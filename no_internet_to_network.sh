#!/bin/bash
#===============================================================================
# no_internet_to_network.sh
# Elimina la salida a internet de una VLAN.
#
# Uso: sudo ./no_internet_to_network.sh <vlan_id> <cidr>
#===============================================================================
set -euo pipefail

WAN_IF="${WAN_IF:-ens3}"

[[ $# -lt 2 ]] && { echo "Uso: $0 <vlan_id> <cidr>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

VLAN_ID="$1"
CIDR="$2"
GW_IF="gw_vlan${VLAN_ID}"

[[ "$CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] \
    || { echo "Error: CIDR invalido: '$CIDR'." >&2; exit 1; }

#--- Las especificaciones replican exactamente las de internet_to_network.sh -
NAT_RULE=(-t nat POSTROUTING -s "$CIDR" -o "$WAN_IF" -j MASQUERADE)
FWD_OUT=(FORWARD -i "$GW_IF" -o "$WAN_IF" -j ACCEPT)
FWD_IN=(FORWARD -i "$WAN_IF" -o "$GW_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT)

if iptables -C "${NAT_RULE[@]}" 2>/dev/null; then
    iptables -D "${NAT_RULE[@]}"
    echo "[OK] MASQUERADE eliminado para $CIDR."
else
    echo "[INFO] No existia regla MASQUERADE para $CIDR."
fi

for rule in FWD_OUT FWD_IN; do
    declare -n r="$rule"
    if iptables -C "${r[@]}" 2>/dev/null; then
        iptables -D "${r[@]}"
    fi
done
echo "[OK] Reglas de reenvio hacia '$WAN_IF' eliminadas para la VLAN $VLAN_ID."

echo "[INFO] Salida a internet deshabilitada para la VLAN $VLAN_ID."
