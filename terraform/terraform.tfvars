# Proxmox API connection
proxmox_api_url = "https://192.168.0.7:8006/api2/json"
proxmox_api_token_id = "root@pam!terraform"
proxmox_api_token_secret = "835ff11e-c7b2-4836-98c9-7fb6761d3fad"
proxmox_tls_insecure = true

# SSH credentials for provisioning
ssh_user = "root"
ssh_password = "ansible123"  # Changed to a simpler password without special characters
# ssh_private_key_path = "~/.ssh/id_rsa"  # Uncomment to use key-based auth

# Service passwords
pihole_webpassword = "5jb93Q23p5586MGi7j"
opensearch_password = "C87V48V593245ks99f"

# Network configuration
gateway_ip = "192.168.0.1"
subnet_mask = "24"

# Container configurations
containers = {
  "opensearch" = {
    id           = 1099
    hostname     = "opensearch-dashboard"
    ip           = "192.168.0.99"
    cores        = 2
    memory       = 10000
    swap         = 10000
    storage_size = 3000
    storage_type = "local-lvm"
    host         = "proxmox2"
    ostemplate   = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    unprivileged = true
    features     = { "nesting" = 1 }
    onboot       = 1
    start_after_create = true
    password     = null  # Set to null to use auto-generated password
    tags         = "infra,monitoring"
  },
  
  "dhcp" = {
    id           = 1010
    hostname     = "isc-dhcp-server"
    ip           = "192.168.0.10"
    cores        = 2
    memory       = 2000
    swap         = 2000
    storage_size = 100
    storage_type = "local-lvm"
    host         = "proxmox2"
    ostemplate   = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    unprivileged = true
    features     = { "nesting" = 1 }
    onboot       = 1
    start_after_create = true
    password     = null  # Set to null to use auto-generated password
    tags         = "infra,network"
  },
  
  "suricata" = {
    id           = 197
    hostname     = "suricata-filebeat"
    ip           = "192.168.0.97"
    cores        = 3
    memory       = 6400
    swap         = 4048
    storage_size = 600
    storage_type = "local-lvm"
    host         = "pve"
    ostemplate   = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
    unprivileged = true
    features     = { "nesting" = 1 }
    onboot       = 1
    start_after_create = true
    password     = null  # Set to null to use auto-generated password
    tags         = "security,monitoring"
  },
  
  "pihole" = {
    id           = 102
    hostname     = "pihole"
    ip           = "192.168.0.102"
    cores        = 1
    memory       = 1270
    swap         = 1270
    storage_size = 276
    storage_type = "local-lvm"
    host         = "pve"
    ostemplate   = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    unprivileged = true
    features     = { "nesting" = 0 }
    onboot       = 1
    start_after_create = true
    password     = null  # Set to null to use auto-generated password
    tags         = "infra,dns"
  }
}

# DHCP server configuration
dhcp_server_ranges = [
  {
    subnet      = "192.168.0.0"
    netmask     = "255.255.255.0"
    range_start = "192.168.0.2"
    range_end   = "192.168.0.232"
  }
]
