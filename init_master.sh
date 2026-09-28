#!/bin/bash
#===============================================================================
# init_master.sh
# Inicializa el nodo master: OVS 'br-int', IPv4 forwarding y politica FORWARD.
#
# Uso: sudo ./init_master.sh <interfaz> [interfaz...]
# Ej:  ssh ubuntu@10.0.10.3 'sudo bash -s' < ./init_master.sh ens4
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

#--- 3. Activar IPv4 forwarding ----------------------------------------------
sysctl -w net.ipv4.ip_forward=1 >/dev/null
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-tel141.conf
echo "[OK] IPv4 forwarding activado (persistente en /etc/sysctl.d/99-tel141.conf)."

#--- 4. Politica por defecto de FORWARD: ACCEPT -> DROP ----------------------
iptables -P FORWARD DROP
echo "[OK] Cadena FORWARD de la tabla filter en politica DROP."

echo "[INFO] Nodo master inicializado: $(hostname)"
