terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.56"
    }
  }
  required_version = ">= 1.10, < 1.11"

  backend "s3" {
    bucket         = "willquill-vps-proxy-tf-state-us-east-2"
    key            = "tfstate/willquill/vps-proxy/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

# Configure the Hetzner Cloud provider
provider "hcloud" {
  # Don't need this when setting HCLOUD_TOKEN envvar
  # token = var.hcloud_token
}
