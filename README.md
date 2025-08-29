# vps-proxy

!!!! THIS IS A WIP !!!!

The aim is to deploy the following to a VPS:

- Wireguard
- Traefik (listens on 22 for GitLab, 443, and 80)
- Authentik
- Gatus

## Overview

## Routing

Your subdomains will point to your VPS, and Traefik will be listening on 443 so that it may forward your requests to either services hosted within the VPS or to services hosted on your home network, as there will be a Wireguard tunnel between the VPS and your home network

Like this: `https://<your-service>.<your-domain>.<your-tld>` > Traefik on the VPS > Wireguard tunnel to home network > Service hosted at home

In my case, I'm actually forwarding all requests to another Traefik instance running at home, so I have two paths:

```
Internet → VPS-Traefik → WireGuard → LAN-Traefik → Service
LAN → LAN-Traefik → Service
```

## Use of Secrets

GitHub Actions needs several environment secrets for CI/CD. Some need to be encrypted - others not really, but I'm encrypted them all anyway.

1. Connecting to your VPS (and Ansible inventory file minus the proxy key)

```sh
VPS_HOST=yourhost.domain.tld
VPS_PROXY_KEY=your_ssh_private_key
VPS_USER=your_ssh_username
```

2. More Ansible playbook variables. Ensure that every secret in your "Run ansible playbook" task within `.github/workflows/deploy.yml` is also in your GitHub environment secrets, as these secrets are used to populate the values within your Traefik configuration files, Authentik configuration files, and more.

3. Creating .env file for Docker compose. See `ansible/templates/env.j2` for all variables. **_Note: Some of the variables are defined in the GitHub Actions `ansible-playbook` command and others are vars in `ansible/main.yml`_**

## Prerequisites

Generate all of the secrets you need above. I won't walk you through all of it, but here are some pointers:

1. SSH key

```sh
ssh-keygen -t ed25519 -C "vpsproxykey@mail.willq.net" -f ~/.ssh/vps_proxy_key
```

2. Create Cloudflare [API tokens here](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/).

Also, create the DNS records for the services you'll want behind your Traefik instance

3. Generate Authentik secrets. You don't actually need the files - just the contents of the files. This command is what I ran when I was using Docker secrets instead of GitHub secrets:

```sh
printf "%s" "$(openssl rand -base64 36 | tr -d '\n')" > ${PWD}/secrets/authentik_postgresql_password &&\
  printf "%s" "$(openssl rand -base64 36 | tr -d '\n')" > ${PWD}/secrets/authentik_postgresql_user &&\
  printf "%s" "$(openssl rand -base64 36 | tr -d '\n')" > ${PWD}/secrets/authentik_postgresql_db &&\
  printf "%s" "$(openssl rand -base64 36 | tr -d '\n')" > ${PWD}/secrets/authentik_secret_key
```

4. Modify the `cloud-init.yaml` file for your needs.

## Installation

For my example, I use Hetzner Cloud. You will need to first create a project manually in the [Hetzner console](console.hetzner.com). Then go to Security, upload the SSH key you created, and create an API key for Terraform.

## Terraform

First, spin up the cloud server. I used [this cloud-init](https://community.hetzner.com/tutorials/basic-cloud-config) with a few modifications of my own. See my `cloud-init.yaml` file.

You can use Terraform or just do it manually.

If using Terraform, ensure that GitLab has the following secrets:

- `HCLOUD_TOKEN` - This is the Hetzner Cloud API Token

Move on to [Wireguard Setup with OPNsense](#wireguard-setup-with-opnsense)

## WireGuard Setup with OPNsense

The Ansible playbook automatically configures WireGuard on the VPS server. To set up the VPS-OPNsense tunnel, follow these steps:

### After Ansible Deployment

1. SSH into your VPS and retrieve the WireGuard public key:

```
cat /etc/wireguard/publickey
```

2. Note your VPS's public IP address.

### OPNsense Configuration

1. On your OPNsense router, navigate to **VPN > WireGuard > Local**
2. Click **+ Add** to create a new WireGuard local configuration:

- **Name**: VPS-Peer (or any descriptive name)
- **Public Key**: Leave blank (will be generated)
- **Private Key**: Click "Generate" button
- **Listen Port**: Choose a port (e.g., 51821)
- **Tunnel Address**: 192.168.145.2/24 (must be in same subnet as VPS but different IP)
- **Disable Routes**: Unchecked
- **Peers**: Leave empty for now

3. Navigate to **VPN > WireGuard > Endpoints**
4. Click **+ Add** to create a new endpoint:

- **Name**: VPS-Endpoint (or any descriptive name)
- **Public Key**: Paste the public key from your VPS
- **Shared Secret**: Leave blank
- **Allowed IPs**: 192.168.145.1/32
- **Endpoint Address**: Your VPS's public IP address
- **Endpoint Port**: 51820
- **Keepalive**: 25 (recommended)

5. Navigate back to **VPN > WireGuard > Local**
6. Edit your local configuration and select your new endpoint under **Peers**

7. Navigate to **VPN > WireGuard > General**
8. Check **Enable WireGuard** and save

9. Create necessary firewall rules to:

- Allow traffic from your WireGuard interface to local networks
- Allow traffic from your VPS through the WireGuard tunnel

### VPS Configuration Update

To add your OPNsense router as a peer on the VPS, SSH into your VPS and run:

```bash
# Get your OPNsense router's public key from the OPNsense UI
OPNSENSE_PUBKEY="your_opnsense_public_key_here"

# Add the peer to your WireGuard configuration
sudo wg set wg0 peer $OPNSENSE_PUBKEY allowed-ips 192.168.145.2/32
sudo wg-quick save wg0
```

### Testing the Connection

To test if the WireGuard tunnel is working:

1. From VPS: `ping 192.168.145.2`
2. From OPNsense: `ping 192.168.145.1`

You can also check the connection status in OPNsense under **VPN > WireGuard > Status**

## Automation Overview:

- You'll use this `cloud-init.yaml` file to initially provision your VPS.
- GitHub actions will use Ansible to prepare your VPS configuration, install Docker, clone this repo, and apply the docker compose file.

## CI/CD Pipeline

This repository uses GitHub Actions for CI/CD workflows to ensure code quality and automate deployment:

### Continuous Integration (CI)

The CI workflow (`.github/workflows/ci.yml`) runs on pull requests to the main branch and includes:

- **Syntax and Linting Checks**:

  - Ansible Lint: Validates Ansible playbooks and roles
  - YAML Lint: Ensures YAML files follow best practices
  - Docker Compose Validation: Verifies docker-compose.yml is valid

- **Security Scanning**:

  - Secret Detection: Uses Gitleaks to detect accidentally committed secrets
  - Vulnerability Scanning: Uses Trivy to scan for security vulnerabilities

- **Functional Testing**:

  - Ansible Dry Run: Tests playbooks in check mode without making changes
  - Container Build Test: Ensures Docker containers build correctly

- **Documentation Checks**:
  - Markdown Linting: Validates formatting of documentation

### Continuous Deployment (CD)

The deployment workflow (`.github/workflows/deploy.yml`) runs on pushes to the main branch and:

1. Sets up SSH connection to your VPS
2. Runs the Ansible playbook to configure your VPS
3. Deploys the services using Docker Compose

To use these workflows, ensure you've configured the required GitHub Secrets as detailed in the "Use of Secrets" section.

## Development

1. Use [nektos/act](https://github.com/nektos/act) to test GitHub Actions locally - big time saver!
