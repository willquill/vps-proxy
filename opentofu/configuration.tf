# Cloud Init variables
# Values supplied by GitHub Actions workflow envars:
# env:
#   TF_VAR_repo_owner: ${{ github.repository_owner }}
#   TF_VAR_workflow_actor: ${{ github.actor }}
#   TF_VAR_ssh_authorized_key: ${{ secrets.VPS_PROXY_KEY }}
variable "repo_owner" {
  description = "GitHub repository owner"
  type        = string
}

variable "workflow_actor" {
  description = "GitHub workflow actor"
  type        = string
}

variable "ssh_authorized_key" {
  description = "SSH public key for cloud-init"
  type        = string
}

# Hetzner Cloud Firewall variable
variable "firewall_rules_tcp_inbound" {
  description = "Inbound firewall rules for TCP"
  type        = list(string)
  default = [
    "2222",  # Host SSH
    "51820", # Host WireGuard
    "80",    # Traefik HTTP redirect to HTTPS
    "443",   # Traefik HTTPS
    "22",    # Traefik SSH to git server
    "636",   # Traefik LDAPS to IDP
  ]
}

variable "owner" {
  description = "Resource owner"
  type        = string
  default     = null
}