#!/bin/bash
#===============================================================================
# verificar_actividad_2.sh
# Verificacion de la topologia desplegada en la Actividad 2.
#===============================================================================
set -uo pipefail

MASTER="10.0.10.3"
WORKER_CT="10.0.10.1"
WORKER_VM="10.0.10.2"

sep() { echo; echo "----- $* -----"; }

echo "############ VERIFICACION - ACTIVIDAD 2 ############"
echo "Fecha: $(date)"

sep "Master (server3): topologia OVS"
ssh ubuntu@$MASTER 'hostname; sudo ovs-vsctl show'

sep "Master: ausencia de servicio DHCP (esperado: sin namespaces, 0 procesos)"
ssh ubuntu@$MASTER 'sudo ip netns list; echo "Procesos DHCP activos: $(pgrep -cx dnsmasq)"'

sep "Master: direcciones de los gateways"
ssh ubuntu@$MASTER 'ip -br addr show gw_vlan100; ip -br addr show gw_vlan200'

sep "Master: reglas de filtrado y NAT"
ssh ubuntu@$MASTER 'sudo iptables -S FORWARD; echo; sudo iptables -t nat -S POSTROUTING'

sep "Worker server2: topologia OVS y maquinas virtuales"
ssh ubuntu@$WORKER_VM 'hostname; sudo ovs-vsctl show; pgrep -af qemu-system | cut -c1-100'

sep "Worker server1: topologia OVS y contenedores"
ssh ubuntu@$WORKER_CT 'hostname; sudo ovs-vsctl show; sudo docker ps --format "{{.Names}} {{.Status}}"'

sep "Contenedor c100 (VLAN 100): direccionamiento estatico"
ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ip addr show eth_c100; sudo docker exec c100 ip route'

sep "Contenedor c200 (VLAN 200): direccionamiento estatico"
ssh ubuntu@$WORKER_CT 'sudo docker exec c200 ip addr show eth_c200; sudo docker exec c200 ip route'

sep "c100 -> gateway VLAN 100 (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ping -c2 -W2 192.168.0.1'

sep "c100 -> internet (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ping -c2 -W2 8.8.8.8'

sep "c200 -> gateway VLAN 200 (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c200 ping -c2 -W2 192.168.2.1'

sep "c200 -> internet (esperado: exito)"
ssh ubuntu@$WORKER_CT 'sudo docker exec c200 ping -c2 -W2 8.8.8.8'

sep "Aislamiento entre VLANs: c100 -> c200 (esperado: SIN respuesta)"
if ssh ubuntu@$WORKER_CT 'sudo docker exec c100 ping -c2 -W2 192.168.2.11'; then
    echo ">>> ATENCION: hubo respuesta, las redes NO estan aisladas"
else
    echo ">>> CORRECTO: sin respuesta. La trama de c100 sale etiquetada con VLAN 100"
    echo "    y el bridge no la entrega a puertos de VLAN 200: aislamiento de capa 2."
fi

sep "Nota sobre la direccion 192.168.2.1"
echo "El gateway de la VLAN 200 responde a c100 porque gw_vlan100 y gw_vlan200"
echo "pertenecen al mismo host (server3): el trafico dirigido a una direccion local"
echo "atraviesa la cadena INPUT, no FORWARD. No constituye comunicacion entre VLANs."

echo
echo "############ FIN DE LA VERIFICACION ############"
