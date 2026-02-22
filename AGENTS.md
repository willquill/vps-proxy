# AGENTS.md - Coding Agent Guide for VPS Proxy

## Project Overview

Infrastructure-as-code repository deploying a VPS with Docker Compose services behind a
Traefik reverse proxy. Provisioned via Ansible and GitHub Actions. No application source
code — primary languages are YAML (Ansible, Docker Compose, GitHub Actions, Traefik),
HCL (OpenTofu/Terraform), Jinja2 (templates), and Bash (scripts).

## Build / Lint / Test Commands

### Linting

```bash
# YAML lint (all YAML files)
yamllint -c .yamllint.yml .

# Ansible lint (all Ansible files)
ansible-lint

# Markdown lint
markdownlint '**/*.md'

# OpenTofu format check
tofu fmt -check -recursive opentofu/
tofu fmt -check -recursive tfstate/

# OpenTofu validate (requires init first)
cd opentofu && tofu init -backend=false && tofu validate
cd tfstate && tofu init -backend=false && tofu validate
```

### Testing

```bash
# Docker Compose validation (from repo root after moving compose file)
docker compose -f ansible/roles/deploy/files/docker-compose.yml config

# Molecule test for a single Ansible role (run from the role directory)
# Requires: pip install ansible molecule molecule-docker
# The shared molecule config must be copied into the role first:
cp -r ansible/molecule ansible/roles/<role_name>/
cd ansible/roles/<role_name>
molecule test --scenario-name debian-13

# Molecule test for specific roles (tested in CI):
#   update, wireguard, docker, traefik, deploy
```

### Security Scanning (CI only)

```bash
# Gitleaks - secret scanning (runs in CI via .github/actions/security)
gitleaks detect --source . --verbose

# Checkov/tfsec - IaC security scanning
checkov -d opentofu/
checkov -d tfstate/
```

### Deployment (CI only, never run locally)

```bash
# Full deploy (done by .github/workflows/deploy.yml)
ansible-playbook ansible/main.yml -e "var1=val1" ...

# System update only
ansible-playbook ansible/main.yml --tags update
```

## Code Style Guidelines

### YAML

- **Document start**: Always begin files with `---`
- **Indentation**: 2 spaces, no tabs; sequences are indented
- **Line length**: 120 characters max (warning, not error)
- **Truthy values**: Use `true`/`false` (lowercase); `yes`/`no` also accepted
- **Document end marker**: Not required

### Ansible

- **Module names**: Always use Fully Qualified Collection Names (FQCNs)
  - `ansible.builtin.apt` not `apt`
  - `ansible.posix.sysctl` not `sysctl`
  - `community.general.ufw` not `ufw`
- **Task names**: Descriptive, sentence-case (e.g., "Ensure Docker GPG key is present")
- **Variable naming**: `snake_case`; prefix registered variables with role name
  (e.g., `wireguard_server_ip`, `deploy_backup_result`)
- **Sensitive data**: Use `no_log: true` on tasks handling secrets
- **Conditionals**: Use list format for multiple `when:` conditions
- **Error handling**: Use `failed_when: false` for optional operations;
  `ignore_errors: true` only for debug/diagnostic tasks
- **Handlers**: Named with capitalized verbs ("Restart WireGuard", "Reload systemd")
- **Play names**: Use visual separator prefix: `━━━━━━ PLAY NAME ━━━━━━`
- **Playbook structure**: One play per role, each with a unique tag, `become: true`
  at play level, role included via `ansible.builtin.include_role`

### Docker Compose

- **YAML anchors**: Define reusable blocks with `x-` prefix at top of file
  (`x-common`, `x-proxy-labels`, `x-security`, `x-user`, `x-networks-proxy`, `x-environment`)
- **Labels**: Use `<<: *proxy-labels` merge key, then add service-specific Traefik labels
- **Container names**: Must match the service name
- **Required settings** (via anchors or direct):
  - `restart: unless-stopped`
  - `pull_policy: always`
  - `security_opt: [no-new-privileges:true]`
- **Environment variables**: Pass by name only (not key=value) when sourced from `.env`
- **Networks**: Use `proxy` (external) for Traefik-routed services; create internal
  networks for database connections (e.g., `gatus`, `pocketid`)

### OpenTofu / Terraform (HCL)

- **Indentation**: 2 spaces
- **File organization**: `terraform {}` block at top; `locals` next; resources; outputs last
- **Variables**: Must include `description`, `type`, and `default`
- **Labels/tags**: Apply consistently to all resources

### Jinja2 Templates

- **Variable syntax**: `{{ variable_name }}` with spaces inside braces
- **Defaults**: Use `| default('')` filter
- **Section comments**: Add `# Section Name` comments at boundaries

### Shell Scripts

- **Shebang**: `#!/bin/bash`
- **Strict mode**: `set -e` or `set -euo pipefail` at top
- **Variables**: UPPERCASE for constants
- **Progress**: Use `echo` statements for user feedback

### Markdown

- **Line length**: 120 characters (tables and code blocks excluded)
- **Heading punctuation**: No trailing `.,;:!`
- **Allowed HTML**: `<br>`, `<p>`, `<pre>`, `<code>`, `<details>`, `<summary>`

## Environment Variable Flow

Secrets follow this chain — never commit private data:

```
GitHub Secret -> Ansible -e flag -> env.j2 template -> .env file -> Docker Compose
```

## Middleware Reference

| Middleware              | Use Case                                             |
|-------------------------|------------------------------------------------------|
| `public@file`           | Default: security headers + rate limiting + CrowdSec |
| `public-oidc-auth@file` | public + Pocket ID OIDC (for services without auth)  |
| `private@file`          | RFC1918 IPs only (LAN access)                        |

Do NOT stack `public-oidc-auth@file` on services with native OIDC — it will break
the service's own SSO callbacks and non-browser auth flows.

## Key Files

| File | Purpose |
|------|---------|
| `ansible/roles/deploy/files/docker-compose.yml` | All Docker services |
| `ansible/roles/deploy/templates/env.j2` | Environment variables template |
| `.github/workflows/deploy.yml` | CI/CD deployment pipeline |
| `ansible/roles/deploy/tasks/main.yml` | Ansible deploy tasks |
| `ansible/roles/traefik/files/traefik.yml` | Traefik static config |
| `ansible/roles/traefik/files/middlewares.yml` | Traefik middleware definitions |
| `ansible/roles/traefik/files/services.yml` | Traefik file provider (LAN services) |
| `ansible/roles/deploy/files/gatus/config.yml` | Gatus uptime monitoring |
| `opentofu/main.tf` | Hetzner Cloud infrastructure |

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `security.yml` | PR, push to main, daily cron | Gitleaks + Checkov scanning |
| `deploy.yml` | Push to main (after security), manual | Full Ansible deployment |
| `test-ansible.yml` | Manual only | Molecule tests per role |
| `test-docker.yml` | PR (compose changes), manual | Docker Compose validation |
| `tofu-lint-plan.yml` | PR, manual | OpenTofu fmt/validate/plan |
| `tofu-apply.yml` | Manual only | OpenTofu apply |
| `update.yml` | Manual only | System updates via Ansible |
