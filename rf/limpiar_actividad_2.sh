#!/bin/bash
#===============================================================================
# limpiar_actividad_2.sh
# Revierte el despliegue de la Actividad 2, en orden inverso al de creacion.
#
# Uso: ./limpiar_actividad_2.sh
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP_DIR="$(dirname "$SCRIPT_DIR")"

MASTER="10.0.10.3"
WORKER_CT="10.0.10.1"
WORKER_VM="10.0.10.2"

VLAN_A=100
CIDR_A="192.168.0.0/24"
VLAN_B=200
CIDR_B="192.168.2.0/24"

run() {
    local host="$1" script="$2"; shift 2
    echo ">>> [${host}] ${script} $*"
    ssh "ubuntu@${host}" 'sudo bash -s' < "${IP_DIR}/${script}" "$@"
    echo
}

echo "############ LIMPIEZA DE LA ACTIVIDAD 2 ############"
echo

echo "===== 1. Contenedores (server1) ====="
run "$WORKER_CT" delete_container.sh c100 br-int "$VLAN_A"
run "$WORKER_CT" delete_container.sh c200 br-int "$VLAN_B"

echo "===== 2. Maquinas virtuales (server2) ====="
run "$WORKER_VM" delete_vm.sh vm100 br-int "$VLAN_A" 1
run "$WORKER_VM" delete_vm.sh vm200 br-int "$VLAN_B" 2

echo "===== 3. Salida a internet (master) ====="
run "$MASTER" no_internet_to_network.sh "$VLAN_A" "$CIDR_A"
run "$MASTER" no_internet_to_network.sh "$VLAN_B" "$CIDR_B"

echo "===== 4. Redes VLAN (master) ====="
run "$MASTER" delete_network_vlan.sh "$VLAN_A"
run "$MASTER" delete_network_vlan.sh "$VLAN_B"

echo "############ LIMPIEZA COMPLETADA ############"
