#!/bin/bash
#===============================================================================
# routing_networks.sh
# Habilita el enrutamiento bidireccional entre dos VLANs.
#
# Uso: sudo ./routing_networks.sh <vlan_id_1> <vlan_id_2>
# Ej:  ssh ubuntu@10.0.10.3 'sudo bash -s' < ./routing_networks.sh 100 200
#===============================================================================
set -euo pipefail

[[ $# -lt 2 ]] && { echo "Uso: $0 <vlan_id_1> <vlan_id_2>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

VLAN_A="$1"
VLAN_B="$2"
IF_A="gw_vlan${VLAN_A}"
IF_B="gw_vlan${VLAN_B}"

[[ "$VLAN_A" == "$VLAN_B" ]] && { echo "Error: las VLANs deben ser distintas." >&2; exit 1; }

for iface in "$IF_A" "$IF_B"; do
    ip link show "$iface" &>/dev/null \
        || { echo "Error: la interfaz '$iface' no existe." >&2; exit 1; }
done

RULE_AB=(FORWARD -i "$IF_A" -o "$IF_B" -j ACCEPT)
RULE_BA=(FORWARD -i "$IF_B" -o "$IF_A" -j ACCEPT)

iptables -C "${RULE_AB[@]}" 2>/dev/null || iptables -A "${RULE_AB[@]}"
iptables -C "${RULE_BA[@]}" 2>/dev/null || iptables -A "${RULE_BA[@]}"

echo "[OK] Enrutamiento habilitado entre VLAN $VLAN_A y VLAN $VLAN_B."
