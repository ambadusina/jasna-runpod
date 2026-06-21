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

# =============================================================================
# AJOUTS : Upscaling (Real-ESRGAN / SeedVR2) + Interpolation (RIFE)
# La base Jasna ci-dessus est inchangee. Ces blocs sont ajoutes avant le CMD.
# =============================================================================

# --- Python 3 + pip (necessaires pour SeedVR2 et RIFE, qui sont en Python) ---
# Le binaire Jasna embarque son propre runtime ; ce Python systeme est dedie
# aux outils Python additionnels ci-dessous.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    git \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Venv dedie aux outils Python additionnels (isole du systeme).
RUN python3 -m venv /opt/aitools
ENV AITOOLS_VENV=/opt/aitools

# Torch CUDA 13 dans ce venv : requis par SeedVR2 et RIFE (inference GPU).
RUN /opt/aitools/bin/pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cu130 \
    torch torchvision

# --- 1) Real-ESRGAN (binaire ncnn-vulkan autonome, aucun Python requis) ---
RUN mkdir -p /app/upscale && cd /app/upscale && \
    wget -q https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-ubuntu.zip \
        -O resr.zip && \
    unzip -q resr.zip && rm resr.zip && \
    chmod +x realesrgan-ncnn-vulkan
COPY realesrgan_video.sh /app/upscale/realesrgan_video.sh
RUN chmod +x /app/upscale/realesrgan_video.sh

# --- 2) SeedVR2 (CLI standalone, Python) ---
# Poids NON embarques : telecharges au 1er run depuis HuggingFace (image legere).
RUN cd /app/upscale && \
    git clone --depth 1 https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git seedvr2 && \
    cd seedvr2 && \
    /opt/aitools/bin/pip install --no-cache-dir -r requirements.txt
RUN mkdir -p /app/upscale/seedvr2/models

# --- 3) Practical-RIFE (interpolation de frames, Python) ---
# IMPORTANT : on N'UTILISE PAS le requirements.txt de RIFE tel quel. Il tire des
# paquets anciens/non maintenus (ex: sk-video) qui veulent se compiler depuis
# les sources et echouent sur Python 3.12 (vieux setuptools utilisant
# pkgutil.ImpImporter, supprime en 3.12). Il epingle aussi parfois torch, ce qui
# ecraserait notre torch CUDA 13. RIFE n'a en realite besoin, en plus de
# torch/torchvision (deja la), que de numpy, opencv et tqdm. On les installe
# explicitement, en wheels modernes uniquement (aucun build from source).
RUN mkdir -p /app/interp && cd /app/interp && \
    git clone --depth 1 https://github.com/hzwer/Practical-RIFE.git rife
RUN /opt/aitools/bin/pip install --no-cache-dir \
    numpy \
    opencv-python \
    tqdm
# Poids RIFE : pas dans le repo git, a versionner dans le repo sous rife_train_log/
COPY rife_train_log/ /app/interp/rife/train_log/
COPY rife_video.sh /app/interp/rife_video.sh
RUN chmod +x /app/interp/rife_video.sh

# =============================================================================
# Fin des ajouts. Configuration runtime d'origine ci-dessous (inchangee).
# =============================================================================

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
