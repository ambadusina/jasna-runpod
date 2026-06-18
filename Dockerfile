FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip \
    ffmpeg \
    mkvtoolnix \
    xvfb \
    x11vnc \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    novnc \
    websockify \
    supervisor \
    net-tools \
    procps \
    nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app && \
    wget -q "https://github.com/Kruk2/jasna/releases/download/v0.7.2/jasna-linux.zip" \
    -O /tmp/jasna.zip && \
    unzip /tmp/jasna.zip -d /app && \
    rm /tmp/jasna.zip && \
    chmod +x /app/jasna

RUN mkdir -p /workspace/model_weights /workspace/input /workspace/output

ENV VNC_PASSWORD=jasna1234
ENV DISPLAY=:1
ENV RESOLUTION=1920x1080
ENV PATH="/app:$PATH"

RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

COPY supervisord.conf /etc/supervisor/conf.d/jasna.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 6080 5900 8888

WORKDIR /workspace
CMD ["/start.sh"]
