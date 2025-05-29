#!/bin/bash
chmod +x inventory_from_terraform.py

# Remove old SSH host keys for security monitoring IPs
for ip in 192.168.0.97 192.168.0.99; do
  ssh-keygen -R "$ip" 2>/dev/null || true
done

echo "Deploying security monitoring infrastructure (Suricata and OpenSearch)..."
ansible-playbook security.yml
