#!/bin/bash
#===============================================================================
# actividad_1.sh
# Reporte Final - Actividad 1: redes aisladas con DHCP y con salida a internet.
#
# Despliega la topologia completa desde el nodo orquestador (server4),
# empleando los scripts desarrollados en el informe previo.
#
# Uso: ./actividad_1.sh
#===============================================================================
set -euo pipefail

#--- Los scripts del informe previo estan en el directorio padre -------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP_DIR="$(dirname "$SCRIPT_DIR")"

MASTER="10.0.10.3"      # server3: gateways, DHCP, NAT
WORKER_CT="10.0.10.1"   # server1: contenedores
WORKER_VM="10.0.10.2"   # server2: maquinas virtuales
DATA_IF="ens4"

VLAN_A=100
CIDR_A="192.168.0.0/24"
RANGE_A="192.168.0.10,192.168.0.100"

VLAN_B=200
CIDR_B="192.168.2.0/24"
RANGE_B="192.168.2.10,192.168.2.100"

#--- Ejecucion remota: el script viaja por stdin, no se copia al nodo -------
run() {  # run <ip> <script> [args...]
    local host="$1" script="$2"; shift 2
    echo ">>> [${host}] ${script} $*"
    ssh "ubuntu@${host}" 'sudo bash -s' < "${IP_DIR}/${script}" "$@"
    echo
}

echo "==== ACTIVIDAD 1: REDES AISLADAS CON DHCP Y SALIDA A INTERNET ===="
echo

echo "--- 1. Inicializacion de nodos ---"
run "$MASTER"    init_master.sh "$DATA_IF"
run "$WORKER_CT" init_worker.sh "$DATA_IF"
run "$WORKER_VM" init_worker.sh "$DATA_IF"

echo "--- 2. Redes VLAN con DHCP (master) ---"
run "$MASTER" create_network_vlan.sh "$VLAN_A" "$CIDR_A" enabled "$RANGE_A"
run "$MASTER" create_network_vlan.sh "$VLAN_B" "$CIDR_B" enabled "$RANGE_B"

echo "--- 3. Salida a internet (master) ---"
run "$MASTER" internet_to_network.sh "$VLAN_A" "$CIDR_A"
run "$MASTER" internet_to_network.sh "$VLAN_B" "$CIDR_B"

echo "--- 4. Maquinas virtuales (server2) ---"
run "$WORKER_VM" create_vm.sh vm100 br-int "$VLAN_A" 1
run "$WORKER_VM" create_vm.sh vm200 br-int "$VLAN_B" 2

echo "--- 5. Contenedores (server1) ---"
run "$WORKER_CT" create_container.sh c100 br-int "$VLAN_A"
run "$WORKER_CT" create_container.sh c200 br-int "$VLAN_B"

echo "=== DESPLIEGUE COMPLETADO ==="
