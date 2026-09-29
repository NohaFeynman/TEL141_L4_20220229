#!/bin/bash
#===============================================================================
# delete_container.sh
# Elimina un contenedor y su par veth.
#
# Uso: sudo ./delete_container.sh <nombre> <nombre_ovs> <vlan_id>
#===============================================================================
set -euo pipefail

[[ $# -lt 3 ]] && { echo "Uso: $0 <nombre> <nombre_ovs> <vlan_id>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

NAME="$1"
BRIDGE="$2"
VLAN_ID="$3"
VETH_OVS="veth_${NAME}"

if ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    ovs-vsctl --if-exists del-port "$BRIDGE" "$VETH_OVS"
fi

if docker inspect "$NAME" &>/dev/null; then
    docker rm -f "$NAME" >/dev/null
    echo "[OK] Contenedor '$NAME' eliminado."
else
    echo "[INFO] El contenedor '$NAME' no existia."
fi

if ip link show "$VETH_OVS" &>/dev/null; then
    ip link del "$VETH_OVS"
    echo "[OK] Interfaz '$VETH_OVS' eliminada."
fi

echo "[INFO] Contenedor '$NAME' eliminado de $(hostname)."
