#!/bin/bash
chmod +x inventory_from_terraform.py

# Remove old SSH host keys for network infrastructure IPs
for ip in 192.168.0.10 192.168.0.102; do
  ssh-keygen -R "$ip" 2>/dev/null || true
done

echo "Deploying network infrastructure (Pi-hole and DHCP)..."
ansible-playbook network.yml
