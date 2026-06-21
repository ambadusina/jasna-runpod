# =============================================================================
# Jasna - RunPod Docker Image
# GPU: NVIDIA RTX PRO 4500 | CUDA: 13.0 | Python: 3.13 | TensorRT: 10.14
# Access: noVNC (browser) on port 6080 | VNC on port 5900
# + Upscaling (Real-ESRGAN / SeedVR2) + Interpolation (RIFE)
# =============================================================================

FROM nvidia/cuda:13.0.0-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris

# =============================================================================
# 1. DEPENDANCES SYSTEME
# =============================================================================
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
    unzip \
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

# Verifier FFmpeg version 8 (requis par Jasna)
RUN ffmpeg -version | head -1 | grep -E "version [89]" || \
    (echo "FFmpeg version must be 8.x — check the base image" && exit 1)

# =============================================================================
# 2. PYTHON & UV
# =============================================================================
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:/root/.local/bin:$PATH"

RUN uv venv /opt/venv --python python3.13
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# =============================================================================
# 3. LIBS CUSTOM (vali + PyNvVideoCodec) — build depuis source
# =============================================================================
WORKDIR /build

RUN git clone https://codeberg.org/Kruk2/vali.git && \
    cd vali && \
    uv pip install . --no-build-isolation

RUN git clone https://codeberg.org/Kruk2/PyNvVideoCodec.git && \
    cd PyNvVideoCodec && \
    uv pip install . --no-build-isolation

# =============================================================================
# 4. JASNA
# =============================================================================
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

# =============================================================================
# 5. UPSCALING : Real-ESRGAN (binaire ncnn-vulkan autonome)
# =============================================================================
# Le binaire ncnn-vulkan ne depend pas de CUDA/PyTorch : ideal a embarquer.
# Verifie la derniere release sur github.com/xinntao/Real-ESRGAN/releases
RUN mkdir -p /app/upscale && cd /app/upscale && \
    wget -q https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-ubuntu.zip \
        -O resr.zip && \
    unzip -q resr.zip && rm resr.zip && \
    chmod +x realesrgan-ncnn-vulkan

# Le wrapper video (extraction frames -> upscale -> reassemblage + audio).
COPY realesrgan_video.sh /app/upscale/realesrgan_video.sh
RUN chmod +x /app/upscale/realesrgan_video.sh

# =============================================================================
# 6. UPSCALING : SeedVR2 (CLI standalone, sans ComfyUI)
# =============================================================================
# Code sous MIT/Apache 2.0 — compatible distribution commerciale.
RUN cd /app/upscale && \
    git clone --depth 1 https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git seedvr2 && \
    cd seedvr2 && \
    uv pip install -r requirements.txt

# Poids des modeles SeedVR2 : NON embarques. Telechargement automatique au 1er
# run depuis HuggingFace (validation SHA256). Image legere ; le 1er upscaling
# SeedVR2 d'un pod attend le telechargement (3,4 Go pour le 3B, 16,5 Go pour le
# 7B). Comme les pods sont ephemeres, ce telechargement se refait a chaque pod.
# On s'assure juste que le dossier de cache existe.
RUN mkdir -p /app/upscale/seedvr2/models

# =============================================================================
# 7. INTERPOLATION : Practical-RIFE (version Python, FPS cible)
# =============================================================================
# Licence MIT. Version Python pour le support du FPS cible (--fps -> 60fps pile).
RUN mkdir -p /app/interp && cd /app/interp && \
    git clone --depth 1 https://github.com/hzwer/Practical-RIFE.git rife && \
    cd rife && \
    uv pip install -r requirements.txt

# Poids du modele RIFE : pas dans le repo git (liens Google Drive). On les
# versionne dans le repo sous rife_train_log/ (flownet.pkl + *.py du modele)
# et on les copie dans train_log/. Voir le README du projet pour la mise en place.
COPY rife_train_log/ /app/interp/rife/train_log/

# Le wrapper qui insule des variations d'interface entre versions de RIFE.
COPY rife_video.sh /app/interp/rife_video.sh
RUN chmod +x /app/interp/rife_video.sh

# =============================================================================
# 8. CONFIGURATION RUNTIME (VNC / dossiers de travail)
# =============================================================================
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
