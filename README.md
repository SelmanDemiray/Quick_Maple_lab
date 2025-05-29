# Quick Maple Lab - Homelab Infrastructure

This project deploys a complete homelab infrastructure using Terraform for provisioning and Ansible for configuration management. The lab includes DHCP, DNS (Pi-hole), OpenSearch, and Suricata security monitoring.

## Table of Contents
- [Quick Start](#quick-start)
- [Terraform Commands](#terraform-commands)
- [Ansible Commands](#ansible-commands)
- [Container Management](#container-management)
- [Service Access](#service-access)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)

## Quick Start

### Initial Deployment
```bash
# 1. Deploy infrastructure with Terraform
cd terraform/
terraform init
terraform plan
terraform apply

# 2. Configure services with Ansible
cd ../ansible/
./run.sh
```

## Terraform Commands

### Infrastructure Management

#### Deploy All Infrastructure
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

#### Destroy All Infrastructure
```bash
cd terraform/
terraform destroy
```

#### Deploy Specific Containers
```bash
# Deploy only Pi-hole
terraform apply -target=proxmox_lxc.containers["pihole"]

# Deploy only DHCP server
terraform apply -target=proxmox_lxc.containers["dhcp"]

# Deploy only OpenSearch
terraform apply -target=proxmox_lxc.containers["opensearch"]

# Deploy only Suricata
terraform apply -target=proxmox_lxc.containers["suricata"]
```

#### Destroy Specific Containers
```bash
# Destroy only Pi-hole
terraform destroy -target=proxmox_lxc.containers["pihole"]

# Destroy only DHCP server
terraform destroy -target=proxmox_lxc.containers["dhcp"]

# Destroy only OpenSearch
terraform destroy -target=proxmox_lxc.containers["opensearch"]

# Destroy only Suricata
terraform destroy -target=proxmox_lxc.containers["suricata"]
```

#### Recreate Containers (Force Replacement)
```bash
# Recreate Pi-hole container
terraform apply -replace=proxmox_lxc.containers["pihole"]

# Recreate DHCP server
terraform apply -replace=proxmox_lxc.containers["dhcp"]

# Recreate OpenSearch container
terraform apply -replace=proxmox_lxc.containers["opensearch"]

# Recreate Suricata container
terraform apply -replace=proxmox_lxc.containers["suricata"]
```

#### View Infrastructure State
```bash
# Show current state
terraform show

# List all resources
terraform state list

# Show specific container state
terraform state show proxmox_lxc.containers["pihole"]
terraform state show proxmox_lxc.containers["dhcp"]
terraform state show proxmox_lxc.containers["opensearch"]
terraform state show proxmox_lxc.containers["suricata"]

# Show outputs
terraform output
terraform output container_ips
terraform output ssh_key_path
```

#### SSH Key Management
```bash
# Regenerate SSH keys (will recreate all containers)
terraform apply -replace=tls_private_key.ssh_key

# View SSH access information
terraform output ssh_public_key
cat ansible/SSH_ACCESS_README.md
```

## Ansible Commands

### Complete Deployment
```bash
cd ansible/

# Run complete infrastructure setup
./run.sh

# Or run playbooks individually
ansible-playbook network.yml
ansible-playbook security.yml
ansible-playbook playbook.yml
```

### Individual Service Configuration

#### Pi-hole DNS Server
```bash
# Configure Pi-hole only
ansible-playbook network.yml --limit pihole_group

# Restart Pi-hole service
ansible pihole_group -m service -a "name=pihole-FTL state=restarted"

# Update Pi-hole
ansible pihole_group -m shell -a "pihole -up"

# Check Pi-hole status
ansible pihole_group -m shell -a "pihole status"
```

#### DHCP Server
```bash
# Configure DHCP server only
ansible-playbook network.yml --limit dhcp

# Restart DHCP service
ansible dhcp -m service -a "name=isc-dhcp-server state=restarted"

# Check DHCP service status
ansible dhcp -m service -a "name=isc-dhcp-server state=status"

# View DHCP leases
ansible dhcp -m shell -a "cat /var/lib/dhcp/dhcpd.leases"
```

#### OpenSearch
```bash
# Configure OpenSearch only
ansible-playbook security.yml --limit opensearch

# Restart OpenSearch service
ansible opensearch -m service -a "name=opensearch state=restarted"

# Restart OpenSearch Dashboard
ansible opensearch -m service -a "name=opensearch-dashboards state=restarted"

# Check OpenSearch cluster status
ansible opensearch -m uri -a "url=http://localhost:9200/_cluster/health"
```

#### Suricata IDS
```bash
# Configure Suricata only
ansible-playbook security.yml --limit suricata

# Restart Suricata service
ansible suricata -m service -a "name=suricata state=restarted"

# Restart Filebeat
ansible suricata -m service -a "name=filebeat state=restarted"

# Check Suricata status
ansible suricata -m shell -a "suricata-update list-sources"

# Update Suricata rules
ansible suricata -m shell -a "suricata-update && systemctl restart suricata"
```

### System Management

#### Update All Systems
```bash
# Update package cache on all containers
ansible all -m apt -a "update_cache=yes"

# Upgrade all packages
ansible all -m apt -a "upgrade=dist"

# Reboot all containers
ansible all -m reboot

# Reboot specific container types
ansible dhcp -m reboot
ansible pihole_group -m reboot
ansible opensearch -m reboot
ansible suricata -m reboot
```

#### Check System Status
```bash
# Check uptime on all systems
ansible all -m shell -a "uptime"

# Check disk usage
ansible all -m shell -a "df -h"

# Check memory usage
ansible all -m shell -a "free -h"

# Check running services
ansible all -m shell -a "systemctl list-units --state=running"

# Check specific service status
ansible all -m service -a "name=ssh state=status"
```

#### Network Diagnostics
```bash
# Test connectivity between containers
ansible all -m ping

# Check network interfaces
ansible all -m shell -a "ip addr show"

# Test DNS resolution
ansible all -m shell -a "nslookup google.com"

# Test internet connectivity
ansible all -m shell -a "curl -s http://httpbin.org/ip"
```

### Log Management
```bash
# View system logs
ansible all -m shell -a "journalctl --since '1 hour ago' --no-pager"

# View specific service logs
ansible pihole_group -m shell -a "tail -f /var/log/pihole.log"
ansible dhcp -m shell -a "journalctl -u isc-dhcp-server --no-pager"
ansible opensearch -m shell -a "journalctl -u opensearch --no-pager"
ansible suricata -m shell -a "tail -f /var/log/suricata/eve.json"
```

## Container Management

### Direct SSH Access
```bash
# SSH into specific containers
ssh -i ansible/id_rsa root@192.168.0.10   # DHCP server
ssh -i ansible/id_rsa root@192.168.0.102  # Pi-hole
ssh -i ansible/id_rsa root@192.168.0.99   # OpenSearch
ssh -i ansible/id_rsa root@192.168.0.97   # Suricata

# Or use hostnames (if DNS is configured)
ssh -i ansible/id_rsa root@isc-dhcp-server
ssh -i ansible/id_rsa root@pihole
ssh -i ansible/id_rsa root@opensearch-dashboard
ssh -i ansible/id_rsa root@suricata-filebeat
```

### Container Lifecycle
```bash
# Start containers (via Proxmox)
ansible all -m shell -a "systemctl start container"

# Stop containers gracefully
ansible all -m shell -a "shutdown -h now"

# Force restart specific container from Proxmox host
# (Run on Proxmox host)
pct stop 102 && pct start 102    # Pi-hole
pct stop 1010 && pct start 1010  # DHCP server
pct stop 1099 && pct start 1099  # OpenSearch
pct stop 197 && pct start 197    # Suricata
```

## Service Access

### Web Interfaces
- **Pi-hole Admin**: http://192.168.0.102/admin
- **OpenSearch Dashboard**: http://192.168.0.99:5601

### Service Ports
- **Pi-hole DNS**: 192.168.0.102:53
- **DHCP Server**: 192.168.0.10:67
- **OpenSearch**: 192.168.0.99:9200
- **OpenSearch Dashboard**: 192.168.0.99:5601
- **Suricata**: Monitoring on 192.168.0.97

### Passwords and Credentials
```bash
# View generated passwords
cat ansible/ssh_passwords.json

# View SSH access information
cat ansible/SSH_ACCESS_README.md
```

## Troubleshooting

### Common Issues

#### Terraform Issues
```bash
# Fix Terraform state lock
terraform force-unlock <LOCK_ID>

# Refresh state
terraform refresh

# Import existing resources
terraform import proxmox_lxc.containers["pihole"] pve/lxc/102

# Validate configuration
terraform validate

# Check for drift
terraform plan -detailed-exitcode
```

#### Ansible Issues
```bash
# Test Ansible connectivity
ansible all -m ping

# Run with verbose output
ansible-playbook playbook.yml -vvv

# Check syntax
ansible-playbook playbook.yml --syntax-check

# Dry run
ansible-playbook playbook.yml --check

# Force gather facts
ansible all -m setup

# Clear fact cache
rm -rf ansible/fact_cache/*
```

#### SSH Connection Issues
```bash
# Remove old SSH keys
ssh-keygen -R 192.168.0.10
ssh-keygen -R 192.168.0.102
ssh-keygen -R 192.168.0.99
ssh-keygen -R 192.168.0.97

# Test SSH manually
ssh -i ansible/id_rsa -o StrictHostKeyChecking=no root@192.168.0.102

# Regenerate SSH keys
cd terraform/
terraform apply -replace=tls_private_key.ssh_key
```

#### Service Issues
```bash
# Check if services are listening
ansible all -m shell -a "netstat -tulpn"

# Check firewall status
ansible all -m shell -a "iptables -L"

# Restart networking
ansible all -m service -a "name=networking state=restarted"

# Check DNS resolution
ansible all -m shell -a "nslookup 8.8.8.8"
```

### Emergency Recovery
```bash
# Complete rebuild
cd terraform/
terraform destroy -auto-approve
terraform apply -auto-approve
cd ../ansible/
./run.sh

# Backup current state
terraform show > backup-$(date +%Y%m%d).tfstate
cp -r ansible/ backup-ansible-$(date +%Y%m%d)/
```

## Project Structure

```
Quick_Maple_lab/
├── README.md                    # This file
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                 # Main Terraform configuration
│   ├── variables.tf            # Variable definitions
│   ├── outputs.tf              # Output definitions
│   ├── providers.tf            # Provider configuration
│   ├── terraform.tfvars        # Variable values
│   └── templates/              # Terraform templates
├── ansible/                    # Configuration Management
│   ├── playbook.yml            # Main playbook
│   ├── network.yml             # Network services playbook
│   ├── security.yml            # Security monitoring playbook
│   ├── ansible.cfg             # Ansible configuration
│   ├── inventory/              # Static inventory
│   ├── roles/                  # Ansible roles
│   ├── id_rsa                  # SSH private key (generated)
│   ├── ssh_passwords.json      # Container passwords (generated)
│   ├── ssh_access.json         # SSH access info (generated)
│   └── SSH_ACCESS_README.md    # SSH documentation (generated)
└── .gitignore                  # Git ignore rules
```

## Security Notes

- SSH keys are automatically generated by Terraform
- Container passwords are randomly generated and stored securely
- All SSH connections use key-based authentication
- Default firewall rules allow necessary services only
- Regular security updates should be applied using the commands above

## Contributing

When making changes:
1. Test with `terraform plan` before applying
2. Use `ansible-playbook --check` for dry runs
3. Document any new commands in this README
4. Backup state files before major changes

For support, check the troubleshooting section or review the generated documentation in `ansible/SSH_ACCESS_README.md`.
