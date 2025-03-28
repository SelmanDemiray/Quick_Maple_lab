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
    },
    dhcp_ranges = var.dhcp_server_ranges  # Add this line to include DHCP ranges
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

# Output completion message with all relevant information
resource "null_resource" "completion_message" {
  depends_on = [local_file.ssh_readme, local_file.ansible_ssh_info, local_file.private_key]
  
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
      echo "SSH Access Information:"
      echo "- SSH private key: ${local.ssh_key_path}"
      echo "- SSH credentials file: ${local_file.ssh_passwords.filename}"
      echo "- SSH access documentation: ${local_file.ssh_readme.filename}"
      echo "- SSH access JSON: ${local_file.ansible_ssh_info.filename}"
      echo ""
      
      ${contains(keys(var.containers), "pihole") ? "echo \"- Pi-hole web interface: http://${split("/", proxmox_lxc.containers["pihole"].network[0].ip)[0]}/admin\"" : ""}
      ${contains(keys(var.containers), "opensearch") ? "echo \"- OpenSearch dashboard: http://${split("/", proxmox_lxc.containers["opensearch"].network[0].ip)[0]}:5601\"" : ""}
      echo ""
      echo "These containers are ready for configuration with Ansible."
      echo "All the SSH information needed for Ansible is automatically generated."
      echo ""
    EOT
  }
}