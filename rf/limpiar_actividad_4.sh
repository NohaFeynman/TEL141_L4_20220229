#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP_DIR="$(dirname "$SCRIPT_DIR")"
MASTER="10.0.10.3"; WORKER_CT="10.0.10.1"; WORKER_VM="10.0.10.2"

run() {
    local host="$1" script="$2"; shift 2
    echo ">>> [${host}] ${script} $*"
    ssh "ubuntu@${host}" 'sudo bash -s' < "${IP_DIR}/${script}" "$@"
    echo
}

echo "############ LIMPIEZA DE LA ACTIVIDAD 4 ############"
echo
echo "===== 1. Enrutamiento entre VLANs (master) ====="
run "$MASTER" no_routing_networks.sh 100 200
echo "===== 2. Contenedores (server1) ====="
run "$WORKER_CT" delete_container.sh c100 br-int 100
run "$WORKER_CT" delete_container.sh c200 br-int 200
echo "===== 3. Maquinas virtuales (server2) ====="
run "$WORKER_VM" delete_vm.sh vm100 br-int 100 1
run "$WORKER_VM" delete_vm.sh vm200 br-int 200 2
echo "===== 4. Redes VLAN (master) ====="
run "$MASTER" delete_network_vlan.sh 100
run "$MASTER" delete_network_vlan.sh 200
echo "############ LIMPIEZA COMPLETADA ############"
