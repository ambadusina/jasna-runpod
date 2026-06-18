FROM nvidia/cuda:13.0.0-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris

RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update && apt-get install -y --no-install-recommends \
    python3.13 \
    python3.13-dev \
    python3.13-venv \
    python3-pip \
    build-essential \
    cmake \
    ninja-build \
    git \
    curl \
    wget \
    pkg-config \
    ffmpeg \
    mkvtoolnix \
    xvfb \
    x11vnc \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    novnc \
    websockify \
    python3-tk \
    tk-dev \
    supervisor \
    net-tools \
    procps \
    nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:/root/.local/bin:$PATH"

RUN uv venv /opt/venv --python python3.13
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build

RUN git clone https://codeberg.org/Kruk2/vali.git && \
    cd vali && \
    uv pip install . --no-build-isolation

RUN git clone https://codeberg.org/Kruk2/PyNvVideoCodec.git && \
    cd PyNvVideoCodec && \
    uv pip install . --no-build-isolation

WORKDIR /app

RUN git clone https://github.com/Kruk2/jasna.git .

RUN uv pip install \
    "torch==2.10.0+cu130" \
    "torchvision==0.25.0+cu130" \
    --index-url https://download.pytorch.org/whl/cu130

RUN uv pip install \
    "tensorrt==10.14.1.48.post1" \
    "torch-tensorrt==2.10.0"

RUN uv pip install -e . --no-build-isolation

RUN mkdir -p /workspace/model_weights /workspace/input /workspace/output

ENV VNC_PASSWORD=jasna1234
ENV DISPLAY=:1
ENV RESOLUTION=1920x1080

RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

COPY supervisord.conf /etc/supervisor/conf.d/jasna.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 6080 5900 8888

WORKDIR /workspace
CMD ["/start.sh"]
