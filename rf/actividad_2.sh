#!/bin/bash
#===============================================================================
# actividad_2.sh
# Reporte Final - Actividad 2: redes aisladas sin DHCP y con salida a internet.
#
# Uso: ./actividad_2.sh
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
GW_A="192.168.0.1"

VLAN_B=200
CIDR_B="192.168.2.0/24"
GW_B="192.168.2.1"

run() {
    local host="$1" script="$2"; shift 2
    echo ">>> [${host}] ${script} $*"
    ssh "ubuntu@${host}" 'sudo bash -s' < "${IP_DIR}/${script}" "$@"
    echo
}

echo "############ ACTIVIDAD 2: REDES AISLADAS SIN DHCP Y SALIDA A INTERNET ############"
echo

echo "===== 1. Inicializacion de nodos ====="
run "$MASTER"    init_master.sh "$DATA_IF"
run "$WORKER_CT" init_worker.sh "$DATA_IF"
run "$WORKER_VM" init_worker.sh "$DATA_IF"

echo "===== 2. Redes VLAN sin DHCP (master) ====="
run "$MASTER" create_network_vlan.sh "$VLAN_A" "$CIDR_A" disabled
run "$MASTER" create_network_vlan.sh "$VLAN_B" "$CIDR_B" disabled

echo "===== 3. Salida a internet (master) ====="
run "$MASTER" internet_to_network.sh "$VLAN_A" "$CIDR_A"
run "$MASTER" internet_to_network.sh "$VLAN_B" "$CIDR_B"

echo "===== 4. Maquinas virtuales (server2) ====="
run "$WORKER_VM" create_vm.sh vm100 br-int "$VLAN_A" 1
run "$WORKER_VM" create_vm.sh vm200 br-int "$VLAN_B" 2

echo "===== 5. Contenedores con direccionamiento estatico (server1) ====="
run "$WORKER_CT" create_container_static.sh c100 br-int "$VLAN_A" 192.168.0.11/24 "$GW_A"
run "$WORKER_CT" create_container_static.sh c200 br-int "$VLAN_B" 192.168.2.11/24 "$GW_B"

echo "############ DESPLIEGUE COMPLETADO ############"
echo
echo "NOTA: las VMs requieren configuracion manual por VNC (puertos 5901 y 5902):"
echo "  VLAN 100:  sudo ip addr add 192.168.0.10/24 dev eth0"
echo "             sudo ip link set eth0 up"
echo "             sudo ip route add default via ${GW_A}"
echo "  VLAN 200:  sudo ip addr add 192.168.2.10/24 dev eth0"
echo "             sudo ip link set eth0 up"
echo "             sudo ip route add default via ${GW_B}"
