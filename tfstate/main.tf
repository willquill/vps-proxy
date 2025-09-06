terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.43.0, < 6"
    }
  }
  # Uses OpenTofu
  required_version = ">= 1.10, < 1.11"
}

provider "aws" {
  region = "us-east-2"
}

module "bootstrap" {
  source        = "trussworks/bootstrap/aws"
  version       = "~> 7.0"
  region        = "us-east-2"
  account_alias = "willquill-vps-proxy"
}
