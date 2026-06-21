#!/bin/bash
# rife_video.sh — interpolation de frames via Practical-RIFE, vers un FPS cible.
#
# Usage : rife_video.sh <input.mp4> <output.mp4> <fps_cible> <dedup 0|1>
#
# Pourquoi un wrapper : l'interface de Practical-RIFE (inference_video.py) varie
# selon les versions (--multi vs --fps, nom de sortie auto, dossier de modele).
# Ce script fige une invocation connue et gere proprement :
#   - le FPS cible (--fps sur les modeles 4.x recents) ;
#   - la preservation de l'audio d'origine ;
#   - l'option de dé-duplication (animation 2D uniquement).
#
# Prerequis dans l'image :
#   - Practical-RIFE clone dans /app/interp/rife (avec train_log/ + flownet.pkl)
#   - ffmpeg / ffprobe
#   - PyTorch (CUDA) installe pour RIFE

set -euo pipefail

IN="$1"
OUT="$2"
FPS="${3:-60}"
DEDUP="${4:-0}"

RIFE_DIR=/app/interp/rife
TMP=$(mktemp -d /workspace/rife_tmp.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Practical-RIFE ecrit sa sortie a cote de l'entree ou dans un chemin impose
# selon la version. On travaille dans un dossier temporaire pour controler le
# nom de sortie, puis on remuxe l'audio d'origine.
RIFE_OUT="$TMP/interp.mp4"

EXTRA=""
if [ "$DEDUP" = "1" ]; then
    # Dé-dup activee (animation 2D) : selon la version, le flag peut differer.
    # Practical-RIFE recents : --remove_dup ; sinon ce flag est ignore.
    EXTRA="--remove_dup"
fi

echo "[rife] interpolation vers ${FPS}fps..."
cd "$RIFE_DIR"
# --fps : FPS cible (modeles 4.x). --video : entree. --output : sortie imposee.
python3 inference_video.py \
    --video "$IN" \
    --output "$RIFE_OUT" \
    --fps "$FPS" \
    $EXTRA

# Si la version utilisee n'a pas pris en compte --output, on tente de retrouver
# le fichier genere (heuristique : le mp4 le plus recent du dossier de travail).
if [ ! -f "$RIFE_OUT" ]; then
    CAND=$(ls -t "$RIFE_DIR"/*.mp4 2>/dev/null | head -n1 || true)
    if [ -n "${CAND:-}" ]; then
        mv "$CAND" "$RIFE_OUT"
    else
        echo "[rife] ERREUR : sortie RIFE introuvable." >&2
        exit 1
    fi
fi

echo "[rife] remux audio d'origine..."
# RIFE ne conserve pas toujours l'audio : on le reprend depuis la source.
ffmpeg -y -i "$RIFE_OUT" -i "$IN" \
    -map 0:v:0 -map 1:a:0? \
    -c:v copy -c:a copy -shortest "$OUT"

echo "[rife] termine : $OUT"
