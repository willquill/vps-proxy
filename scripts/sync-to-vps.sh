#!/bin/bash
# sync-to-vps.sh - Deploy edited config files to VPS

VPS_IP="YOUR_VPS_IP"
VPS_USER="willquill"

rsync -avz -e "ssh -p 2222" \
  ansible/roles/deploy/files/gatus/config.yml \
  ${VPS_USER}@${VPS_IP}:~/vps-proxy/config/gatus/
  
rsync -avz -e "ssh -p 2222" \
  ansible/roles/traefik/files/traefik.yml \
  ${VPS_USER}@${VPS_IP}:~/vps-proxy/config/traefik/

rsync -avz --delete -e "ssh -p 2222" \
  ansible/roles/traefik/files/config/ \
  ${VPS_USER}@${VPS_IP}:~/vps-proxy/config/traefik/config/

echo "✓ Config files synced to VPS"
