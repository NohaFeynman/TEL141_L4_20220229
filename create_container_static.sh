#!/bin/bash
#===============================================================================
# create_container_static.sh
# Crea un contenedor Docker conectado a una VLAN del OVS, con IP estatica.
#
# Uso: sudo ./create_container_static.sh <nombre> <ovs> <vlan_id> <ip/cidr> <gateway>
# Ej:  ssh ubuntu@10.0.10.1 'sudo bash -s' < ./create_container_static.sh \
#          c100 br-int 100 192.168.0.11/24 192.168.0.1
#===============================================================================
set -euo pipefail

[[ $# -lt 5 ]] && { echo "Uso: $0 <nombre> <ovs> <vlan_id> <ip/cidr> <gateway>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

NAME="$1"
BRIDGE="$2"
VLAN_ID="$3"
IP_CIDR="$4"
GATEWAY="$5"

VETH_OVS="veth_${NAME}"
VETH_CT="eth_${NAME}"

[[ "$VLAN_ID" =~ ^[0-9]+$ ]] && (( VLAN_ID >= 1 && VLAN_ID <= 4094 )) \
    || { echo "Error: VLAN ID invalido: '$VLAN_ID'." >&2; exit 1; }

[[ "$IP_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] \
    || { echo "Error: direccion invalida: '$IP_CIDR'." >&2; exit 1; }

ovs-vsctl br-exists "$BRIDGE" \
    || { echo "Error: el bridge '$BRIDGE' no existe. Ejecute init_worker.sh." >&2; exit 1; }

#--- 1. Contenedor sin red Docker -------------------------------------------
if docker inspect "$NAME" &>/dev/null; then
    echo "[INFO] El contenedor '$NAME' ya existe. Se reutiliza."
else
    docker run -d --network none --name "$NAME" \
        --cap-add=NET_ADMIN alpine sleep infinity >/dev/null
    echo "[OK] Contenedor '$NAME' creado (sin red Docker)."
fi

PID=$(docker inspect -f '{{.State.Pid}}' "$NAME")

#--- 2. Par veth --------------------------------------------------------------
if ! ip link show "$VETH_OVS" &>/dev/null; then
    ip link add "$VETH_OVS" type veth peer name "$VETH_CT"
fi

ovs-vsctl --may-exist add-port "$BRIDGE" "$VETH_OVS" tag="$VLAN_ID"
ip link set dev "$VETH_OVS" up

if ip link show "$VETH_CT" &>/dev/null; then
    ip link set "$VETH_CT" netns "$PID"
fi
echo "[OK] Par veth conectado: '$VETH_OVS' (tag $VLAN_ID)."

#--- 3. Direccionamiento estatico dentro del contenedor ---------------------
nsenter -t "$PID" -n ip link set dev lo up
nsenter -t "$PID" -n ip link set dev "$VETH_CT" up
nsenter -t "$PID" -n ip addr replace "$IP_CIDR" dev "$VETH_CT"
nsenter -t "$PID" -n ip route replace default via "$GATEWAY"

echo "[OK] Contenedor '$NAME': $IP_CIDR, gateway $GATEWAY, VLAN $VLAN_ID."
nsenter -t "$PID" -n ip addr show "$VETH_CT"
nsenter -t "$PID" -n ip route
