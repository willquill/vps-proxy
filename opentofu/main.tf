locals {
  # Ensure no keys or labels have spaces
  labels = {
    for k, v in {
      "Provisioner"      = "GitHub Actions"
      "Last-Provisioned" = var.created_timestamp
      "Owner"            = var.repo_owner
      "Workflow-Actor"   = var.workflow_actor
    } : replace(k, " ", "-") => replace(v, " ", "-")
  }
}

resource "hcloud_firewall" "vps_proxy" {
  name = "vps-proxy"

  # ICMP rule
  rule {
    direction = "in"
    protocol  = "icmp"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  # TCP rules
  dynamic "rule" {
    for_each = toset(var.firewall_rules_tcp_inbound)
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }

  labels = local.labels
}

# data "cloudinit_config" "vps_proxy" {

#   gzip          = true
#   base64_encode = true

#   # Main cloud-config configuration file.
#   part {
#     filename     = "init.cfg"
#     content_type = "text/cloud-config"
#     content = templatefile(
#       "${path.module}/cloud-init.yaml.tpl",
#       {
#         name               = var.repo_owner
#         ssh_authorized_key = var.ssh_authorized_key
#       }
#     )
#   }
# }

resource "hcloud_server" "server" {
  name         = "vps-proxy"
  server_type  = "cpx11"
  image        = "debian-13"
  datacenter   = "ash-dc1"
  firewall_ids = [hcloud_firewall.vps_proxy.id]

  #user_data = data.cloudinit_config.vps_proxy.rendered
  user_data = templatefile(
    "${path.module}/cloud-init.yaml.tpl",
    {
      name               = var.repo_owner
      ssh_authorized_key = var.ssh_authorized_key
    }
  )

  labels = local.labels
}

output "server_id" {
  value = hcloud_server.server.id
}

output "server_ipv4" {
  value = hcloud_server.server.ipv4_address
}

output "server_ipv6" {
  value = hcloud_server.server.ipv6_address
}
