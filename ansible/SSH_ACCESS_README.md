# SSH Access Information
This file provides information about SSH access to the deployed containers.

## SSH Private Key
Location: /home/ansible/new/Quick_Maple_lab/ansible/id_rsa

## Container Access
- isc-dhcp-server (dhcp): ssh -i /home/ansible/new/Quick_Maple_lab/ansible/id_rsa root@192.168.0.10
- opensearch-dashboard (opensearch): ssh -i /home/ansible/new/Quick_Maple_lab/ansible/id_rsa root@192.168.0.99
- pihole (pihole): ssh -i /home/ansible/new/Quick_Maple_lab/ansible/id_rsa root@192.168.0.102
- suricata-filebeat (suricata): ssh -i /home/ansible/new/Quick_Maple_lab/ansible/id_rsa root@192.168.0.97

## Ansible Integration
Ansible can consume the SSH access information from:
- SSH Keys: /home/ansible/new/Quick_Maple_lab/ansible/id_rsa
- Structured data: /home/ansible/new/Quick_Maple_lab/ansible/ssh_access.json
- Passwords: /home/ansible/new/Quick_Maple_lab/ansible/ssh_passwords.json

## Service Management
- Pi-hole web interface: http://192.168.0.102/admin
- OpenSearch dashboard: http://192.168.0.99:5601 (Authentication required: admin/C87V48V593245ks99f)
- OpenSearch API (secure): https://192.168.0.99:9200

This file is automatically regenerated when containers are recreated.
