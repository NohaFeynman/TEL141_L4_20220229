#!/bin/bash
#===============================================================================
# create_container.sh
# Crea un contenedor Docker conectado a una VLAN del OVS mediante par veth.
#
# Uso: sudo ./create_container.sh <nombre> <nombre_ovs> <vlan_id>
# Ej:  ssh ubuntu@10.0.10.1 'sudo bash -s' < ./create_container.sh c100 br-int 100
#===============================================================================
set -euo pipefail

[[ $# -lt 3 ]] && { echo "Uso: $0 <nombre> <nombre_ovs> <vlan_id>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

NAME="$1"
BRIDGE="$2"
VLAN_ID="$3"

VETH_OVS="veth_${NAME}"
VETH_CT="eth_${NAME}"

[[ "$VLAN_ID" =~ ^[0-9]+$ ]] && (( VLAN_ID >= 1 && VLAN_ID <= 4094 )) \
    || { echo "Error: VLAN ID invalido: '$VLAN_ID'." >&2; exit 1; }

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

#--- 2. Par veth: un extremo al OVS, otro al namespace del contenedor -------
if ! ip link show "$VETH_OVS" &>/dev/null; then
    ip link add "$VETH_OVS" type veth peer name "$VETH_CT"
fi

ovs-vsctl --may-exist add-port "$BRIDGE" "$VETH_OVS" tag="$VLAN_ID"
ip link set dev "$VETH_OVS" up

if ip link show "$VETH_CT" &>/dev/null; then
    ip link set "$VETH_CT" netns "$PID"
fi
echo "[OK] Par veth conectado: '$VETH_OVS' (tag $VLAN_ID) <-> '$VETH_CT' en el contenedor."

#--- 3. Configuracion de red dentro del contenedor (DHCP) -------------------
nsenter -t "$PID" -n ip link set dev "$VETH_CT" up
nsenter -t "$PID" -n ip link set dev lo up

docker exec "$NAME" udhcpc -i "$VETH_CT" -q 2>&1 | tail -2 || \
    echo "[WARN] udhcpc no obtuvo direccion. Verifique el servicio DHCP de la VLAN $VLAN_ID." >&2

echo "[OK] Contenedor '$NAME' conectado a la VLAN $VLAN_ID."
docker exec "$NAME" ip addr show "$VETH_CT"
