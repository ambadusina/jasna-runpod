#!/bin/bash
set -e

echo "============================================"
echo "  Jasna - RunPod Container Starting"
echo "============================================"

# --- SSH: injecter la clé publique RunPod ---
if [ -n "$PUBLIC_KEY" ]; then
    mkdir -p /root/.ssh
    echo "$PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
    echo "SSH public key installed"
fi

# --- VNC password ---
VNC_PASSWORD=${VNC_PASSWORD:-jasna1234}
mkdir -p /root/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" /root/.vnc/passwd
echo "VNC password set"

# --- Log directories ---
mkdir -p /var/log/supervisor

echo "Starting sshd, Xvfb, x11vnc, noVNC, XFCE via supervisor..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
