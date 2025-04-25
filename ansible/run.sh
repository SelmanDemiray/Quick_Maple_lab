#!/bin/bash
chmod +x inventory_from_terraform.py

# Remove old SSH host keys for all container IPs before running Ansible
for ip in 192.168.0.10 192.168.0.97 192.168.0.99 192.168.0.102; do
  ssh-keygen -R "$ip" 2>/dev/null || true
done

ansible-playbook playbook.yml
