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
    git \
    build-essential \
    python3-venv \
    python3-pip \
    python3-dev \
    python3-tk \
    libsndfile1 \
    libsndfile1-dev \
    portaudio19-dev \
    libwebkit2gtk-4.1-0 \
    libgtk-3-0 \
    gir1.2-webkit2-4.1 \
    gir1.2-gtk-3.0 \
    libgirepository1.0-dev \
    libcairo2-dev \
    pkg-config \
    gobject-introspection \
    libc++1 \
    libc++abi1 \
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

# +++ JupyterLab dans un venv isole (port 8888) +++
RUN python3 -m venv /opt/jupyter-venv && \
    /opt/jupyter-venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/jupyter-venv/bin/pip install --no-cache-dir jupyterlab && \
    mkdir -p /workspace/notebooks

# +++ WhisperJAV dans un venv isole (PyTorch cu128, extras cli+gui+translate) +++
# PyTorch DOIT etre installe en premier via --index-url pour verrouiller la version GPU.
# install.py --cuda128 detecte le GPU et gere l'ordre d'installation.
# pygobject<3.52 : backend GTK3 pour pywebview (GUI). 3.56+ exige girepository-2.0 (GTK4).
# soundfile/librosa/... : deps audio importees au boot, non posees par install.py.
RUN git clone https://github.com/meizhong986/whisperjav.git /opt/whisperjav && \
    python3 -m venv /opt/whisperjav-venv && \
    /opt/whisperjav-venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/whisperjav-venv/bin/pip install --no-cache-dir uv && \
    /opt/whisperjav-venv/bin/pip install --no-cache-dir \
        torch torchaudio --index-url https://download.pytorch.org/whl/cu128 && \
    cd /opt/whisperjav && \
    /opt/whisperjav-venv/bin/python install.py --cuda128 --skip-preflight && \
    /opt/whisperjav-venv/bin/pip install --no-cache-dir -e ".[gui]" && \
    /opt/whisperjav-venv/bin/pip install --no-cache-dir "pygobject<3.52" pycairo && \
    /opt/whisperjav-venv/bin/pip install --no-cache-dir soundfile librosa numba audioread resampy

# +++ Lanceur GUI + icone bureau XFCE (lancement manuel, pas au boot) +++
# Pas de volume persistant : les modeles se retelechargent a chaque nouveau pod.
RUN printf '#!/bin/bash\nexport MPLBACKEND=Agg\nsource /opt/whisperjav-venv/bin/activate\ncd /workspace\nexec whisperjav-gui\n' \
    > /usr/local/bin/whisperjav-gui-launch && \
    chmod +x /usr/local/bin/whisperjav-gui-launch && \
    mkdir -p /root/Desktop && \
    printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=WhisperJAV\nComment=Generateur de sous-titres ASR\nExec=/usr/local/bin/whisperjav-gui-launch\nTerminal=true\nCategories=AudioVideo;\n' \
    > /root/Desktop/WhisperJAV.desktop && \
    chmod +x /root/Desktop/WhisperJAV.desktop

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
