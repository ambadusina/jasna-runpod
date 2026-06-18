#!/bin/bash
set -e

echo "============================================"
echo "  Jasna - RunPod Container Starting"
echo "============================================"

if [ ! -L /app/model_weights ]; then
    rm -rf /app/model_weights
    ln -sf /workspace/model_weights /app/model_weights
    echo "✅ model_weights → /workspace/model_weights"
fi

VNC_PASSWORD=${VNC_PASSWORD:-jasna1234}
mkdir -p ~/.vnc
x11vnc -storepasswd "$VNC_PASSWORD" ~/.vnc/passwd
echo "✅ VNC password set"

echo "🚀 Starting Xvfb, VNC, noVNC, XFCE..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
