# Ansible Configuration for Containers

This directory contains the Ansible configuration files to manage the containers created by Terraform.

## Directory Structure
- `inventory/hosts.yml` - Inventory file containing all container hosts
- `group_vars/all.yml` - Variables applied to all hosts
- `ansible.cfg` - Ansible configuration
- `playbook.yml` - Main playbook for container provisioning
- `tasks/` - Task files imported by playbooks
- `handlers/` - Handler files for service management
- `roles/` - Role-specific configurations
- `playbooks/` - Additional playbooks including health checks
- `health_checks/` - Health monitoring system files

## Usage

To apply configurations to all containers:

```bash
ansible-playbook -i inventory/hosts.yml playbook.yml
```

To apply configurations to specific container types:

```bash
ansible-playbook -i inventory/hosts.yml playbook.yml --limit dhcp_servers
ansible-playbook -i inventory/hosts.yml playbook.yml --limit opensearch_nodes
ansible-playbook -i inventory/hosts.yml playbook.yml --limit pihole_servers
ansible-playbook -i inventory/hosts.yml playbook.yml --limit suricata_hosts
```

## SSH Access

SSH credentials are stored in `ssh_access.json` and SSH keys in `id_rsa`.

## Health Check System

The health check system monitors all services and reports their status to Slack.

### Slack Configuration

To configure Slack notifications, you need to set up an incoming webhook:

1. Go to https://api.slack.com/apps/A08JJTUEPU1/incoming-webhooks
2. Click "Add New Webhook to Workspace"
3. Select the channel where notifications should appear
4. Copy the webhook URL
5. Update `/home/ansible/retry/ansible/health_checks/config.json` with the URL

Alternatively, you can use API token authentication:
1. Set `"auth_method": "api"` in `config.json`
2. Ensure your app has the `chat:write` scope
3. Generate a bot token and add it to the `token` field in the `slack_app` section

### Manual Execution

To run a health check manually:

```bash
/home/ansible/retry/ansible/health_checks/run_health_check.sh
```

### Automated Checks

Health checks run automatically every 30 minutes via cron. To install the cron job:

```bash
crontab -l | cat - /home/ansible/retry/ansible/crontab_entry | crontab -
```

### Configuration

To configure the Slack webhook and other settings, edit:
`/home/ansible/retry/ansible/health_checks/config.json`

### Status Files

Individual host status files are stored in:
`/home/ansible/retry/ansible/health_checks/{hostname}_status.json`
