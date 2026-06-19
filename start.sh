#!/bin/bash
set -e

echo "============================================"
echo "  Jasna - RunPod Container Starting"
echo "============================================"

# --- VNC password ---
VNC_PASSWORD=${VNC_PASSWORD:-jasna1234}
mkdir -p /root/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" /root/.vnc/passwd
echo "VNC password set"

# --- Log directories ---
mkdir -p /var/log/supervisor

echo "Starting Xvfb, x11vnc, noVNC, XFCE via supervisor..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
