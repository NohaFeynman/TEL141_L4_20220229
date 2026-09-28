#!/bin/bash
#===============================================================================
# create_vm.sh
# Crea una VM conectada a una VLAN del OVS, con disco COW sobre imagen base.
#
# Uso: sudo ./create_vm.sh <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>
# Ej:  ssh ubuntu@10.0.10.2 'sudo bash -s' < ./create_vm.sh vm1 br-int 100 1
#===============================================================================
set -euo pipefail

BASE_URL="http://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img"
IMG_DIR="/home/ubuntu"
BASE_IMG="${IMG_DIR}/cirros-0.5.1-x86_64-disk.img"
MAC_PREFIX="20:22:02:29"     # derivado del codigo PUCP 20220229
VM_RAM="128"

[[ $# -lt 4 ]] && { echo "Uso: $0 <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

VM_NAME="$1"
BRIDGE="$2"
VLAN_ID="$3"
VNC_PORT="$4"

TAP_IF="${VM_NAME}_tap"
VM_DISK="${IMG_DIR}/${VM_NAME}_img.qcow2"

[[ "$VLAN_ID" =~ ^[0-9]+$ ]] && (( VLAN_ID >= 1 && VLAN_ID <= 4094 )) \
    || { echo "Error: VLAN ID invalido: '$VLAN_ID'." >&2; exit 1; }
[[ "$VNC_PORT" =~ ^[0-9]+$ ]] \
    || { echo "Error: puerto VNC invalido: '$VNC_PORT'." >&2; exit 1; }

ovs-vsctl br-exists "$BRIDGE" \
    || { echo "Error: el bridge '$BRIDGE' no existe. Ejecute init_worker.sh." >&2; exit 1; }

pgrep -f "guest=${VM_NAME}," &>/dev/null \
    && { echo "Error: la VM '$VM_NAME' ya esta en ejecucion." >&2; exit 1; }

#--- 1. Imagen base: descargar si no existiera -------------------------------
if [[ -f "$BASE_IMG" ]]; then
    echo "[OK] Imagen base ya disponible: $BASE_IMG"
else
    echo "[INFO] Imagen base no encontrada. Descargando..."
    wget -q -O "$BASE_IMG" "$BASE_URL" \
        || { echo "Error: fallo la descarga de la imagen base." >&2; rm -f "$BASE_IMG"; exit 1; }
    echo "[OK] Imagen base descargada: $BASE_IMG"
fi

#--- 2. Disco COW de la VM ---------------------------------------------------
if [[ -f "$VM_DISK" ]]; then
    echo "[INFO] El disco '$VM_DISK' ya existe. Se reutiliza."
else
    qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$VM_DISK" >/dev/null
    echo "[OK] Disco COW creado: $VM_DISK (backing file: $BASE_IMG)"
fi

#--- 3. Interfaz TAP conectada al OVS con el tag de VLAN ---------------------
ip link show "$TAP_IF" &>/dev/null || ip tuntap add mode tap name "$TAP_IF"
ovs-vsctl --may-exist add-port "$BRIDGE" "$TAP_IF" tag="$VLAN_ID"
ip link set dev "$TAP_IF" up
echo "[OK] Interfaz TAP '$TAP_IF' conectada a '$BRIDGE' con tag $VLAN_ID."

#--- 4. Direccion MAC derivada de la VLAN y del puerto VNC -------------------
MAC=$(printf "%s:%02x:%02x" "$MAC_PREFIX" $(( VLAN_ID % 256 )) $(( VNC_PORT % 256 )))

#--- 5. Lanzar la VM ---------------------------------------------------------
qemu-system-x86_64 \
    -name "guest=${VM_NAME},debug-threads=on" \
    -enable-kvm \
    -m "$VM_RAM" \
    -vnc "0.0.0.0:${VNC_PORT}" \
    -netdev tap,id=tap1,ifname="$TAP_IF",script=no,downscript=no \
    -device e1000,netdev=tap1,mac="$MAC" \
    -daemonize \
    "$VM_DISK"

echo "[OK] VM '$VM_NAME' iniciada."
echo "[INFO] MAC: $MAC | VNC: puerto $(( 5900 + VNC_PORT )) | VLAN: $VLAN_ID"