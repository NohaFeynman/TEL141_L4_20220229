#!/bin/bash
#===============================================================================
# verificar_actividad_3.sh
# Verificacion de la topologia desplegada en la Actividad 3.
#===============================================================================
set -uo pipefail

MASTER="10.0.10.3"
WORKER_CT="10.0.10.1"
WORKER_VM="10.0.10.2"

sep() { echo; echo "----- $* -----"; }

echo "############ VERIFICACION - ACTIVIDAD 3 ############"
echo "Fecha: $(date)"

sep "Master (server3): topologia OVS"
ssh ubuntu@$MASTER 'hostname; sudo ovs-vsctl show'

sep "Master: servicio DHCP activo (esperado: 2 namespaces, 2 procesos)"
ssh ubuntu@$MASTER 'sudo ip netns list; echo "Procesos DHCP activos: $(pgrep -cx dnsmasq)"'

sep "Master: interfaces DHCP dentro de cada namespace"
ssh ubuntu@$MASTER 'sudo ip netns exec ns-dhcp-vlan100 ip -br addr; sudo ip netns exec ns-dhcp-vlan200 ip -br addr'

sep "Master: ausencia de NAT y de reglas de reenvio (esperado: solo la politica)"
ssh ubuntu@$MASTER 'sudo iptables -S FORWARD; echo; sudo iptables -t nat -S POSTROUTING'

sep "Worker server2: topologia OVS y maquinas virtuales"
ssh ubuntu@$WORKER_VM 'hostname; sudo ovs-vsctl show; pgrep -af qemu-system-x86_64 | cut -c1-100'

sep "Worker server1: topologia OVS y contenedores"
ssh ubuntu@$WORKER_CT 'hostname; sudo ovs-vsctl show; sudo docker ps --format "{{.Names}} {{.Status}}"'

sep "Contenedor c100: direccionamiento obtenido por DHCP"
ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ip addr show eth_c100; sudo docker exec c100 ip route'

sep "Contenedor c200: direccionamiento obtenido por DHCP"
ssh ubuntu@$WORKER_CT 'sudo docker exec c200 ip addr show eth_c200; sudo docker exec c200 ip route'

sep "Master: leases entregados por los servidores DHCP"
ssh ubuntu@$MASTER 'sudo cat /var/lib/misc/dnsmasq-vlan100.leases /var/lib/misc/dnsmasq-vlan200.leases 2>/dev/null || echo "sin leases registrados"'

sep "c100 -> gateway VLAN 100 (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ping -c2 -W2 192.168.0.1'

sep "c200 -> gateway VLAN 200 (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c200 ping -c2 -W2 192.168.2.1'

sep "c100 -> internet (esperado: SIN respuesta)"
if ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ping -c2 -W3 8.8.8.8'; then
    echo ">>> ATENCION: hubo respuesta, existe salida a internet"
else
    echo ">>> CORRECTO: sin respuesta. Sin MASQUERADE el trafico saldria con"
    echo "    direccion privada y sin retorno; ademas la politica FORWARD DROP"
    echo "    descarta el reenvio antes de llegar al NAT."
fi

sep "c200 -> internet (esperado: SIN respuesta)"
if ssh ubuntu@$WORKER_CT 'sudo docker exec c200 ping -c2 -W3 8.8.8.8'; then
    echo ">>> ATENCION: hubo respuesta, existe salida a internet"
else
    echo ">>> CORRECTO: sin respuesta, la VLAN 200 no tiene salida a internet"
fi

sep "Aislamiento entre VLANs: c100 -> c200 (esperado: SIN respuesta)"
CT200_IP=$(ssh ubuntu@$WORKER_CT "sudo docker exec c200 ip -4 addr show eth_c200 | awk '/inet /{print \$2}' | cut -d/ -f1")
echo "Direccion de c200 obtenida por DHCP: $CT200_IP"
if ssh ubuntu@$WORKER_CT "sudo docker exec c100 ping -c2 -W2 $CT200_IP"; then
    echo ">>> ATENCION: hubo respuesta, las redes NO estan aisladas"
else
    echo ">>> CORRECTO: sin respuesta, aislamiento de capa 2 entre VLANs"
fi

echo
echo "############ FIN DE LA VERIFICACION ############"
