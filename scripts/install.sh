#!/usr/bin/env bash
# Installs the translator popup onto a machine already running
# end-4/dots-hyprland (ii). Safe to re-run — it just overwrites the
# installed copies with what's in this repo checkout.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QS_DIR="$HOME/.config/quickshell/translator"
VENV_DIR="$HOME/.local/share/translator-stt-venv"

echo "==> Checking system dependencies"
missing=0
for bin in pw-record wtype wl-copy hyprctl python3 qs docker; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "  MISSING: $bin"
        missing=1
    fi
done
if [ "$missing" = 1 ]; then
    echo "  -> install the missing binaries above before continuing (docker is only needed for the LibreTranslate fallback, see docs/LIBRETRANSLATE_SETUP.md)"
fi

echo "==> Checking for the ii-generated color palette"
COLORS_JSON="$HOME/.local/state/quickshell/user/generated/colors.json"
if [ ! -f "$COLORS_JSON" ]; then
    echo "  WARNING: $COLORS_JSON not found."
    echo "  This popup reads ii's live matugen color palette from that path."
    echo "  If your ii install generates it somewhere else, edit qs/Colors.qml"
    echo "  (search for 'colorsPath') before continuing."
fi

echo "==> Installing Quickshell config to $QS_DIR"
mkdir -p "$QS_DIR"
cp "$REPO_DIR"/qs/*.qml "$QS_DIR"/
cp "$REPO_DIR"/stt/stt_daemon.py "$QS_DIR"/

echo "==> Setting up STT Python venv at $VENV_DIR"
python3 -m venv "$VENV_DIR"
"$VENV_DIR"/bin/pip install --upgrade pip --quiet
"$VENV_DIR"/bin/pip install -r "$REPO_DIR"/stt/requirements.txt

echo "==> Hardware Acceleration & GPU Detection"
HAS_NVIDIA=0
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    HAS_NVIDIA=1
elif lspci 2>/dev/null | grep -iq 'nvidia'; then
    HAS_NVIDIA=1
fi

HAS_AMD=0
if lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -iq 'amd\|radeon'; then
    HAS_AMD=1
fi

TARGET_ACCEL=""
if [ -n "${ACCEL:-}" ]; then
    TARGET_ACCEL="$ACCEL"
elif [ -t 0 ] && [ "$HAS_NVIDIA" -eq 1 ]; then
    GPU_NAME=$(command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "NVIDIA GPU")
    echo "  [+] $GPU_NAME detected!"
    read -rp "  Enable NVIDIA CUDA GPU acceleration? (faster STT & AI polish) [Y/n]: " ans
    if [[ "$ans" =~ ^[Nn] ]]; then
        TARGET_ACCEL="cpu"
    else
        TARGET_ACCEL="cuda"
    fi
elif [ "$HAS_NVIDIA" -eq 1 ]; then
    # Non-interactive default when NVIDIA is present
    TARGET_ACCEL="cuda"
elif [ "$HAS_AMD" -eq 1 ]; then
    echo "  [i] AMD GPU detected."
    echo "      Whisper STT (CTranslate2) runs with optimized multi-threaded CPU."
    TARGET_ACCEL="cpu"
else
    echo "  [i] Using CPU inference (AVX2/int8)."
    TARGET_ACCEL="cpu"
fi

if [ "$TARGET_ACCEL" = "cuda" ]; then
    echo "  -> Installing NVIDIA CUDA 12 runtime packages (cublas, cudnn)..."
    "$VENV_DIR"/bin/pip install nvidia-cublas-cu12 nvidia-cudnn-cu12
    echo "  [OK] NVIDIA CUDA 12 runtime configured."
else
    echo "  -> Configured for CPU inference."
fi

echo "==> Setting up STT and AI Polish models"
"$REPO_DIR"/scripts/download_models.sh

cat <<'EOF'

==> Install done. Remaining manual steps:

1. Add the keybind from hypr/keybind-snippet.lua into
   ~/.config/hypr/custom/keybinds.lua (pick a combo that's actually free
   on your setup — grep your own keybinds.lua files first).

2. Then: hyprctl reload

3. Test it directly, without the keybind, in two terminals:
     qs -c translator
     qs -c translator ipc call translator toggle

4. (Optional, for translation without Google's rate limit) Set up
   LibreTranslate locally — see docs/LIBRETRANSLATE_SETUP.md.
   Without it, translation still works, just against Google's free gtx
   endpoint, which has an undocumented per-IP rate limit.

See README.md for the full architecture, protocol details, and how to
tune the STT silence threshold / keep-alive timeout for your machine.
EOF
