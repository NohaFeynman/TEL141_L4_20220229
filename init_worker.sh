#!/bin/bash
#===============================================================================
# init_worker.sh
# Inicializa un nodo worker: OVS 'br-int' y conexion de interfaces.
#
# Uso: sudo ./init_worker.sh <interfaz> [interfaz...]
# Ej:  ssh ubuntu@10.0.10.1 'sudo bash -s' < ./init_worker.sh ens4
#===============================================================================
set -euo pipefail

BRIDGE="br-int"

usage() {
    echo "Uso: $0 <interfaz> [interfaz...]" >&2
    echo "  <interfaz>  Interfaz de red a conectar al OVS '$BRIDGE'." >&2
    exit 1
}

[[ $# -lt 1 ]] && usage
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

#--- 1. Crear el OVS 'br-int' si no existiera --------------------------------
ovs-vsctl --may-exist add-br "$BRIDGE"
ip link set "$BRIDGE" up
echo "[OK] Bridge OVS '$BRIDGE' disponible."

#--- 2. Conectar las interfaces provistas ------------------------------------
for iface in "$@"; do
    if ! ip link show "$iface" &>/dev/null; then
        echo "[WARN] La interfaz '$iface' no existe. Se omite." >&2
        continue
    fi

    if ip -4 addr show "$iface" | grep -q 'inet '; then
        echo "[ERROR] '$iface' tiene una direccion IPv4 asignada." >&2
        echo "        Conectarla al bridge interrumpiria la conectividad. Se omite." >&2
        continue
    fi

    ovs-vsctl --may-exist add-port "$BRIDGE" "$iface"
    ip link set "$iface" up
    echo "[OK] Interfaz '$iface' conectada a '$BRIDGE'."
done

echo "[INFO] Nodo worker inicializado: $(hostname)"
