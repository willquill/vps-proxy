# CLAUDE.md - VPS Proxy Project Guide

## Project Overview

This repository deploys a VPS running Docker Compose services behind a Traefik reverse proxy, provisioned via Ansible and GitHub Actions. Traefik handles TLS termination (via Cloudflare DNS challenge) and routes traffic to Docker services or to LAN services over a WireGuard tunnel.

## Architecture

- **Traefik** is the reverse proxy with entrypoints `web` (port 80) and `websecure` (port 443)
- HTTP-to-HTTPS redirect is handled globally in `traefik.yml` (not per-service)
- **CrowdSec** provides security via a Traefik bouncer plugin
- **Pocket ID** provides OIDC authentication for services without native auth
- Services are either VPS-hosted (Docker containers) or LAN-hosted (forwarded via WireGuard)

## Key Files

| File                                            | Purpose                                          |
| ----------------------------------------------- | ------------------------------------------------ |
| `ansible/roles/deploy/files/docker-compose.yml` | All Docker services                              |
| `ansible/roles/deploy/templates/env.j2`         | Environment variables template (Jinja2)          |
| `.github/workflows/deploy.yml`                  | CI/CD pipeline with Ansible variables            |
| `ansible/roles/deploy/tasks/main.yml`           | Ansible tasks (directories, configs, deployment) |
| `ansible/roles/traefik/files/traefik.yml`       | Traefik static configuration                     |
| `ansible/roles/traefik/files/middlewares.yml`   | Traefik middleware definitions                   |
| `ansible/roles/traefik/files/services.yml`      | Traefik file provider for LAN services           |
| `ansible/roles/deploy/files/gatus/config.yml`   | Gatus uptime monitoring endpoints                |
| `README.md`                                     | Project documentation                            |

## Adding a New VPS Service

When adding a new Docker service that runs on the VPS:

### 1. Docker Compose (`ansible/roles/deploy/files/docker-compose.yml`)

Add the service definition. Use the existing YAML anchors:

- `*proxy-labels` for Traefik discovery labels
- `*common` for security_opt, user, restart, pull_policy

Traefik labels pattern (no HTTP redirect needed - it's global):

```yaml
labels:
  <<: *proxy-labels
  traefik.http.routers.<service>.entrypoints: "websecure"
  traefik.http.routers.<service>.rule: "Host(`<subdomain>.${PUBLIC_DOMAIN}`)"
  traefik.http.routers.<service>.tls: "true"
  traefik.http.routers.<service>.service: "<service>"
  traefik.http.services.<service>.loadbalancer.server.port: "<port>"
  traefik.http.routers.<service>.middlewares: "public@file"
```

Use `"public-oidc-auth@file"` middleware instead of `"public@file"` if the service should be protected by Pocket ID OIDC.

If the service needs its own internal network (e.g., for a database), add a new network at the bottom of the file.

### 2. Environment Variables (`ansible/roles/deploy/templates/env.j2`)

Add any new environment variables with their Ansible variable mappings:

```jinja2
# Service Name
VARIABLE_NAME={{ ansible_variable_name }}
```

### 3. GitHub Actions (`/.github/workflows/deploy.yml`)

Add `-e` flags to the `ansible-playbook` command for each new Ansible variable:

```yaml
-e "ansible_variable_name=${{ secrets.SECRET_NAME }}"
```

### 4. Config Directories (`ansible/roles/deploy/tasks/main.yml`)

Add the service's config directory to the "Create application configuration directories" task:

```yaml
- "<service_name>"
```

### 5. Gatus Monitoring (`ansible/roles/deploy/files/gatus/config.yml`)

Add a new endpoint entry to the `endpoints` list. Do not configure alerts for new services.

If the service is **not** behind OIDC authentication:

```yaml
  - name: <Service Name>
    group: Backend
    url: "https://<subdomain>.${PUBLIC_DOMAIN}/"
    interval: 30s
    conditions:
      - "[STATUS] == 200"
```

If the service **is** behind OIDC authentication (Traefik OIDC middleware or native OIDC):

```yaml
  - name: <Service Name>
    group: Backend
    url: "https://<subdomain>.${PUBLIC_DOMAIN}/"
    interval: 30s
    conditions:
      # Because it's behind authentication
      - "[STATUS] == 401"
```

### 6. README (`README.md`)

- Add the service to the list at the top
- Add a section describing setup steps
- Add any new secrets to the "Use of Secrets" table

### 7. GitHub Secrets

Create any new secrets in the GitHub repository environment (`hetzner-cloud`).

## Adding a New LAN Service

LAN services are services already running on your home network, exposed through the VPS via WireGuard + Traefik file provider.

### 1. Traefik File Provider (`ansible/roles/traefik/files/services.yml`)

Add a new router entry:

```yaml
new_service:
  entryPoints:
    - "websecure"
  rule: 'Host(`{{env "LAN_NEW_SERVICE"}}.{{env "PUBLIC_DOMAIN"}}`)'
  middlewares:
    - public
  tls: {}
  service: lan_traefik
```

### 2. Environment Variables (`ansible/roles/deploy/templates/env.j2`)

Add the new LAN variable in the "Traefik to LAN" section:

```jinja2
LAN_SERVICE3={{ lan_new_service }}
```

The new LAN variable will always follow the schema: `LAN_SERVICE<iteration>`. So if LAN_SERVICE2 is the highest number LAN service, the next one would be named `LAN_SERVICE3`. Do not blindly use `LAN_SERVICE3` for every LAN service, despite the fact that the following instructions use this iteration for the examples.

### 3. Docker Compose - Traefik Service

Add the new environment variable to the Traefik service's environment list in `docker-compose.yml`:

```yaml
- LAN_SERVICE3
```

### 4. GitHub Actions (`/.github/workflows/deploy.yml`)

Add the `-e` flag:

```yaml
-e "lan_service3=${{ secrets.LAN_SERVICE3 }}"
```

### 5. README

Add the new secret to the secrets table and document the service.

## Middleware Reference

| Middleware              | Use Case                                             |
| ----------------------- | ---------------------------------------------------- |
| `public@file`           | Default: security headers + rate limiting + CrowdSec |
| `public-oidc-auth@file` | Same as public + Pocket ID OIDC via Traefik plugin   |
| `private@file`          | RFC1918 IPs only (LAN access)                        |

### OIDC: Traefik-Level vs Application-Level

There are two distinct ways a service can use Pocket ID for authentication:

**Traefik-level OIDC** (`public-oidc-auth@file`): The `traefik-oidc-auth` plugin intercepts requests at the reverse proxy before they reach the service. Use this for services that have **no native OIDC support** (e.g., the Traefik dashboard). All services sharing this middleware use one shared OIDC client in Pocket ID, with one callback URL per service.

**Application-level OIDC** (`public@file`): The service itself handles OIDC natively (e.g., tuwunel's `identity_provider` config). Traefik just forwards traffic — the service redirects users to Pocket ID on its own. Use `public@file` (not `public-oidc-auth@file`) to avoid Traefik intercepting requests meant for the service's own OIDC flow. These services require their own **separate** OIDC client in Pocket ID.

**Do NOT stack both.** Applying `public-oidc-auth@file` to a service with native OIDC will break it — Traefik's plugin will intercept the service's own SSO callbacks and API requests, and mobile/desktop clients that use non-browser auth flows will fail.

## Conventions

- Container names match service names
- Subdomains follow pattern: `<service>.${PUBLIC_DOMAIN}`
- No private data (domains, IPs, keys) in committed files - use GitHub Secrets
- Environment variables flow: GitHub Secret -> Ansible `-e` flag -> `env.j2` template -> `.env` file -> Docker Compose
