# vps-proxy

!!!! THIS IS A WIP !!!!

This does the following:

- Creates a firewall and virtual private server (VPS) in Hetzner Cloud
- Installs, configures, and starts Wireguard on the VPS
- Installs Docker on the VPS and executes a docker compose file to spin up docker services

Intention:

- The VPS runs Traefik, Authentik, Gatus, and others as docker services to act as a reverse proxy and IDP for requests that are ultimately forwarded elsewhere

## Overview

![Architecture Diagram](architecture_diagram.png)

## Routing

Your subdomains will point to your VPS, and Traefik will be listening on 443 so that it may forward your requests to either services hosted within the VPS or to services hosted on your home network, as there will be a Wireguard tunnel between the VPS and your home network

Like this: `https://<your-service>.<your-domain>.<your-tld>` > Traefik on the VPS > Wireguard tunnel to home network > Service hosted at home

In my case, I'm actually forwarding all requests to another Traefik instance running at home, so I have two paths:

```
Public client → VPS-Traefik → WireGuard → LAN-Traefik → Service

and

Private client → LAN-Traefik → Service
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

### Prepare Terraform State Backend

Instead of storing the Terraform state locally or committing it to GitHub, I'm going to keep mine in AWS S3 and use DynamoDB for state locking. The [terraform-aws-bootstrap](https://github.com/trussworks/terraform-aws-bootstrap) module makes this super easy.

I do this part manually since it is only done once.

`cd` into `./terraform/tfstate`, run "aws configure", enter your key ID and access key for your AWS user, then do `terraform apply`. Why Terraform and not OpenTofu? Because I don't know of a similar module for OpenTofu, and I was too lazy to build it myself.

In sum:

- Terraform will be used _manually_ to create the S3 bucket to store the OpenTofu state and DynamoDB for state locking
- OpenTofu will be used _with GitHub Actions_ to create the Hetzner Cloud resources.

If you did a `tofu apply` before creating your backend, you can migrate your local tfstate file to the remote state by simply executing `tofu init` as follows:

```txt
$ tofu init

Initializing the backend...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly
  configured "s3" backend. Do you want to copy this state to the new "s3"
  backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value: yes
```

## Installation

For my example, I use Hetzner Cloud. You will need to first create a project manually in the [Hetzner console](console.hetzner.com). Then go to Security, upload the SSH key you created, and create an API key for Terraform.

If you use GitHub Actions to deploy, use the ones from this repo. Otherwise, deploy manually in the order seen in the deploy action.

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

## Development

Use [nektos/act](https://github.com/nektos/act) to test GitHub Actions locally - big time saver!

Here's a [helpful gist with example usages of the deb822_repository Ansible module](https://gist.github.com/roib20/27fde10af195cee1c1f8ac5f68be7e9b)

### Local testing

When testing with Ansible, do the following:

```sh
ansible-galaxy install -r galaxy-requirements.yml
```

And then run the `ansible-playbook` command found in the workflow but replace the variables with your own (unless you use nektos/act).
