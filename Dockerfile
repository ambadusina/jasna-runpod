# =============================================================================
# Ajouts au Dockerfile Jasna pour l'upscaling (Real-ESRGAN + SeedVR2)
# A inserer dans ton Dockerfile existant (guilegui123/jasna-runpod).
# =============================================================================

# -----------------------------------------------------------------------------
# 1) Real-ESRGAN (binaire ncnn-vulkan autonome — pas de stack Python lourde)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# 2) SeedVR2 (CLI standalone, sans ComfyUI)
# -----------------------------------------------------------------------------
# Le code est sous MIT/Apache 2.0 — compatible distribution commerciale.
# On clone l'implementation CLI standalone et on installe ses dependances.
RUN cd /app/upscale && \
    git clone --depth 1 https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git seedvr2 && \
    cd seedvr2 && \
    pip install --no-cache-dir -r requirements.txt

# Poids des modeles SeedVR2 : NON embarques dans l'image.
#
# Strategie retenue : telechargement automatique au premier run. Le CLI SeedVR2
# telecharge le modele demande (3B FP8 ou 7B FP16) et le VAE partage depuis
# HuggingFace lors du premier traitement, avec validation SHA256. L'image reste
# legere ; en contrepartie, le tout premier upscaling SeedVR2 d'un pod attend le
# telechargement (3,4 Go pour le 3B, 16,5 Go pour le 7B).
#
# Le dossier de cache doit exister et etre accessible en ecriture. Le CLI le
# remplit tout seul ; on s'assure juste qu'il est present.
RUN mkdir -p /app/upscale/seedvr2/models

# Note : si un jour tu veux figer une version precise des poids (reproductibilite
# ou eviter l'attente au 1er run), tu pourras les pre-telecharger ici depuis
# huggingface.co/numz/SeedVR2_comfyUI vers /app/upscale/seedvr2/models.
# Tailles de reference : 3B FP8 = 3,39 Go, 7B FP16 = 16,5 Go, VAE = ~0,3 Go.

# -----------------------------------------------------------------------------
# 3) Practical-RIFE (interpolation de frames, version Python)
# -----------------------------------------------------------------------------
# Licence MIT — compatible distribution commerciale. Version Python choisie
# pour le support du FPS cible (--fps) permettant de viser 60fps pile.
RUN mkdir -p /app/interp && cd /app/interp && \
    git clone --depth 1 https://github.com/hzwer/Practical-RIFE.git rife && \
    cd rife && \
    pip install --no-cache-dir -r requirements.txt

# Poids du modele RIFE : Practical-RIFE attend les .py et flownet.pkl dans
# train_log/. Les poids ne sont PAS dans le repo git (liens Google Drive dans
# le README). Deux options :
#   (a) Telecharger le modele recommande (4.25 par defaut) et le placer dans
#       /app/interp/rife/train_log/ au build. Adapte l'URL/le mirror que tu
#       utilises (les liens officiels sont Google Drive / Baidu).
#   (b) Le copier depuis ton contexte de build s'il est versionne ailleurs :
#
# COPY rife_train_log/ /app/interp/rife/train_log/
#
# Sans ces poids, RIFE ne demarrera pas. C'est le seul element non automatisable
# proprement via un simple git clone (poids hors repo).

# Le wrapper qui insule des variations d'interface entre versions de RIFE.
COPY rife_video.sh /app/interp/rife_video.sh
RUN chmod +x /app/interp/rife_video.sh

# -----------------------------------------------------------------------------
# Notes importantes
# -----------------------------------------------------------------------------
# - SeedVR2 attend PyTorch 2.4+ avec CUDA. Ton image est deja en CUDA 13 ; verifie
#   la compatibilite de la version torch installee par requirements.txt (au besoin,
#   epingle torch a une version compatible CUDA 13 AVANT ce bloc).
# - flash-attn est OPTIONNEL (~10% de gain). Ne l'installe que si le build le
#   supporte ; sinon SeedVR2 retombe sur l'attention PyTorch standard.
# - Espace disque du pod : l'upscaling 8K via Real-ESRGAN dumpe des frames PNG.
#   Prevois un containerDiskInGb genereux (l'app le configure deja, ajuste si
#   tu traites de longues videos 8K).
# - IMPORTANT (pods ephemeres) : les poids SeedVR2 n'etant pas dans l'image, ils
#   se re-telechargent a CHAQUE nouveau pod (le cache disparait avec le pod).
#   Pour du SeedVR2 frequent, ce re-telechargement (3,4 a 16,5 Go) s'ajoute au
#   demarrage. Si ca devient genant, deux pistes : (1) embarquer le 3B FP8 dans
#   l'image, ou (2) mettre les poids sur ton stockage R2 et les tirer au demarrage
#   (datacenter -> datacenter, plus rapide que HuggingFace).
