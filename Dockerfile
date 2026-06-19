FROM nvidia/cuda:13.0.0-cudnn-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget \
    ffmpeg \
    mkvtoolnix \
    xvfb \
    x11vnc \
    x11-utils \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    novnc \
    websockify \
    supervisor \
    net-tools \
    netcat-openbsd \
    procps \
    nano \
    zstd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/Kruk2/jasna/releases/download/v0.7.2/jasna-linux.tar.zst.part-aa" -O /tmp/part-aa && \
    wget -q "https://github.com/Kruk2/jasna/releases/download/v0.7.2/jasna-linux.tar.zst.part-ab" -O /tmp/part-ab && \
    wget -q "https://github.com/Kruk2/jasna/releases/download/v0.7.2/jasna-linux.tar.zst.part-ac" -O /tmp/part-ac && \
    cat /tmp/part-aa /tmp/part-ab /tmp/part-ac > /tmp/jasna.tar.zst && \
    rm /tmp/part-aa /tmp/part-ab /tmp/part-ac && \
    mkdir -p /app && \
    tar -I zstd -xf /tmp/jasna.tar.zst -C /app && \
    rm /tmp/jasna.tar.zst

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
CMD ["/start.sh"]NV DISPLAY=:1
ENV RESOLUTION=1920x1080
ENV PATH="/app:$PATH"

RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

COPY supervisord.conf /etc/supervisor/conf.d/jasna.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 6080 5900 8888

WORKDIR /workspace
CMD ["/start.sh"]
