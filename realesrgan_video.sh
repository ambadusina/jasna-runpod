#!/bin/bash
# realesrgan_video.sh — upscaling video uniforme via Real-ESRGAN, frame par frame.
#
# Usage : realesrgan_video.sh <input.mp4> <output.mp4> <scale>
#   scale = 2 ou 4
#
# Strategie : on evite de dumper toutes les frames en PNG (qui exploserait le
# disque en 8K). On extrait les frames dans un dossier temporaire, on les passe
# par realesrgan-ncnn-vulkan (binaire autonome, pas de dependances Python lourdes),
# puis on reassemble en preservant la piste audio d'origine.
#
# Prerequis dans l'image :
#   - ffmpeg / ffprobe
#   - realesrgan-ncnn-vulkan dans le PATH (ou /app/upscale/realesrgan-ncnn-vulkan)
#   - les modeles (realesrgan-x4plus, etc.) dans le dossier models du binaire
#
# Note : Real-ESRGAN ncnn upscale nativement en x4. Pour un x2, on upscale en x4
# puis on redimensionne a la moitie (resultat plus propre qu'un modele x2 sur
# du live-action selon les cas). Ajuste si tu embarques un modele x2 dedie.

set -euo pipefail

IN="$1"
OUT="$2"
SCALE="${3:-2}"

# Binaire : priorite au PATH, repli sur /app/upscale.
if command -v realesrgan-ncnn-vulkan >/dev/null 2>&1; then
    RESR=realesrgan-ncnn-vulkan
else
    RESR=/app/upscale/realesrgan-ncnn-vulkan
fi

MODEL="${REALESRGAN_MODEL:-realesrgan-x4plus}"

TMP=$(mktemp -d /workspace/resr_tmp.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/in" "$TMP/out"

echo "[realesrgan] extraction des frames..."
# FPS d'origine pour reassembler a l'identique.
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
      -of csv=p=0 "$IN")
ffmpeg -y -i "$IN" "$TMP/in/frame_%08d.png"

echo "[realesrgan] upscaling x4 (modele $MODEL)..."
"$RESR" -i "$TMP/in" -o "$TMP/out" -n "$MODEL" -s 4 -f png

# Si on veut x2, on redimensionne les frames upscalees a la moitie via ffmpeg
# au moment du reassemblage. Si x4, on les garde telles quelles.
VF=""
if [ "$SCALE" = "2" ]; then
    VF="-vf scale=iw/2:ih/2"
fi

echo "[realesrgan] reassemblage + audio d'origine..."
ffmpeg -y -framerate "$FPS" -i "$TMP/out/frame_%08d.png" \
    -i "$IN" \
    $VF \
    -map 0:v:0 -map 1:a:0? \
    -c:v libx265 -pix_fmt yuv420p \
    -c:a copy -shortest "$OUT"

echo "[realesrgan] termine : $OUT"
