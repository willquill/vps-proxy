#!/bin/bash
# sync-from-vps.sh - Pull config changes from VPS

VPS_IP="YOUR_VPS_IP"
VPS_USER="willquill"

rsync -avz -e "ssh -p 2222" \
  ${VPS_USER}@${VPS_IP}:~/vps-proxy/config/gatus/config.yml \
  ansible/roles/deploy/files/gatus/

rsync -avz -e "ssh -p 2222" \
  ${VPS_USER}@${VPS_IP}:~/vps-proxy/config/traefik/traefik.yml \
  ansible/roles/traefik/files/

rsync -avz --delete -e "ssh -p 2222" \
  ${VPS_USER}@${VPS_IP}:~/vps-proxy/config/traefik/config/ \
  ansible/roles/traefik/files/config/

git diff ansible/roles/
echo "✓ Config files synced from VPS. Review with 'git diff ansible/roles/'"
