#!/bin/sh
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
USER_NAME="${USER_NAME:-demo}"

SSH_DIR="/etc/ssh"
PRINCIPALS_DIR="/etc/ssh/auth_principals"
USER_HOME="/home/$USER_NAME"

addgroup -g "$PGID" -S "$USER_NAME" 2>/dev/null || true
adduser -u "$PUID" -G "$USER_NAME" -D -h "$USER_HOME" -s /bin/sh "$USER_NAME" 2>/dev/null || true
sed -i "s|^$USER_NAME:!|$USER_NAME:*|" /etc/shadow 2>/dev/null || true

mkdir -p "$USER_HOME/.ssh"
chown "$USER_NAME:$USER_NAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"

if [ -f /mnt/authorized_keys/authorized_keys ]; then
    cp /mnt/authorized_keys/authorized_keys "$USER_HOME/.ssh/authorized_keys"
    chown "$USER_NAME:$USER_NAME" "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
fi

mkdir -p "$PRINCIPALS_DIR"
if [ -d /mnt/principals ]; then
    for f in /mnt/principals/*; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        cp "$f" "$PRINCIPALS_DIR/$name"
    done
fi

for keytype in ed25519 rsa; do
    if [ ! -f "$SSH_DIR/ssh_host_${keytype}_key" ]; then
        ssh-keygen -t "$keytype" -N "" -f "$SSH_DIR/ssh_host_${keytype}_key" >/dev/null 2>&1
    fi
done

if [ -f /mnt/sshd-config/sshd_config ]; then
    cp /mnt/sshd-config/sshd_config "$SSH_DIR/sshd_config"
fi

chmod 600 "$SSH_DIR/ssh_host_"*_key 2>/dev/null || true

mkdir -p /run/sshd

echo "==> Starting sshd on port 2222 for user $USER_NAME"
exec /usr/sbin/sshd -D -e "$@"
