#cloud-config
users:
  # Note: This user must match your VPS_USER secret
  - name: ${name}
    groups: users, admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_authorized_key}
packages:
  - fail2ban
  - ufw
  - python3
  - python3-pip
  - python3-apt
  - aptitude
  - openssh-server
  - vim
  - tree
  - curl
  - wget
package_update: true
package_upgrade: true
write_files:
  - path: /etc/ssh/sshd_config.d/99-ssh-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      Port 2222
      PubkeyAuthentication yes
      KbdInteractiveAuthentication no
      ChallengeResponseAuthentication no
      MaxAuthTries 2
      AllowTcpForwarding no
      X11Forwarding no
      AllowAgentForwarding no
      AuthorizedKeysFile .ssh/authorized_keys
      AllowUsers ${name}
  - path: /etc/systemd/system/ssh.socket.d/listen.conf
    content: |
      [Socket]
      ListenStream=
      ListenStream=2222
ufw:
  enabled: true
  allow:
    - "22"
    - "2222"
    - "80"
    - "443"
    - "636"
    - "51820"
runcmd:
  - printf "[sshd]\nenabled = true\nport = ssh, 2222\nbanaction = iptables-multiport" > /etc/fail2ban/jail.local
  - systemctl enable fail2ban
  - systemctl enable ssh
  - systemctl start ssh
  - reboot
