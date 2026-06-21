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
else
    echo "ATTENTION: PUBLIC_KEY non definie - le SSH refusera la connexion."
    echo "  -> Enregistre ta cle publique dans RunPod > Settings > SSH Public Keys."
fi
# --- SSH: prerequis sshd (repertoire runtime + cles d'hote) ---
mkdir -p /run/sshd
# Genere les cles d'hote si absentes (filet de securite ; normalement faites au build)
ssh-keygen -A
echo "sshd prerequisites ready"
# --- VNC password ---
VNC_PASSWORD=${VNC_PASSWORD:-jasna1234}
mkdir -p /root/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" /root/.vnc/passwd
echo "VNC password set"
# --- Log directories ---
mkdir -p /var/log/supervisor
echo "Starting sshd, Xvfb, x11vnc, noVNC, XFCE via supervisor..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
