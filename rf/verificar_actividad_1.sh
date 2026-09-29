#!/bin/bash
#===============================================================================
# verificar_actividad_1.sh
# Verificacion de la topologia desplegada en la Actividad 1.
#===============================================================================
set -uo pipefail

MASTER="10.0.10.3"
WORKER_CT="10.0.10.1"
WORKER_VM="10.0.10.2"

sep() { echo; echo "----- $* -----"; }

echo "############ VERIFICACION - ACTIVIDAD 1 ############"
echo "Fecha: $(date)"

sep "Master (server3): topologia OVS"
ssh ubuntu@$MASTER 'hostname; sudo ovs-vsctl show'

sep "Master: servicio DHCP activo (esperado: 2 namespaces, 2 procesos)"
ssh ubuntu@$MASTER 'sudo ip netns list; echo "Procesos DHCP activos: $(pgrep -cx dnsmasq)"'

sep "Master: interfaces DHCP dentro de cada namespace"
ssh ubuntu@$MASTER 'sudo ip netns exec ns-dhcp-vlan100 ip -br addr; sudo ip netns exec ns-dhcp-vlan200 ip -br addr'

sep "Master: reglas de NAT y de reenvio hacia internet"
ssh ubuntu@$MASTER 'sudo iptables -S FORWARD; echo; sudo iptables -t nat -S POSTROUTING'

sep "Master: reenvio IPv4 habilitado"
ssh ubuntu@$MASTER 'echo "net.ipv4.ip_forward = $(sysctl -n net.ipv4.ip_forward)"'

sep "Worker server2: topologia OVS y maquinas virtuales"
ssh ubuntu@$WORKER_VM 'hostname; sudo ovs-vsctl show; pgrep -af qemu-system-x86_64 | cut -c1-100'

sep "Worker server1: topologia OVS y contenedores"
ssh ubuntu@$WORKER_CT 'hostname; sudo ovs-vsctl show; sudo docker ps --format "{{.Names}} {{.Status}}"'

sep "Direccionamiento obtenido por DHCP"
ssh ubuntu@$WORKER_CT 'echo "-- c100 --"; sudo docker exec c100 ip addr show eth_c100 | grep "inet "; sudo docker exec c100 ip route'
ssh ubuntu@$WORKER_CT 'echo "-- c200 --"; sudo docker exec c200 ip addr show eth_c200 | grep "inet "; sudo docker exec c200 ip route'

sep "Master: leases entregados por los servidores DHCP"
ssh ubuntu@$MASTER 'sudo cat /var/lib/misc/dnsmasq-vlan100.leases /var/lib/misc/dnsmasq-vlan200.leases'

IP_C200=$(ssh ubuntu@$WORKER_CT "sudo docker exec c200 ip -4 addr show eth_c200 | awk '/inet /{print \$2}' | cut -d/ -f1")

sep "c100 -> gateway VLAN 100 (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ping -c2 -W2 192.168.0.1'

sep "c200 -> gateway VLAN 200 (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c200 ping -c2 -W2 192.168.2.1'

sep "c100 -> internet (esperado: exito)"
if ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ping -c3 -W3 8.8.8.8'; then
    echo ">>> CORRECTO: el trafico sale enmascarado por ens3 y el retorno es"
    echo "    autorizado por la regla de estado ESTABLISHED,RELATED."
else
    echo ">>> ATENCION: sin respuesta pese a las reglas de NAT."
fi

sep "c200 -> internet (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c200 ping -c3 -W3 8.8.8.8'

sep "Contadores de las reglas de NAT y reenvio"
ssh ubuntu@$MASTER 'sudo iptables -L FORWARD -n -v; echo; sudo iptables -t nat -L POSTROUTING -n -v'

sep "Aislamiento entre VLANs: c100 -> c200 (esperado: SIN respuesta)"
echo "Direccion de c200: $IP_C200"
if ssh ubuntu@$WORKER_CT "sudo docker exec c100 ping -c2 -W2 $IP_C200"; then
    echo ">>> ATENCION: hubo respuesta, las redes NO estan aisladas"
else
    echo ">>> CORRECTO: sin respuesta. La salida a internet no implica"
    echo "    conectividad entre VLANs: son autorizaciones independientes."
fi

echo
echo "############ FIN DE LA VERIFICACION ############"
