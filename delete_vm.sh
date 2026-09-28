#!/bin/bash
#===============================================================================
# delete_vm.sh
# Elimina una VM y sus recursos. Borra la imagen base si queda sin deltas.
#
# Uso: sudo ./delete_vm.sh <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>
# Ej:  ssh ubuntu@10.0.10.2 'sudo bash -s' < ./delete_vm.sh vm1 br-int 100 1
#===============================================================================
set -euo pipefail

IMG_DIR="/home/ubuntu"
BASE_IMG="${IMG_DIR}/cirros-0.5.1-x86_64-disk.img"

[[ $# -lt 4 ]] && { echo "Uso: $0 <nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>" >&2; exit 1; }
[[ $EUID -ne 0 ]] && { echo "Error: requiere privilegios de root." >&2; exit 1; }

VM_NAME="$1"
BRIDGE="$2"
VLAN_ID="$3"
VNC_PORT="$4"

TAP_IF="${VM_NAME}_tap"
VM_DISK="${IMG_DIR}/${VM_NAME}_img.qcow2"

#--- 1. Detener el proceso QEMU ----------------------------------------------
PIDS=$(pgrep -f "guest=${VM_NAME}," || true)
if [[ -n "$PIDS" ]]; then
    kill $PIDS
    sleep 1
    if pgrep -f "guest=${VM_NAME}," &>/dev/null; then
        kill -9 $PIDS 2>/dev/null || true
        sleep 1
    fi
    echo "[OK] Proceso de la VM '$VM_NAME' detenido."
else
    echo "[INFO] La VM '$VM_NAME' no estaba en ejecucion."
fi

#--- 2. Retirar la interfaz TAP del OVS y del sistema ------------------------
if ovs-vsctl br-exists "$BRIDGE" 2>/dev/null; then
    ovs-vsctl --if-exists del-port "$BRIDGE" "$TAP_IF"
fi

if ip link show "$TAP_IF" &>/dev/null; then
    ip link del "$TAP_IF"
    echo "[OK] Interfaz TAP '$TAP_IF' eliminada."
else
    echo "[INFO] La interfaz TAP '$TAP_IF' no existia."
fi

#--- 3. Eliminar el disco de la VM -------------------------------------------
if [[ -f "$VM_DISK" ]]; then
    rm -f "$VM_DISK"
    echo "[OK] Disco '$VM_DISK' eliminado."
else
    echo "[INFO] El disco '$VM_DISK' no existia."
fi

#--- 4. Eliminar la imagen base si ya no tiene deltas ------------------------
if [[ ! -f "$BASE_IMG" ]]; then
    echo "[INFO] La imagen base no existe."
    exit 0
fi

BASE_REAL=$(readlink -f "$BASE_IMG")
deltas=0

shopt -s nullglob
for disk in "${IMG_DIR}"/*_img.qcow2; do
    [[ "$(readlink -f "$disk")" == "$BASE_REAL" ]] && continue

    # -U permite leer metadatos de discos en uso por QEMU (solo lectura)
    info=$(qemu-img info -U --output=json "$disk" 2>/dev/null) || {
        echo "[WARN] No se pudo inspeccionar '$disk'. La imagen base se conserva por seguridad." >&2
        deltas=$(( deltas + 1 ))
        continue
    }

    backing=$(echo "$info" \
              | grep -o '"backing-filename": *"[^"]*"' \
              | sed 's/.*"backing-filename": *"\([^"]*\)".*/\1/')
    [[ -z "$backing" ]] && continue

    if [[ "$(readlink -f "$backing")" == "$BASE_REAL" ]]; then
        deltas=$(( deltas + 1 ))
    fi
done
shopt -u nullglob

if (( deltas == 0 )); then
    rm -f "$BASE_IMG"
    echo "[OK] Imagen base eliminada: no quedan discos que la referencien."
else
    echo "[INFO] Imagen base conservada: $deltas disco(s) aun la referencian."
fi

echo "[INFO] VM '$VM_NAME' eliminada de $(hostname)."