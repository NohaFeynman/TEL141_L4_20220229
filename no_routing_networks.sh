#!/bin/bash
#===============================================================================
# no_routing_networks.sh
# Elimina el enrutamiento entre dos VLANs.
#
# Uso: sudo ./no_routing_networks.sh <vlan_id_1> <vlan_id_2>
# Ej:  ssh ubuntu@10.0.10.3 'sudo bash -s' < ./no_routing_networks.sh 100 200
#===============================================================================
set -euo pipefail

[[ $# -lt 2 ]] && { echo "Uso: $0 <vlan_id_1> <vlan_id_2>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

VLAN_A="$1"
VLAN_B="$2"
IF_A="gw_vlan${VLAN_A}"
IF_B="gw_vlan${VLAN_B}"

#--- Las especificaciones replican exactamente las de routing_networks.sh ----
RULE_AB=(FORWARD -i "$IF_A" -o "$IF_B" -j ACCEPT)
RULE_BA=(FORWARD -i "$IF_B" -o "$IF_A" -j ACCEPT)

removed=0

if iptables -C "${RULE_AB[@]}" 2>/dev/null; then
    iptables -D "${RULE_AB[@]}"
    (( removed++ )) || true
fi

if iptables -C "${RULE_BA[@]}" 2>/dev/null; then
    iptables -D "${RULE_BA[@]}"
    (( removed++ )) || true
fi

if (( removed > 0 )); then
    echo "[OK] Enrutamiento eliminado entre VLAN $VLAN_A y VLAN $VLAN_B ($removed reglas)."
else
    echo "[INFO] No existian reglas de enrutamiento entre VLAN $VLAN_A y VLAN $VLAN_B."
fi