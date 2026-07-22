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
RUN wget -q "https://github.com/Kruk2/jasna/releases/download/v0.8.1/jasna-linux-nvidia-0.8.1.tar.zst.part000" -O /tmp/part-aa && \
    wget -q "https://github.com/Kruk2/jasna/releases/download/v0.8.1/jasna-linux-nvidia-0.8.1.tar.zst.part001" -O /tmp/part-ab && \
    wget -q "https://github.com/Kruk2/jasna/releases/download/v0.8.1/jasna-linux-nvidia-0.8.1.tar.zst.part002" -O /tmp/part-ac && \
    cat /tmp/part-aa /tmp/part-ab /tmp/part-ac > /tmp/jasna.tar.zst && \
    rm /tmp/part-aa /tmp/part-ab /tmp/part-ac && \
    mkdir -p /app && \
    tar -I zstd -xf /tmp/jasna.tar.zst -C /app && \
    rm /tmp/jasna.tar.zst

RUN mkdir -p /workspace/input /workspace/output /root/Desktop

# +++ Engines pre-compiles deposes sur le Bureau (mis de cote, pas charges par Jasna) +++
# A copier manuellement dans /app/jasna-linux-nvidia-0.8.1/model_weights une fois la
# compatibilite TensorRT confirmee.
RUN mkdir -p /root/Desktop/engines_bakes && \
    curl -fSL "https://github.com/ambadusina/jasna-runpod/releases/download/engine/rfdetr-v5.bs4.fp16.linux.engine" \
        -o /root/Desktop/engines_bakes/rfdetr-v5.bs4.fp16.linux.engine && \
    curl -fSL "https://github.com/ambadusina/jasna-runpod/releases/download/engine/unet-4x.fp16.linux.engine.enc" \
        -o /root/Desktop/engines_bakes/unet-4x.fp16.linux.engine.enc && \
    curl -fSL "https://github.com/ambadusina/jasna-runpod/releases/download/engine/sub_engines.tar" \
        -o /tmp/sub_engines.tar && \
    tar -xf /tmp/sub_engines.tar -C /root/Desktop/engines_bakes/ && \
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

# +++ ProPainter + GUI Gradio Track-Anything (usage perso, S-Lab non-commerciale) +++
# cu128 comme WhisperJAV : evite les conflits avec le CUDA 13 de Jasna.
RUN git clone https://github.com/sczhou/ProPainter.git /opt/propainter && \
    python3 -m venv /opt/propainter-venv && \
    /opt/propainter-venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/propainter-venv/bin/pip install --no-cache-dir \
        torch torchvision --index-url https://download.pytorch.org/whl/cu128 && \
    /opt/propainter-venv/bin/pip install --no-cache-dir -r /opt/propainter/requirements.txt && \
    /opt/propainter-venv/bin/pip install --no-cache-dir \
        -r /opt/propainter/web-demos/hugging_face/requirements.txt

# +++ Poids ProPainter + SAM + Cutie bakes dans l'image (~3.3 Go) +++
# La GUI et le CLI cherchent tous deux dans /opt/propainter/weights.
RUN cd /opt/propainter/weights && \
    curl -fSL -O "https://github.com/sczhou/ProPainter/releases/download/v0.1.0/ProPainter.pth" && \
    curl -fSL -O "https://github.com/sczhou/ProPainter/releases/download/v0.1.0/raft-things.pth" && \
    curl -fSL -O "https://github.com/sczhou/ProPainter/releases/download/v0.1.0/recurrent_flow_completion.pth" && \
    curl -fSL -O "https://github.com/sczhou/ProPainter/releases/download/v0.1.0/cutie-base-mega.pth" && \
    curl -fSL -O "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth"

# +++ Gradio expose sur 0.0.0.0 pour passer par le proxy RunPod (port 7860) +++
# Pas de navigateur dans l'image : la GUI s'ouvre depuis le navigateur local.
# Le grep verifie que le patch a bien ete applique (echec du build sinon).
RUN sed -i 's/^iface\.launch(debug=True)$/iface.launch(debug=True, server_name="0.0.0.0", server_port=7860)/' \
        /opt/propainter/web-demos/hugging_face/app.py && \
    grep -q 'server_name="0.0.0.0"' /opt/propainter/web-demos/hugging_face/app.py

# +++ faster-propainter : variante rapide pour watermarks STATIQUES uniquement +++
# Principe : crop de la zone du watermark + FastFlowNet (ptlflow) au lieu de RAFT.
# Masque = une seule image PNG fixe. Pas de GUI, config dans globals.py.
RUN git clone https://github.com/halfzm/faster-propainter.git /opt/faster-propainter && \
    /opt/propainter-venv/bin/pip install --no-cache-dir ptlflow && \
    ln -s /opt/propainter/weights /opt/faster-propainter/weights

# Pre-telechargement du checkpoint FastFlowNet (sinon fetch au 1er lancement).
RUN /opt/propainter-venv/bin/python -c \
    "import ptlflow; ptlflow.get_model('fastflownet', pretrained_ckpt='things')" || \
    echo "AVERTISSEMENT: pre-fetch fastflownet echoue, sera telecharge au 1er lancement"

# +++ FaceFusion 3.7.1 (licence OpenRAIL-AS, usage perso : anonymisation) +++
# Venv isole : onnxruntime-gpu, independant des venvs Jasna/WhisperJAV/ProPainter.
# L'argument onnxruntime est POSITIONNEL (pas --onnxruntime).
RUN git clone https://github.com/facefusion/facefusion.git /opt/facefusion && \
    python3 -m venv /opt/facefusion-venv && \
    /opt/facefusion-venv/bin/pip install --no-cache-dir --upgrade pip && \
    cd /opt/facefusion && \
    /opt/facefusion-venv/bin/python install.py cuda --skip-conda

# +++ Gradio expose sur 0.0.0.0, port 7861 (7860 pris par ProPainter) +++
RUN sed -i "s/ui\.launch(favicon_path = 'facefusion\.ico', inbrowser = state_manager\.get_item('open_browser'))/ui.launch(favicon_path = 'facefusion.ico', inbrowser = False, server_name = '0.0.0.0', server_port = 7861)/" \
        /opt/facefusion/facefusion/uis/layouts/default.py && \
    grep -q "server_name = '0.0.0.0'" /opt/facefusion/facefusion/uis/layouts/default.py

# +++ Lanceur GUI WhisperJAV + icone bureau XFCE (lancement manuel, pas au boot) +++
# Pas de volume persistant : les modeles se retelechargent a chaque nouveau pod.
RUN printf '#!/bin/bash\nexport MPLBACKEND=Agg\nsource /opt/whisperjav-venv/bin/activate\ncd /workspace\nexec whisperjav-gui\n' \
    > /usr/local/bin/whisperjav-gui-launch && \
    chmod +x /usr/local/bin/whisperjav-gui-launch && \
    printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=WhisperJAV\nComment=Generateur de sous-titres ASR\nExec=/usr/local/bin/whisperjav-gui-launch\nTerminal=true\nCategories=AudioVideo;\n' \
    > /root/Desktop/WhisperJAV.desktop && \
    chmod +x /root/Desktop/WhisperJAV.desktop

# +++ Lanceur GUI ProPainter + icone bureau XFCE +++
# La GUI doit tourner depuis son propre dossier (chemins relatifs vers ../../weights).
RUN printf '#!/bin/bash\nsource /opt/propainter-venv/bin/activate\ncd /opt/propainter/web-demos/hugging_face\necho "GUI sur le port 7860 -> ouvrir via le proxy RunPod"\nexec python app.py\n' \
    > /usr/local/bin/propainter-gui-launch && \
    chmod +x /usr/local/bin/propainter-gui-launch && \
    printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=ProPainter\nComment=Inpainting video (Track-Anything)\nExec=/usr/local/bin/propainter-gui-launch\nTerminal=true\nCategories=AudioVideo;\n' \
    > /root/Desktop/ProPainter.desktop && \
    chmod +x /root/Desktop/ProPainter.desktop

# +++ Lanceur faster-propainter (shell, config manuelle dans globals.py) +++
RUN printf '#!/bin/bash\nsource /opt/propainter-venv/bin/activate\ncd /opt/faster-propainter\necho "Editez globals.py (source_path / target_path / output_path) puis: python start.py"\nexec bash\n' \
    > /usr/local/bin/faster-propainter-shell && \
    chmod +x /usr/local/bin/faster-propainter-shell && \
    printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=faster-ProPainter\nComment=Retrait watermark statique (rapide)\nExec=xfce4-terminal -e /usr/local/bin/faster-propainter-shell\nTerminal=false\nCategories=AudioVideo;\n' \
    > /root/Desktop/faster-ProPainter.desktop && \
    chmod +x /root/Desktop/faster-ProPainter.desktop

# +++ Lanceur GUI FaceFusion + icone bureau XFCE +++
RUN printf '#!/bin/bash\nsource /opt/facefusion-venv/bin/activate\ncd /opt/facefusion\necho "GUI sur le port 7861 -> ouvrir via le proxy RunPod"\nexec python facefusion.py run\n' \
    > /usr/local/bin/facefusion-gui-launch && \
    chmod +x /usr/local/bin/facefusion-gui-launch && \
    printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=FaceFusion\nComment=Anonymisation de visages\nExec=/usr/local/bin/facefusion-gui-launch\nTerminal=true\nCategories=AudioVideo;\n' \
    > /root/Desktop/FaceFusion.desktop && \
    chmod +x /root/Desktop/FaceFusion.desktop

# +++ Lanceur GUI Jasna + icone bureau XFCE (lancement manuel, pas au boot) +++
# cd dans le dossier versionne avant de lancer : Jasna resout model_weights/ en relatif.
RUN printf '#!/bin/bash\ncd /app/jasna-linux-nvidia-0.8.1\nexec ./jasna\n' \
    > /usr/local/bin/jasna-gui-launch && \
    chmod +x /usr/local/bin/jasna-gui-launch && \
    printf '[Desktop Entry]\nVersion=1.0\nType=Application\nName=Jasna\nComment=Restauration video JAV\nExec=/usr/local/bin/jasna-gui-launch\nTerminal=true\nCategories=AudioVideo;\n' \
    > /root/Desktop/Jasna.desktop && \
    chmod +x /root/Desktop/Jasna.desktop

ENV VNC_PASSWORD=jasna1234
ENV DISPLAY=:1
ENV RESOLUTION=1920x1080
ENV PATH="/app/jasna-linux-nvidia-0.8.1:$PATH"
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html
COPY supervisord.conf /etc/supervisor/conf.d/jasna.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh
EXPOSE 6080 5900 8888 7860 7861
WORKDIR /workspace
CMD ["/start.sh"]
