# Tell terraform to use the provider and select a version.
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.52"
    }
  }
  required_version = ">= 1.10, < 1.11"
}

# Configure the Hetzner Cloud provider
provider "hcloud" {
  # Don't need this when setting HCLOUD_TOKEN envvar
  token = var.hcloud_token
}
