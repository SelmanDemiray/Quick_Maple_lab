output "container_ips" {
  description = "IP addresses of provisioned containers"
  value = {
    for name, container in proxmox_lxc.containers :
    name => "${container.hostname}: ${container.network[0].ip}"
  }
}

output "opensearch_dashboard_url" {
  description = "URL to access OpenSearch Dashboard"
  value = contains(keys(proxmox_lxc.containers), "opensearch") ? "http://${split("/", proxmox_lxc.containers["opensearch"].network[0].ip)[0]}:5601" : "OpenSearch not deployed"
}

output "pihole_admin_url" {
  description = "URL to access Pi-hole admin interface"
  value = contains(keys(proxmox_lxc.containers), "pihole") ? "http://${split("/", proxmox_lxc.containers["pihole"].network[0].ip)[0]}/admin" : "Pi-hole not deployed"
}

output "dhcp_server_ranges" {
  description = "Configured DHCP server IP ranges"
  value = var.dhcp_server_ranges
}

output "ssh_passwords_file" {
  description = "Path to the generated SSH passwords file"
  value = local_file.ssh_passwords.filename
  sensitive = true
}

output "container_passwords" {
  description = "Container SSH passwords (sensitive)"
  value = {
    for name, container in var.containers :
    name => container.password != null ? container.password : random_password.container_passwords[name].result
  }
  sensitive = true
}

output "ssh_private_key" {
  description = "SSH private key for accessing all containers (sensitive)"
  value       = tls_private_key.ssh_key.private_key_pem
  sensitive   = true
}

output "ssh_public_key" {
  description = "SSH public key deployed to all containers"
  value       = tls_private_key.ssh_key.public_key_openssh
}

output "ssh_key_path" {
  description = "Path to the SSH private key file"
  value       = local_file.private_key.filename
}
