#!/bin/bash
#===============================================================================
# internet_to_network.sh
# Habilita la salida a internet de una VLAN mediante masquerading.
#
# Uso: sudo ./internet_to_network.sh <vlan_id> <cidr>
# Ej:  ssh ubuntu@10.0.10.3 'sudo bash -s' < ./internet_to_network.sh 100 192.168.0.0/24
#===============================================================================
set -euo pipefail

WAN_IF="${WAN_IF:-ens3}"   # interfaz con salida a internet

[[ $# -lt 2 ]] && { echo "Uso: $0 <vlan_id> <cidr>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

VLAN_ID="$1"
CIDR="$2"
GW_IF="gw_vlan${VLAN_ID}"

[[ "$CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] \
    || { echo "Error: CIDR invalido: '$CIDR'." >&2; exit 1; }

ip link show "$GW_IF" &>/dev/null \
    || { echo "Error: la interfaz '$GW_IF' no existe. Ejecute create_network_vlan.sh." >&2; exit 1; }

#--- 1. NAT de salida: enmascarar el origen con la IP de la interfaz WAN -----
NAT_RULE=(POSTROUTING -s "$CIDR" -o "$WAN_IF" -j MASQUERADE)
iptables -t nat -C "${NAT_RULE[@]}" 2>/dev/null || iptables -t nat -A "${NAT_RULE[@]}"
echo "[OK] MASQUERADE activo para $CIDR por '$WAN_IF'."

#--- 2. Autorizar el reenvio de salida y el retorno de conexiones establecidas
FWD_OUT=(FORWARD -i "$GW_IF" -o "$WAN_IF" -j ACCEPT)
iptables -C "${FWD_OUT[@]}" 2>/dev/null || iptables -A "${FWD_OUT[@]}"

FWD_IN=(FORWARD -i "$WAN_IF" -o "$GW_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT)
iptables -C "${FWD_IN[@]}" 2>/dev/null || iptables -A "${FWD_IN[@]}"

echo "[OK] Reenvio autorizado entre '$GW_IF' y '$WAN_IF'."
echo "[INFO] Salida a internet habilitada para la VLAN $VLAN_ID."
