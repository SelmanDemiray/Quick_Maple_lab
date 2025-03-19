# This file contains the main resources and data sources for the homelab setup.

# Remove duplicate terraform and provider blocks as they're in providers.tf

# Generate a unique SSH key pair for this deployment
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key for Ansible
resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/../ansible/id_rsa"
  file_permission = "0600"
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
  
  target_node  = each.value.host
  hostname     = each.value.hostname
  vmid         = each.value.id
  ostemplate   = each.value.ostemplate
  unprivileged = each.value.unprivileged
  password     = each.value.password != null ? each.value.password : random_password.container_passwords[each.key].result
  
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
  
  # Add a delay to ensure the container is fully initialized
  provisioner "local-exec" {
    command = "echo 'Waiting for container ${each.value.hostname} (${each.value.ip}) to initialize...' && sleep 10"
  }

  # Force SSH known hosts update
  provisioner "local-exec" {
    command = "ssh-keygen -R ${each.value.ip} || true"
  }
  
  # Test SSH connection with retry logic
  provisioner "local-exec" {
    command = <<-EOT
      count=0
      max_retries=20
      until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${local_file.private_key.filename} ${var.ssh_user}@${each.value.ip} 'echo SSH connection successful'; do
        if [ $count -eq $max_retries ]; then
          echo "SSH connection failed after $max_retries attempts"
          exit 1
        fi
        count=$((count+1))
        echo "Waiting for SSH connection to ${each.value.hostname} (${each.value.ip})... ($count/$max_retries)"
        sleep 5
      done
    EOT
  }
}

// Ensure Ansible directory structure exists
resource "null_resource" "ansible_directory_structure" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/../ansible/{inventory,group_vars,tasks,handlers}
      mkdir -p ${path.module}/../ansible/roles/{opensearch,pihole,dhcp,suricata}/{tasks,templates,handlers,files}
      chmod 0600 ${path.module}/../ansible/id_rsa
    EOT
  }
  
  depends_on = [local_file.private_key]
}

# Generate Ansible inventory file from template
resource "local_file" "ansible_inventory" {
  content         = templatefile("${path.module}/templates/inventory.tftpl", {
    ssh_user      = var.ssh_user,
    ssh_key_path  = local_file.private_key.filename,
    containers    = proxmox_lxc.containers
  })
  filename        = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission = "0644"
  sensitive_content = null  # Explicitly set to null to avoid sensitivity conflicts
  
  depends_on = [proxmox_lxc.containers]
  
  # Ensure directory exists before creating file
  provisioner "local-exec" {
    command = "mkdir -p ${dirname("${path.module}/../ansible/inventory/")}"
  }
}

# Generate Ansible group_vars from template
resource "local_file" "ansible_group_vars" {
  content         = templatefile("${path.module}/templates/group_vars.tftpl", {
    opensearch_password = var.opensearch_password,
    containers = proxmox_lxc.containers,
    pihole_webpassword = var.pihole_webpassword,
    dhcp_server_ranges = var.dhcp_server_ranges,
    gateway_ip = var.gateway_ip
  })
  filename        = "${path.module}/../ansible/group_vars/all.yml"
  file_permission = "0644"
  sensitive_content = null  # Explicitly set to null to avoid sensitivity conflicts
  
  depends_on = [proxmox_lxc.containers]
  
  # Ensure directory exists before creating file
  provisioner "local-exec" {
    command = "mkdir -p ${dirname("${path.module}/../ansible/group_vars/")}"
  }
}

# Generate ansible.cfg with correct private key path
resource "local_file" "ansible_config" {
  content = <<-EOT
[defaults]
host_key_checking = False
private_key_file = ${local_file.private_key.filename}
timeout = 30
EOT
  filename = "${path.module}/../ansible/ansible.cfg"
  
  depends_on = [local_file.private_key]
}

# Create SSH setup tasks file for Ansible
resource "local_file" "ansible_ssh_tasks" {
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
  filename = "${path.module}/../ansible/tasks/ssh_setup.yml"
  
  depends_on = [proxmox_lxc.containers]
}

# Create handler for SSH restart
resource "local_file" "ansible_handlers" {
  content = <<-EOT
---
# handlers/main.yml
- name: Restart sshd
  service:
    name: sshd
    state: restarted
EOT
  filename = "${path.module}/../ansible/handlers/main.yml"
  
  depends_on = [proxmox_lxc.containers]
}

# Generate a passwords file with all container credentials
resource "local_file" "ssh_passwords" {
  content = templatefile("${path.module}/templates/ssh_passwords.tftpl", {
    containers = {
      for name, container in var.containers : name => {
        ip       = container.ip
        hostname = container.hostname
        username = var.ssh_user
        password = container.password != null ? container.password : random_password.container_passwords[name].result
      }
    }
  })
  filename = "${path.module}/${var.ssh_passwords_file}"
  file_permission = "0600"
}

# Ensure the SSH passwords file is added to .gitignore
resource "local_file" "update_gitignore" {
  content = <<-EOT
# Ensure SSH passwords file is ignored
${var.ssh_passwords_file}
  EOT
  filename = "${path.module}/.gitignore"
  file_permission = "0644"
}

# Create a structured SSH access information file for Ansible
resource "local_file" "ansible_ssh_info" {
  content = jsonencode({
    ssh_key_path = local_file.private_key.filename
    ssh_key_content = tls_private_key.ssh_key.private_key_pem
    ssh_public_key = tls_private_key.ssh_key.public_key_openssh
    containers = {
      for name, container in proxmox_lxc.containers : name => {
        id = container.id
        ip = container.network[0].ip
        hostname = container.hostname
        user = var.ssh_user
        password = container.password
      }
    }
  })
  filename = "${path.module}/../ansible/ssh_access.json"
  file_permission = "0600"
  
  depends_on = [proxmox_lxc.containers, local_file.private_key]
}

# Add this after ssh_passwords file creation
resource "local_file" "ssh_readme" {
  content = <<-EOT
# SSH Access Information
This file provides information about SSH access to the deployed containers.

## SSH Private Key
Location: ${local_file.private_key.filename}

## Container Access
${join("\n", [for name, container in proxmox_lxc.containers :
"- ${container.hostname} (${name}): ssh -i ${local_file.private_key.filename} ${var.ssh_user}@${split("/", container.network[0].ip)[0]}"])}

## Ansible Integration
Ansible can consume the SSH access information from:
- SSH Keys: ${local_file.private_key.filename}
- Structured data: ${local_file.ansible_ssh_info.filename}
- Passwords: ${local_file.ssh_passwords.filename}

This file is automatically regenerated when containers are recreated.
EOT
  filename = "${path.module}/../ansible/SSH_ACCESS_README.md"
  file_permission = "0644"
  
  depends_on = [local_file.ansible_ssh_info, local_file.ssh_passwords, local_file.private_key]
}

# Run Ansible playbook automatically
resource "null_resource" "run_ansible" {
  depends_on = [
    proxmox_lxc.containers,
    local_file.ansible_inventory,
    local_file.ansible_config,
    local_file.ansible_group_vars,
    local_file.ansible_ssh_tasks,
    local_file.ansible_handlers,
    null_resource.ansible_directory_structure
  ]
  
  triggers = {
    containers = join(",", [for c in proxmox_lxc.containers : c.id])
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Checking for Ansible availability..."
      if command -v ansible-playbook >/dev/null 2>&1; then
        echo "Running Ansible playbook..."
        cd ${path.module}/../ansible && ansible-playbook -i inventory/hosts.yml playbook.yml
      else
        echo "WARNING: ansible-playbook command not found. Skipping Ansible run."
        echo "To configure containers, please install Ansible and run:"
        echo "cd ${path.module}/../ansible && ansible-playbook -i inventory/hosts.yml playbook.yml"
      fi
    EOT
  }
}

# Output completion message
resource "null_resource" "completion_message" {
  depends_on = [null_resource.run_ansible]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "=================================================="
      echo "All containers have been created and configured successfully!"
      echo "=================================================="
      echo ""
      echo "Service access information:"
      echo ""
      ${join("", [for name, container in var.containers : <<-CONTAINER
      echo "${name}: ${container.ip}"
      echo "  SSH: ssh -i ${local_file.private_key.filename} ${var.ssh_user}@${container.ip}"
      echo ""
      CONTAINER
      ])}
      
      ${contains(keys(var.containers), "pihole") ? "echo \"Pi-hole web interface: http://${var.containers["pihole"].ip}/admin\"" : ""}
      ${contains(keys(var.containers), "opensearch") ? "echo \"OpenSearch dashboard: http://${var.containers["opensearch"].ip}:5601\"" : ""}
      echo ""
      echo "SSH private key has been saved to: ${local_file.private_key.filename}"
      echo "SSH passwords have been saved to: ${local_file.ssh_passwords.filename}"
      echo ""
    EOT
  }
}