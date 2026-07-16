#!/bin/bash
# 在新机阿里云 Workbench（网页终端）里整段粘贴执行，执行完回消息「好了」
set -euo pipefail

mkdir -p /root/.ssh
chmod 700 /root/.ssh
PUB='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAy0wAkHrYo5ajKY2VdET+ml2/hZ2HeMRvlP8BnTwbfv ninewood-migrate@luojianmingdeMacBook-Pro.local'
grep -qxF "$PUB" /root/.ssh/authorized_keys 2>/dev/null || echo "$PUB" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# 顺带打开密码登录（可选，方便排障）
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
grep -q '^PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd || service ssh restart

echo "AUTHORIZED_KEYS_OK"
wc -l /root/.ssh/authorized_keys
