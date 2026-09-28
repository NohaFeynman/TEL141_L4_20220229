#!/bin/bash
#===============================================================================
# create_network_vlan.sh
# Crea una red VLAN sobre el OVS 'br-int': gateway y, opcionalmente, DHCP.
#
# Uso: sudo ./create_network_vlan.sh <vlan_id> <cidr> <dhcp> [rango]
#   <vlan_id>  Identificador de VLAN (1-4094)
#   <cidr>     Direccion de red en formato CIDR (ej. 192.168.0.0/24)
#   <dhcp>     'enabled' o 'disabled'
#   [rango]    Rango DHCP 'inicio,fin' (requerido si dhcp=enabled)
#
# Ej: ssh ubuntu@10.0.10.3 'sudo bash -s' < ./create_network_vlan.sh \
#         100 192.168.0.0/24 enabled 192.168.0.10,192.168.0.100
#===============================================================================
set -euo pipefail

BRIDGE="br-int"

usage() {
    echo "Uso: $0 <vlan_id> <cidr> <enabled|disabled> [inicio,fin]" >&2
    exit 1
}

#--- Conversion de direcciones IPv4 a entero y viceversa ---------------------
ip2int() {
    local IFS='.'; read -r a b c d <<< "$1"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

int2ip() {
    local n=$1
    echo "$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 )).$(( n & 255 ))"
}

prefix2mask() {
    local p=$1
    int2ip $(( 0xFFFFFFFF ^ ((1 << (32 - p)) - 1) ))
}

#--- Espera a que OVS materialice el netdev interno --------------------------
wait_for_iface() {
    local iface="$1" timeout=50
    while (( timeout-- > 0 )); do
        ip link show "$iface" &>/dev/null && return 0
        sleep 0.1
    done
    echo "Error: la interfaz '$iface' no fue creada por OVS." >&2
    return 1
}

#--- Validacion de parametros ------------------------------------------------
[[ $# -lt 3 ]] && usage
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

VLAN_ID="$1"
CIDR="$2"
DHCP="$3"
RANGE="${4:-}"

[[ "$VLAN_ID" =~ ^[0-9]+$ ]] && (( VLAN_ID >= 1 && VLAN_ID <= 4094 )) \
    || { echo "Error: VLAN ID invalido: '$VLAN_ID'." >&2; exit 1; }

[[ "$CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] \
    || { echo "Error: CIDR invalido: '$CIDR'." >&2; exit 1; }

case "$DHCP" in
    enabled|disabled) ;;
    *) echo "Error: el tercer parametro debe ser 'enabled' o 'disabled'." >&2; exit 1 ;;
esac

[[ "$DHCP" == "enabled" && -z "$RANGE" ]] \
    && { echo "Error: DHCP habilitado requiere el rango de direcciones." >&2; exit 1; }

ovs-vsctl br-exists "$BRIDGE" \
    || { echo "Error: el bridge '$BRIDGE' no existe. Ejecute init_master.sh." >&2; exit 1; }

#--- Calculo de direcciones --------------------------------------------------
NET_ADDR="${CIDR%/*}"
PREFIX="${CIDR#*/}"
NETMASK=$(prefix2mask "$PREFIX")
NET_INT=$(ip2int "$NET_ADDR")

GW_IP=$(int2ip $(( NET_INT + 1 )))      # primera direccion: gateway
DHCP_IP=$(int2ip $(( NET_INT + 2 )))    # segunda direccion: servidor DHCP

GW_IF="gw_vlan${VLAN_ID}"
DHCP_IF="dhcp_vlan${VLAN_ID}"
NS="ns-dhcp-vlan${VLAN_ID}"
PIDFILE="/var/run/dnsmasq-vlan${VLAN_ID}.pid"
LEASEFILE="/var/lib/misc/dnsmasq-vlan${VLAN_ID}.leases"

echo "[INFO] VLAN $VLAN_ID | red $CIDR | mascara $NETMASK"
echo "[INFO] Gateway: $GW_IP  |  DHCP: $DHCP"

#--- 1. Puerto interno de gateway en el namespace raiz -----------------------
ovs-vsctl --may-exist add-port "$BRIDGE" "$GW_IF" tag="$VLAN_ID" \
    -- set interface "$GW_IF" type=internal

wait_for_iface "$GW_IF"
ip addr replace "${GW_IP}/${PREFIX}" dev "$GW_IF"
ip link set "$GW_IF" up
echo "[OK] Interfaz '$GW_IF' creada con tag $VLAN_ID y direccion $GW_IP/$PREFIX."

#--- 2. Servicio DHCP en namespace dedicado ----------------------------------
if [[ "$DHCP" == "disabled" ]]; then
    echo "[INFO] DHCP deshabilitado para la VLAN $VLAN_ID."
    echo "[INFO] Red VLAN $VLAN_ID creada en $(hostname)."
    exit 0
fi

RANGE_START="${RANGE%,*}"
RANGE_END="${RANGE#*,}"

[[ "$RANGE_START" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && \
   "$RANGE_END"   =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
    || { echo "Error: rango DHCP invalido: '$RANGE'." >&2; exit 1; }

# Detener una instancia previa de dnsmasq para esta VLAN
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")"
    echo "[OK] Instancia previa de dnsmasq para la VLAN $VLAN_ID detenida."
fi

# Namespace
ip netns list | grep -qw "$NS" || ip netns add "$NS"
ip netns exec "$NS" ip link set lo up
echo "[OK] Namespace '$NS' disponible."

# Puerto interno para el servicio DHCP, trasladado al namespace
ovs-vsctl --may-exist add-port "$BRIDGE" "$DHCP_IF" tag="$VLAN_ID" \
    -- set interface "$DHCP_IF" type=internal

if ip link show "$DHCP_IF" &>/dev/null; then
    wait_for_iface "$DHCP_IF"
    ip link set "$DHCP_IF" netns "$NS"
fi

ip netns exec "$NS" ip addr replace "${DHCP_IP}/${PREFIX}" dev "$DHCP_IF"
ip netns exec "$NS" ip link set "$DHCP_IF" up
echo "[OK] Interfaz '$DHCP_IF' en '$NS' con direccion $DHCP_IP/$PREFIX."

# dnsmasq: solo DHCP, atado a la interfaz del namespace
mkdir -p "$(dirname "$LEASEFILE")"
ip netns exec "$NS" dnsmasq \
    --conf-file=/dev/null \
    --no-resolv --no-hosts \
    --bind-interfaces \
    --interface="$DHCP_IF" \
    --except-interface=lo \
    --listen-address="$DHCP_IP" \
    --dhcp-range="${RANGE_START},${RANGE_END},${NETMASK},12h" \
    --dhcp-option=3,"$GW_IP" \
    --dhcp-option=6,8.8.8.8 \
    --dhcp-authoritative \
    --pid-file="$PIDFILE" \
    --dhcp-leasefile="$LEASEFILE"

echo "[OK] dnsmasq activo en '$NS': rango ${RANGE_START}-${RANGE_END}, gateway $GW_IP."
echo "[INFO] Red VLAN $VLAN_ID creada en $(hostname)."
