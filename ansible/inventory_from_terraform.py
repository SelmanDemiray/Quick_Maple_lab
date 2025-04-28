#!/usr/bin/env python3

import json
import os
import sys
from pathlib import Path

def load_ssh_access():
    """Load the SSH access information from the Terraform-generated file."""
    script_dir = Path(__file__).parent.absolute()
    ssh_access_file = script_dir / "ssh_access.json"
    
    try:
        with open(ssh_access_file, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        sys.stderr.write(f"Error: SSH access file {ssh_access_file} not found.\n")
        sys.exit(1)
    except json.JSONDecodeError:
        sys.stderr.write(f"Error: SSH access file {ssh_access_file} contains invalid JSON.\n")
        sys.exit(1)

def build_inventory():
    """Build Ansible inventory from Terraform SSH access data."""
    ssh_data = load_ssh_access()
    
    # Initialize inventory structure
    inventory = {
        'all': {'hosts': []},
        '_meta': {'hostvars': {}},
    }
    
    # Process containers and build inventory groups
    for name, container in ssh_data['containers'].items():
        # Add host to its groups
        for group in container.get('groups', []):
            inventory.setdefault(group, {'hosts': []})['hosts'].append(container['hostname'])
        
        # always add to all
        inventory['all']['hosts'].append(container['hostname'])
        
        # hostvars
        inventory['_meta']['hostvars'][container['hostname']] = {
            'ansible_host': container['ip'],
            'ansible_user': container['user'],
            'terraform_id': container['id'],
            'container_name': name
        }
    
    return inventory

if __name__ == '__main__':
    # Output inventory as JSON
    print(json.dumps(build_inventory(), indent=2))
