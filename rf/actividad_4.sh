#!/bin/bash
#===============================================================================
# actividad_4.sh
# Reporte Final - Actividad 4: enrutamiento entre redes aisladas.
#
# Topologia identica a la Actividad 3 (DHCP en ambas VLANs, sin salida a
# internet) con la adicion de las reglas que habilitan el trafico entre VLANs.
#
# Uso: ./actividad_4.sh
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP_DIR="$(dirname "$SCRIPT_DIR")"

MASTER="10.0.10.3"
WORKER_CT="10.0.10.1"
WORKER_VM="10.0.10.2"
DATA_IF="ens4"

VLAN_A=100
CIDR_A="192.168.0.0/24"
RANGE_A="192.168.0.10,192.168.0.100"

VLAN_B=200
CIDR_B="192.168.2.0/24"
RANGE_B="192.168.2.10,192.168.2.100"

run() {
    local host="$1" script="$2"; shift 2
    echo ">>> [${host}] ${script} $*"
    ssh "ubuntu@${host}" 'sudo bash -s' < "${IP_DIR}/${script}" "$@"
    echo
}

echo "############ ACTIVIDAD 4: ENRUTAMIENTO ENTRE REDES AISLADAS ############"
echo

echo "===== 1. Inicializacion de nodos ====="
run "$MASTER"    init_master.sh "$DATA_IF"
run "$WORKER_CT" init_worker.sh "$DATA_IF"
run "$WORKER_VM" init_worker.sh "$DATA_IF"

echo "===== 2. Redes VLAN con DHCP (master) ====="
run "$MASTER" create_network_vlan.sh "$VLAN_A" "$CIDR_A" enabled "$RANGE_A"
run "$MASTER" create_network_vlan.sh "$VLAN_B" "$CIDR_B" enabled "$RANGE_B"

echo "===== 3. Sin salida a internet: se garantiza la ausencia de reglas NAT ====="
run "$MASTER" no_internet_to_network.sh "$VLAN_A" "$CIDR_A"
run "$MASTER" no_internet_to_network.sh "$VLAN_B" "$CIDR_B"

echo "===== 4. Maquinas virtuales (server2) ====="
run "$WORKER_VM" create_vm.sh vm100 br-int "$VLAN_A" 1
run "$WORKER_VM" create_vm.sh vm200 br-int "$VLAN_B" 2

echo "===== 5. Contenedores (server1) ====="
run "$WORKER_CT" create_container.sh c100 br-int "$VLAN_A"
run "$WORKER_CT" create_container.sh c200 br-int "$VLAN_B"

echo "===== 6. Estado previo: sin enrutamiento entre VLANs ====="
run "$MASTER" no_routing_networks.sh "$VLAN_A" "$VLAN_B"
echo "--- Prueba de conectividad ANTES de habilitar el enrutamiento ---"
CT200_IP=$(ssh ubuntu@$WORKER_CT "sudo docker exec c200 ip -4 addr show eth_c200 | awk '/inet /{print \$2}' | cut -d/ -f1")
echo "Direccion de c200: $CT200_IP"
if ssh ubuntu@$WORKER_CT "sudo docker exec c100 ping -c2 -W3 $CT200_IP"; then
    echo ">>> INESPERADO: hay conectividad sin las reglas de enrutamiento"
else
    echo ">>> CORRECTO: sin respuesta. La politica FORWARD DROP descarta el trafico."
fi
echo

echo "===== 7. Habilitacion del enrutamiento entre VLANs (master) ====="
run "$MASTER" routing_networks.sh "$VLAN_A" "$VLAN_B"

echo "############ DESPLIEGUE COMPLETADO ############"
echo
echo "NOTA: cirros obtiene direccionamiento por DHCP automaticamente al arrancar."
echo "      Consolas VNC disponibles en los puertos 5901 (vm100) y 5902 (vm200)."
