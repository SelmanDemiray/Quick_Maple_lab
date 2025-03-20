# This file contains the main resources and data sources for the homelab setup.

locals {
  # Common path references with proper path handling
  ansible_path = abspath("${path.module}/../ansible")
  ssh_key_path = "${local.ansible_path}/id_rsa"
  
  # Container password map for consistent reference
  container_passwords = {
    for name, container in var.containers :
    name => container.password != null ? container.password : random_password.container_passwords[name].result
  }
  
  # SSH configurations
  ssh_opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  
  # Container groups for easier management
  container_types = {
    opensearch = [for name, c in var.containers : name if length(regexall("opensearch", name)) > 0]
    dhcp       = [for name, c in var.containers : name if length(regexall("dhcp", name)) > 0]
    pihole     = [for name, c in var.containers : name if length(regexall("pihole", name)) > 0]
    suricata   = [for name, c in var.containers : name if length(regexall("suricata", name)) > 0]
  }
}

# Generate a unique SSH key pair for this deployment
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key for Ansible with proper lifecycle management
resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = local.ssh_key_path
  file_permission = "0600"
  
  lifecycle {
    replace_triggered_by = [
      # Regenerate if SSH key changes
      tls_private_key.ssh_key
    ]
  }
}

# Generate random passwords for containers that don't specify one
resource "random_password" "container_passwords" {
  for_each = {
    for name, container in var.containers :
    name => container if container.password == null
  }
  
  length      = 20
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
  # Use only SSH-safe special characters
  override_special = "!@#%^*()-_=+[]{}:;,."
}

# Create LXC containers based on the variable definitions
resource "proxmox_lxc" "containers" {
  for_each = var.containers
  
  # System configuration
  target_node  = each.value.host
  hostname     = each.value.hostname
  vmid         = each.value.id
  ostemplate   = each.value.ostemplate
  unprivileged = each.value.unprivileged
  password     = local.container_passwords[each.key]
  
  # Start container after creation
  start        = each.value.start_after_create
  onboot       = each.value.onboot == 1 ? true : false
  
  # Hardware allocation
  cores        = each.value.cores
  memory       = each.value.memory
  swap         = each.value.swap
  
  # Container features
  features {
    nesting = lookup(each.value.features, "nesting", 0) == 1 ? true : false
  }
  
  # Networks
  network {
    name   = "eth0"
    bridge = "vmbr0"
    ip     = "${each.value.ip}/${var.subnet_mask}"
    gw     = var.gateway_ip
  }
  
  # Storage
  rootfs {
    storage = each.value.storage_type
    size    = "${each.value.storage_size}G"
  }
  
  # Set tags if provided
  tags = each.value.tags != null ? each.value.tags : ""

  # Add SSH key to authorized_keys
  ssh_public_keys = tls_private_key.ssh_key.public_key_openssh
  
  # Improved connection handling with proper timeouts
  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = tls_private_key.ssh_key.private_key_pem
    host        = each.value.ip
    timeout     = "5m"
  }
  
  # Better container initialization with safeguards
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for container ${each.value.hostname} (${each.value.ip}) to initialize..."
      sleep 10
      
      # Force SSH known hosts update with error handling
      ssh-keygen -R ${each.value.ip} 2>/dev/null || true
      
      # Connection test with proper retry and error handling
      count=0
      max_retries=20
      until ssh ${local.ssh_opts} -i ${local.ssh_key_path} ${var.ssh_user}@${each.value.ip} 'echo "SSH connection successful"'; do
        if [ $count -eq $max_retries ]; then
          echo "ERROR: SSH connection to ${each.value.hostname} (${each.value.ip}) failed after $max_retries attempts"
          exit 1
        fi
        count=$((count+1))
        echo "Waiting for SSH connection to ${each.value.hostname} (${each.value.ip})... ($count/$max_retries)"
        sleep 5
      done
      echo "Container ${each.value.hostname} is ready and accessible via SSH"
    EOT
  }
  
  # Prevent unnecessary replacement of containers
  lifecycle {
    ignore_changes = [
      # Ignore changes in container configuration that don't require recreation
      ssh_public_keys,
      tags
    ]
  }
}

# Generate all Ansible configuration files with proper dependencies
resource "local_file" "ansible_configs" {
  for_each = {
    "inventory"     = {
      content = templatefile("${path.module}/templates/inventory.tftpl", {
        ssh_user      = var.ssh_user,
        ssh_key_path  = local.ssh_key_path,
        containers    = proxmox_lxc.containers
      })
      path = "${local.ansible_path}/inventory/hosts.yml"
    }
    "group_vars"    = {
      content = templatefile("${path.module}/templates/group_vars.tftpl", {
        opensearch_password = var.opensearch_password,
        containers = proxmox_lxc.containers,
        pihole_webpassword = var.pihole_webpassword,
        dhcp_server_ranges = var.dhcp_server_ranges,
        gateway_ip = var.gateway_ip
      })
      path = "${local.ansible_path}/group_vars/all.yml"
    }
    "ansible_cfg"   = {
      content = <<-EOT
[defaults]
host_key_checking = False
private_key_file = ${local.ssh_key_path}
timeout = 30
inventory = inventory/hosts.yml
retry_files_enabled = False
EOT
      path = "${local.ansible_path}/ansible.cfg"
    }
    "ssh_tasks"     = {
      content = <<-EOT
---
# tasks/ssh_setup.yml - Ensures SSH works properly

- name: Ensure SSH directory exists
  file:
    path: /root/.ssh
    state: directory
    mode: '0700'
  become: yes

- name: Configure SSH to allow password authentication for root
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin'
    line: 'PermitRootLogin yes'
    state: present
  notify: Restart sshd

- name: Configure SSH to allow password authentication
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PasswordAuthentication'
    line: 'PasswordAuthentication yes'
    state: present
  notify: Restart sshd

- name: Configure SSH to allow public key authentication
  lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PubkeyAuthentication'
    line: 'PubkeyAuthentication yes'
    state: present
  notify: Restart sshd

- name: Restart sshd immediately if needed
  meta: flush_handlers

- name: Wait for SSH to be available
  wait_for:
    port: 22
    host: "{{ ansible_host }}"
    timeout: 60
    state: started
    delay: 5
EOT
      path = "${local.ansible_path}/tasks/ssh_setup.yml"
    }
    "handlers"      = {
      content = <<-EOT
---
# handlers/main.yml
- name: Restart sshd
  service:
    name: sshd
    state: restarted
EOT
      path = "${local.ansible_path}/handlers/main.yml"
    }
    "playbook"      = {
      content = <<-EOT
---
# Main playbook for infrastructure configuration
- name: SSH Setup
  hosts: all
  become: true
  tasks:
    - name: Include SSH setup tasks
      include_tasks: tasks/ssh_setup.yml
  
  # Define handlers directly in the playbook
  handlers:
    - name: Restart sshd
      service:
        name: sshd
        state: restarted

# Service-specific configurations
- name: Configure OpenSearch servers
  hosts: opensearch_nodes
  become: true
  tasks:
    - name: Ensure OpenSearch prerequisites are met
      debug:
        msg: "OpenSearch node configuration would go here"
      tags: opensearch

- name: Configure Pi-hole servers
  hosts: pihole_servers
  become: true
  tasks:
    - name: Ensure Pi-hole prerequisites are met
      debug:
        msg: "Pi-hole configuration would go here"
      tags: pihole

- name: Configure DHCP servers
  hosts: dhcp_servers
  become: true
  tasks:
    - name: Ensure DHCP servers are properly configured
      debug:
        msg: "DHCP configuration would go here"
      tags: dhcp

- name: Configure Suricata hosts
  hosts: suricata_hosts
  become: true
  tasks:
    - name: Ensure Suricata is properly configured
      debug:
        msg: "Suricata configuration would go here"
      tags: suricata
EOT
      path = "${local.ansible_path}/playbook.yml"
    }
  }

  content         = each.value.content
  filename        = each.value.path
  file_permission = "0644"
  
  depends_on = [
    proxmox_lxc.containers
  ]
}

# Generate a comprehensive SSH access file with container credentials
resource "local_file" "ssh_passwords" {
  content = templatefile("${path.module}/templates/ssh_passwords.tftpl", {
    containers = {
      for name, container in var.containers : name => {
        ip       = container.ip
        hostname = container.hostname
        username = var.ssh_user
        password = local.container_passwords[name]
      }
    }
  })
  filename = "${local.ansible_path}/ssh_passwords.json" # Use absolute path with local.ansible_path
  file_permission = "0600"
  
  depends_on = [proxmox_lxc.containers]
}

# Create a structured SSH access information file for Ansible
resource "local_file" "ansible_ssh_info" {
  content = jsonencode({
    ssh_key_path = local.ssh_key_path
    ssh_key_content = tls_private_key.ssh_key.private_key_pem
    ssh_public_key = tls_private_key.ssh_key.public_key_openssh
    containers = {
      for name, container in proxmox_lxc.containers : name => {
        id = container.id
        ip = split("/", container.network[0].ip)[0]
        hostname = container.hostname
        user = var.ssh_user
        password = local.container_passwords[name]
        groups = [
          for group, names in local.container_types :
          group if contains(names, name)
        ]
      }
    }
  })
  filename = "${local.ansible_path}/ssh_access.json"
  file_permission = "0600"
  
  depends_on = [proxmox_lxc.containers, local_file.private_key]
}

# Add this after ssh_passwords file creation
resource "local_file" "ssh_readme" {
  content = <<-EOT
# SSH Access Information
This file provides information about SSH access to the deployed containers.

## SSH Private Key
Location: ${local.ssh_key_path}

## Container Access
${join("\n", [for name, container in proxmox_lxc.containers :
"- ${container.hostname} (${name}): ssh -i ${local.ssh_key_path} ${var.ssh_user}@${split("/", container.network[0].ip)[0]}"])}

## Ansible Integration
Ansible can consume the SSH access information from:
- SSH Keys: ${local.ssh_key_path}
- Structured data: ${local_file.ansible_ssh_info.filename}
- Passwords: ${local_file.ssh_passwords.filename}

## Service Management
${contains(keys(var.containers), "pihole") ? "- Pi-hole web interface: http://${split("/", proxmox_lxc.containers["pihole"].network[0].ip)[0]}/admin" : ""}
${contains(keys(var.containers), "opensearch") ? "- OpenSearch dashboard: http://${split("/", proxmox_lxc.containers["opensearch"].network[0].ip)[0]}:5601" : ""}

This file is automatically regenerated when containers are recreated.
EOT
  filename = "${local.ansible_path}/SSH_ACCESS_README.md"
  file_permission = "0644"
  
  depends_on = [local_file.ansible_ssh_info, local_file.ssh_passwords, local_file.private_key]
}

# Run Ansible playbook with better error handling
resource "null_resource" "run_ansible" {
  # Only run when relevant resources change
  triggers = {
    containers = join(",", [for c in proxmox_lxc.containers : c.id])
    playbook_content = md5(local_file.ansible_configs["playbook"].content)
    inventory_content = md5(local_file.ansible_configs["inventory"].content)
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Checking for Ansible availability..."
      if command -v ansible-playbook >/dev/null 2>&1; then
        echo "Running Ansible playbook with error handling..."
        cd ${local.ansible_path} && \
        ansible-playbook playbook.yml --syntax-check && \
        ansible-playbook playbook.yml || {
          # Allow the Terraform run to continue even if Ansible has warnings
          if [ $? -eq 2 ]; then
            echo "ERROR: Ansible playbook failed with fatal errors!"
            exit 1
          else
            echo "WARNING: Ansible playbook completed with warnings."
          fi
        }
        echo "Ansible playbook execution finished."
      else
        echo "WARNING: ansible-playbook command not found. Skipping Ansible run."
        echo "To configure containers, install Ansible and run:"
        echo "cd ${local.ansible_path} && ansible-playbook playbook.yml"
      fi
    EOT
  }
  
  depends_on = [
    proxmox_lxc.containers,
    local_file.ansible_configs
  ]
}

# Output completion message with all relevant information
resource "null_resource" "completion_message" {
  depends_on = [null_resource.run_ansible]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "=================================================="
      echo "Infrastructure Deployment Complete"
      echo "=================================================="
      echo ""
      echo "Deployed containers:"
      echo ""
      ${join("", [for name, container in proxmox_lxc.containers : <<-CONTAINER
      echo "${name}: ${split("/", container.network[0].ip)[0]} (${container.hostname})"
      CONTAINER
      ])}
      
      echo ""
      echo "Access information:"
      echo "- SSH private key: ${local.ssh_key_path}"
      echo "- Credentials file: ${local_file.ssh_passwords.filename}"
      echo "- Access documentation: ${local_file.ssh_readme.filename}"
      echo ""
      
      ${contains(keys(var.containers), "pihole") ? "echo \"- Pi-hole web interface: http://${split("/", proxmox_lxc.containers["pihole"].network[0].ip)[0]}/admin\"" : ""}
      ${contains(keys(var.containers), "opensearch") ? "echo \"- OpenSearch dashboard: http://${split("/", proxmox_lxc.containers["opensearch"].network[0].ip)[0]}:5601\"" : ""}
      echo ""
    EOT
  }
}