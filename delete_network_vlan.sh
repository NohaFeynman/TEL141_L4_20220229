#!/bin/bash
#===============================================================================
# delete_network_vlan.sh
# Elimina una red VLAN: servicio DHCP, namespace, puertos internos.
#
# Uso: sudo ./delete_network_vlan.sh <vlan_id>
# Ej:  ssh ubuntu@10.0.10.3 'sudo bash -s' < ./delete_network_vlan.sh 100
#===============================================================================
set -euo pipefail

BRIDGE="br-int"

[[ $# -lt 1 ]] && { echo "Uso: $0 <vlan_id>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

VLAN_ID="$1"

[[ "$VLAN_ID" =~ ^[0-9]+$ ]] && (( VLAN_ID >= 1 && VLAN_ID <= 4094 )) \
    || { echo "Error: VLAN ID invalido: '$VLAN_ID'." >&2; exit 1; }

GW_IF="gw_vlan${VLAN_ID}"
DHCP_IF="dhcp_vlan${VLAN_ID}"
NS="ns-dhcp-vlan${VLAN_ID}"
PIDFILE="/var/run/dnsmasq-vlan${VLAN_ID}.pid"
LEASEFILE="/var/lib/misc/dnsmasq-vlan${VLAN_ID}.leases"

#--- 1. Detener el servicio DHCP --------------------------------------------
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")"
    echo "[OK] Servicio dnsmasq de la VLAN $VLAN_ID detenido."
else
    echo "[INFO] No habia dnsmasq activo para la VLAN $VLAN_ID."
fi
rm -f "$PIDFILE" "$LEASEFILE"

#--- 2. Retirar el puerto DHCP del OVS y eliminar el namespace --------------
if ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    ovs-vsctl --if-exists del-port "$BRIDGE" "$DHCP_IF"
fi

if ip netns list | grep -qw "$NS"; then
    ip netns del "$NS"
    echo "[OK] Namespace '$NS' eliminado."
else
    echo "[INFO] El namespace '$NS' no existia."
fi

#--- 3. Retirar el puerto de gateway ----------------------------------------
if ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    ovs-vsctl --if-exists del-port "$BRIDGE" "$GW_IF"
    echo "[OK] Puerto '$GW_IF' retirado de '$BRIDGE'."
fi

if ip link show "$GW_IF" &>/dev/null; then
    ip link del "$GW_IF"
fi

echo "[INFO] Red VLAN $VLAN_ID eliminada de $(hostname)."
