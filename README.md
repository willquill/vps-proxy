# vps-proxy

Create a VPS that runs

- [Traefik](https://traefik.io/traefik) (reverse proxy) w/ [oidc-auth](https://github.com/sevensolutions/traefik-oidc-auth) plugin
- [Pocket ID](https://github.com/pocket-id/pocket-id) (OIDC identity provider)
- [Gatus](https://gatus.io/) (uptime monitoring and alerting)
- Wireguard tunnel to another network

Automation tasks:

- Creates a firewall and virtual private server (VPS) in Hetzner Cloud
- Installs, configures, and starts Wireguard on the VPS
- Installs Docker on the VPS and executes a docker compose file to spin up docker services

## Overview

![Architecture Diagram](architecture_diagram.png)

## Just tell me how I can use this without being an expert coder

Okay, so you want to have your own Debian server running docker compose services? Easy enough.

You need to already have:

- AWS account with programmatic access (just for the OpenTofu state resources - **all free tier**)
- A Hetzner Cloud account
- MaxMind license key (see link in [Use of Secrets](#use-of-secrets))
- An SSH key pair
- A domain purchased anywhere (I use [porkbun.com](https://porkbun.com/)) but using Cloudflare nameservers

Clone or fork this repo and then do the following:

1. Create an SSH key pair. Or use one you already have.

2. Populate the secrets in your GitHub repo.

3. Add or remove docker services to your preference (within `ansible/roles/deploy/files/docker-compose.yml`). Don't forget to add the configuration directories to the `with_items` list in the Ansible task within `ansible/roles/deploy/tasks/main.yml`.

4. Tweak the environment variables as necessary.

5. `cd` into the `tfstate` directory, update `main.tf` to your preference, and apply the Terraform to create an S3 bucket and DynamoDB which will be utilized for the OpenTofu automation state.

6. Commit, push, create a PR, and watch the magic happen!

## Use of Secrets

GitHub Actions needs several environment secrets for CI/CD. Some need to be encrypted - others not really, but I'm encrypted them all anyway.

| Secret Name                   | Purpose                              | How to Generate                                                                                    |
| ----------------------------- | ------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `VPS_HOST`                    | VPS hostname or IP                   | Provided by Hetzner Cloud after VPS creation                                                       |
| `VPS_PROXY_KEY`               | SSH private key for VPS access       | `ssh-keygen -t ed25519`                                                                            |
| `VPS_USER`                    | SSH username for VPS                 | Your chosen username (e.g., GitHub username)                                                       |
| `HCLOUD_TOKEN`                | Hetzner Cloud API token              | Generated in Hetzner Cloud Console → Security → API Tokens                                         |
| `TRAEFIK_BASIC_AUTH_USERNAME` | Traefik dashboard username           | Your chosen username                                                                               |
| `TRAEFIK_BASIC_AUTH_PASSWORD` | Traefik dashboard password (hashed)  | `echo $(htpasswd -nb user password) \| sed -e s/\\$/\\$\\$/g`                                      |
| `TRAEFIK_OIDC_AUTH_SECRET`    | OIDC authentication secret           | `openssl rand -base64 36`                                                                          |
| `TRAEFIK_OIDC_CLIENT_ID`      | OIDC client identifier               | Provided by your identity provider                                                                 |
| `TRAEFIK_OIDC_CLIENT_SECRET`  | OIDC client secret                   | Provided by your identity provider                                                                 |
| `MAXMIND_LICENSE_KEY`         | MaxMind GeoIP license key            | [MaxMind signup](https://www.maxmind.com/en/geolite2/signup)                                       |
| `ACME_EMAIL`                  | Email for Let's Encrypt certificates | Your email address                                                                                 |
| `PUBLIC_DOMAIN`               | Your public domain name              | Your registered domain (e.g., example.com)                                                         |
| `CF_DNS_API_TOKEN`            | Cloudflare DNS API token             | [Cloudflare API tokens](https://dash.cloudflare.com/profile/api-tokens) with DNS:Edit permissions  |
| `CF_ZONE_API_TOKEN`           | Cloudflare Zone API token            | [Cloudflare API tokens](https://dash.cloudflare.com/profile/api-tokens) with Zone:Read permissions |
| `TZ`                          | Timezone for containers              | IANA timezone (e.g., America/New_York)                                                             |

### Ansible Secrets

Ensure that every secret in your "Run ansible playbook" task within `.github/workflows/deploy.yml` is also in your GitHub environment secrets, as these secrets are used to populate the values within your Traefik configuration files and more.

### Docker Compose Secrets

See `ansible/roles/deploy/templates/env.j2` for all variables. **_Note: Some of the variables are defined in the GitHub Actions `ansible-playbook` command and others are vars in `ansible/main.yml`_**

## Details

### Routing

Your subdomains will point to your VPS, and Traefik will be listening on 443 so that it may forward your requests to either services hosted within the VPS (via labels on the docker compose services) or to services hosted on your home network (via the file provider, i.e. `services.yml.j2`), as there will be a Wireguard tunnel between the VPS and your home network.

Like this: `https://<your-service>.<your-domain>.<your-tld>` > Traefik on the VPS > Wireguard tunnel to home network > Service hosted at home

In my case, I'm actually forwarding all requests to another Traefik instance running at home, so I have two paths:

```
Internet → VPS-Traefik → WireGuard → LAN-Traefik → Service
LAN → LAN-Traefik → Service
```

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

### Hetzner Cloud

I use Hetzner Cloud, but you can update the files within the `opentofu` directory to provision your VPS elsewhere. You will need to first create a project manually in the [Hetzner console](console.hetzner.com). Then go to Security, upload the SSH key you created, and create an API key for Terraform.

If you use GitHub Actions to deploy, use the ones from this repo. Otherwise, deploy manually in the order seen in the deploy action.

### WireGuard Setup with OPNsense

The Ansible playbook automatically configures WireGuard on the VPS server. To set up the VPS-OPNsense tunnel, follow these steps:

### After Ansible Deployment

1. SSH into your VPS and retrieve the WireGuard public key:

```
cat /etc/wireguard/publickey
```

2. Note your VPS's public IP address.

### OPNsense Configuration

1. On your OPNsense router, navigate to **VPN > WireGuard > Instances**
2. Click **+ Add** to create a new WireGuard peer configuration:

- **Name**: vps-proxy
- **Public Key**: Leave blank (will be generated)
- **Private Key**: Click "Generate" button
- **Listen Port**: I use 51821 because 51820 is already in use in my case
- **Tunnel Address**: 192.168.145.2/24 (must be in same subnet as VPS but different IP)
- **Disable Routes**: Unchecked
- **Peers**: Leave empty for now

3. Navigate to **VPN > WireGuard > Endpoints**
4. Click **+ Add** to create a new endpoint:

- **Name**: vps-proxy
- **Public Key**: Paste the public key from your VPS
- **Shared Secret**: Leave blank
- **Allowed IPs**: 192.168.145.1/32
- **Endpoint Address**: Your VPS's public IP address
- **Endpoint Port**: 51820
- **Instances**: vps-proxy
- **Keepalive**: 25 (recommended)

5. Navigate to **VPN > WireGuard > General**
6. Check **Enable WireGuard** and save

7. Create firewall rule to allow the VPS proxy's public IP to hit your WAN interface:

- Firewall > Aliases > create a new one
- **Name**: vps_proxy_wan_ip
- **Content**: ddns.<yourdomain> (the value you gave to PUBLIC_DOMAIN)
- Diagnostics > Aliases > select the alias and you should see the IP address!
- Firewall > Rules > WAN > create a new one
- **Source**: Alias you just created
- **Destination**: WAN address
- **Port**: 51821

7. Create new interface for the Wireguard tunnel

- Interfaces > Assignments > Assign a new interface
- **Device**: wg1
- **Description**: VPSProxyWG
- Interfaces > VPSProxyWG > Enable Interface

8. Allow the VPS proxy to hit internal IPs

- Firewall > Rules > VPSProxyWG
- Create a new rule
- **Source**: \*
- **Destination**: Whatever you want
- **Port**: Whatever you want

### VPS Configuration Update

To add your OPNsense router as a peer on the VPS, SSH into your VPS and run:

```bash
# Get your OPNsense router's public key from the OPNsense UI
OPNSENSE_PUBKEY="your_opnsense_public_key_here"
YOUR_HOME_PUBLIC_IP="home IP or DDNS FQDN"

# Add the peer to your WireGuard configuration
sudo wg set wg0 peer $OPNSENSE_PUBKEY allowed-ips 192.168.145.2/32,10.1.0.0/16 endpoint $YOUR_HOME_PUBLIC_IP:51821 persistent-keepalive 25

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
