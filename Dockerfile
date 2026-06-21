FROM nvidia/cuda:13.0.0-cudnn-devel-ubuntu24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget \
    openssh-server \
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
# Cles d'hote SSH generees au build (sshd ne demarre pas sans).
RUN ssh-keygen -A && mkdir -p /run/sshd
RUN wget -q "https://github.com/Kruk2/jasna/releases/download/v0.7.2/jasna-linux.tar.zst.part-aa" -O /tmp/part-aa && \
    wget -q "https://github.com/Kruk2/jasna/releases/download/v0.7.2/jasna-linux.tar.zst.part-ab" -O /tmp/part-ab && \
    wget -q "https://github.com/Kruk2/jasna/releases/download/v0.7.2/jasna-linux.tar.zst.part-ac" -O /tmp/part-ac && \
    cat /tmp/part-aa /tmp/part-ab /tmp/part-ac > /tmp/jasna.tar.zst && \
    rm /tmp/part-aa /tmp/part-ab /tmp/part-ac && \
    mkdir -p /app && \
    tar -I zstd -xf /tmp/jasna.tar.zst -C /app && \
    rm /tmp/jasna.tar.zst
RUN mkdir -p /workspace/model_weights /workspace/input /workspace/output
# Engine RF-DETR bake
RUN curl -fSL "https://github.com/ambadusina/jasna-runpod/releases/download/engine/rfdetr-v5.bs4.fp16.linux.engine" \
    -o /app/model_weights/rfdetr-v5.bs4.fp16.linux.engine
# Engine unet-4x bake
RUN curl -fSL "https://github.com/ambadusina/jasna-runpod/releases/download/engine/unet-4x.fp16.linux.engine.enc" \
    -o /app/model_weights/unet-4x.fp16.linux.engine.enc
# Sub-engines BasicVSR++ bakes
RUN curl -fSL "https://github.com/ambadusina/jasna-runpod/releases/download/engine/sub_engines.tar" \
    -o /tmp/sub_engines.tar && \
    tar -xf /tmp/sub_engines.tar -C /app/model_weights/ && \
    rm /tmp/sub_engines.tar

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
