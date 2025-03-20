# Proxmox provider connection variables
variable "proxmox_api_url" {
  description = "The Proxmox API URL"
  type        = string
  validation {
    condition     = can(regex("^https://.+:[0-9]+/api2/json$", var.proxmox_api_url))
    error_message = "The proxmox_api_url must be a valid URL ending with /api2/json."
  }
}

variable "proxmox_api_token_id" {
  description = "The Proxmox API token ID"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "The Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification for Proxmox API"
  type        = bool
  default     = true
}

# Network configuration
variable "gateway_ip" {
  description = "Default gateway IP address"
  type        = string
  default     = "192.168.0.1"
}

variable "subnet_mask" {
  description = "Network subnet mask"
  type        = string
  default     = "24"
}

variable "nameserver" {
  description = "Default DNS server IP address"
  type        = string
  default     = "192.168.0.1"
}

# SSH connection details for provisioning
variable "ssh_user" {
  description = "SSH username for provisioning"
  type        = string
  default     = "root"
}

variable "ssh_password" {
  description = "SSH password for provisioning"
  type        = string
  sensitive   = true
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning (alternative to password)"
  type        = string
  default     = ""
}

# Proxmox host configurations
variable "proxmox_hosts" {
  description = "Proxmox hosts details"
  type = map(object({
    node_name = string
    ip        = string
  }))
  default = {
    "proxmox2" = {
      node_name = "proxmox2"
      ip        = "192.168.0.7"
    },
    "pve" = {
      node_name = "pve"
      ip        = "192.168.0.45"
    }
  }
}

# LXC container configurations
variable "containers" {
  description = "LXC container configurations"
  type = map(object({
    id           = number         # Container ID
    hostname     = string
    ip           = string
    cores        = number
    memory       = number
    swap         = number
    storage_size = number
    storage_type = string
    host         = string
    ostemplate   = string
    unprivileged = bool
    features     = map(number)
    onboot       = number
    start_after_create = bool
    password     = optional(string) # Optional unique password for each container
    tags         = optional(string)
  }))
}

# New variable for SSH passwords file
variable "ssh_passwords_file" {
  description = "Path to save the SSH passwords file for containers"
  type        = string
  default     = "ssh_passwords.json"
}

# Service-specific configurations
variable "pihole_webpassword" {
  description = "Password for Pi-hole web interface"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "opensearch_password" {
  description = "Password for OpenSearch admin user"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "dhcp_server_ranges" {
  description = "DHCP server IP ranges"
  type        = list(object({
    range_start = string
    range_end   = string
    subnet      = string
    netmask     = string
  }))
  default = [
    {
      range_start = "192.168.0.150"
      range_end   = "192.168.0.200"
      subnet      = "192.168.0.0"
      netmask     = "255.255.255.0"
    }
  ]
}
