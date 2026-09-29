# TEL141_L4_20220229

Estudiante: Nilton Fernando Condori Quispe

Scripts de automatización para el Laboratorio 4 del curso TEL141 - Ingeniería de Redes Cloud.

## Uso

Los scripts se ejecutan de forma remota desde el nodo orquestador:

    ssh ubuntu@<ip_nodo> 'sudo bash -s' < ./<script>.sh <parametros>

## Scripts

| Script | Parámetros |
|---|---|
| `init_master.sh` | `<interfaz> [interfaz...]` |
| `init_worker.sh` | `<interfaz> [interfaz...]` |
| `create_network_vlan.sh` | `<vlan_id> <cidr> <enabled\|disabled> [inicio,fin]` |
| `internet_to_network.sh` | `<vlan_id> <cidr>` |
| `no_internet_to_network.sh` | `<vlan_id> <cidr>` |
| `routing_networks.sh` | `<vlan_id_1> <vlan_id_2>` |
| `no_routing_networks.sh` | `<vlan_id_1> <vlan_id_2>` |
| `create_vm.sh` | `<nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>` |
| `delete_vm.sh` | `<nombre_vm> <nombre_ovs> <vlan_id> <puerto_vnc>` |
## Reporte Final

El directorio `rf/` contiene los scripts de despliegue de cada actividad y sus
registros de ejecucion en `rf/evidencias/`.

| Actividad | DHCP | Internet | Ruteo entre VLANs |
|---|---|---|---|
| 1 | si | si | no |
| 2 | no | si | no |
| 3 | si | no | no |
| 4 | si | no | si |

Cada actividad cuenta con un script de despliegue (`actividad_N.sh`), uno de
verificacion (`verificar_actividad_N.sh`) y uno de reversion
(`limpiar_actividad_N.sh`). Todos se ejecutan desde el nodo orquestador
(server4) y operan sobre los nodos del slice mediante SSH.
