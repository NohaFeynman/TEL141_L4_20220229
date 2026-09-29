#!/bin/bash
#===============================================================================
# verificar_actividad_4.sh
# Verificacion del enrutamiento entre redes aisladas (Actividad 4).
#===============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IP_DIR="$(dirname "$SCRIPT_DIR")"

MASTER="10.0.10.3"
WORKER_CT="10.0.10.1"
WORKER_VM="10.0.10.2"

VLAN_A=100
VLAN_B=200

sep() { echo; echo "----- $* -----"; }

run() {
    local host="$1" script="$2"; shift 2
    echo ">>> [${host}] ${script} $*"
    ssh "ubuntu@${host}" 'sudo bash -s' < "${IP_DIR}/${script}" "$@"
}

echo "############ VERIFICACION - ACTIVIDAD 4 ############"
echo "Fecha: $(date)"

sep "Master (server3): topologia OVS"
ssh ubuntu@$MASTER 'hostname; sudo ovs-vsctl show'

sep "Master: servicio DHCP en ambas VLANs"
ssh ubuntu@$MASTER 'sudo ip netns list; echo "Procesos DHCP activos: $(pgrep -cx dnsmasq)"'

sep "Master: reglas de enrutamiento entre VLANs y ausencia de NAT"
ssh ubuntu@$MASTER 'sudo iptables -S FORWARD; echo; sudo iptables -t nat -S POSTROUTING'

sep "Master: reenvio IPv4 habilitado"
ssh ubuntu@$MASTER 'echo "net.ipv4.ip_forward = $(sysctl -n net.ipv4.ip_forward)"'

sep "Workers: topologia OVS"
ssh ubuntu@$WORKER_VM 'hostname; sudo ovs-vsctl show'
ssh ubuntu@$WORKER_CT 'hostname; sudo ovs-vsctl show'

sep "Direccionamiento obtenido por DHCP"
ssh ubuntu@$WORKER_CT 'echo "-- c100 --"; sudo docker exec c100 ip addr show eth_c100 | grep "inet "; sudo docker exec c100 ip route'
ssh ubuntu@$WORKER_CT 'echo "-- c200 --"; sudo docker exec c200 ip addr show eth_c200 | grep "inet "; sudo docker exec c200 ip route'

sep "Master: leases entregados"
ssh ubuntu@$MASTER 'sudo cat /var/lib/misc/dnsmasq-vlan100.leases /var/lib/misc/dnsmasq-vlan200.leases'

#--- Direcciones reales de los contenedores ---------------------------------
IP_C100=$(ssh ubuntu@$WORKER_CT "sudo docker exec c100 ip -4 addr show eth_c100 | awk '/inet /{print \$2}' | cut -d/ -f1")
IP_C200=$(ssh ubuntu@$WORKER_CT "sudo docker exec c200 ip -4 addr show eth_c200 | awk '/inet /{print \$2}' | cut -d/ -f1")

sep "Direcciones en uso"
echo "c100 (VLAN $VLAN_A): $IP_C100"
echo "c200 (VLAN $VLAN_B): $IP_C200"

sep "CON enrutamiento: c100 -> c200 (esperado: exito)"
if ssh ubuntu@$WORKER_CT "sudo docker exec c100 ping -c3 -W3 $IP_C200"; then
    echo ">>> CORRECTO: el trafico entre VLANs es reenviado por server3."
else
    echo ">>> ATENCION: sin respuesta pese a las reglas de enrutamiento."
fi

sep "CON enrutamiento: c200 -> c100 (esperado: exito)"
ssh ubuntu@$WORKER_CT "sudo docker exec c200 ping -c3 -W3 $IP_C100"

sep "Contadores de las reglas de enrutamiento"
ssh ubuntu@$MASTER 'sudo iptables -L FORWARD -n -v'

sep "Sin salida a internet (esperado: SIN respuesta)"
if ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ping -c2 -W3 8.8.8.8'; then
    echo ">>> ATENCION: existe salida a internet"
else
    echo ">>> CORRECTO: el enrutamiento entre VLANs no implica salida a internet."
fi

sep "Reversion: eliminacion de las reglas de enrutamiento"
run "$MASTER" no_routing_networks.sh "$VLAN_A" "$VLAN_B"
ssh ubuntu@$MASTER 'sudo iptables -S FORWARD'

sep "SIN enrutamiento: c100 -> c200 (esperado: SIN respuesta)"
if ssh ubuntu@$WORKER_CT "sudo docker exec c100 ping -c2 -W3 $IP_C200"; then
    echo ">>> ATENCION: persiste la conectividad tras eliminar las reglas."
else
    echo ">>> CORRECTO: al retirar las reglas ACCEPT, la politica DROP vuelve"
    echo "    a descartar el trafico. El control reside en el filtrado de capa 3."
fi

sep "Restauracion del enrutamiento"
run "$MASTER" routing_networks.sh "$VLAN_A" "$VLAN_B"
ssh ubuntu@$WORKER_CT "sudo docker exec c100 ping -c2 -W3 $IP_C200"

echo
echo "############ FIN DE LA VERIFICACION ############"
