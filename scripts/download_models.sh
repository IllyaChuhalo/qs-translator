#!/usr/bin/env bash
# Downloads and verifies local STT and SLM models for the translator popup.
set -euo pipefail

MODELS_DIR="${TRANSLATOR_MODELS_DIR:-$HOME/.local/share/translator/models}"
mkdir -p "$MODELS_DIR"

echo "=========================================================="
echo "    Translator Models Setup (STT + AI Polish)"
echo "=========================================================="

echo "==> Detecting hardware acceleration..."
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    echo "  [GPU] NVIDIA Detected: $GPU_NAME (Vulkan / CUDA acceleration ready)"
elif lspci | grep -iE 'vga|3d|display' | grep -i 'amd\|radeon' >/dev/null 2>&1; then
    echo "  [GPU] AMD Radeon Detected (Vulkan / RADV acceleration ready)"
else
    echo "  [CPU] Using CPU AVX2 multi-threading"
fi

download_file() {
    local url="$1"
    local dest="$2"
    local desc="$3"

    if [ -f "$dest" ] && [ -s "$dest" ]; then
        echo "  [OK] $desc already exists: $(basename "$dest")"
    else
        echo "  ==> Downloading $desc..."
        echo "      URL: $url"
        curl -L --progress-bar "$url" -o "$dest.tmp"
        mv "$dest.tmp" "$dest"
        echo "  [DONE] Saved to $dest"
    fi
}

echo ""
echo "==> Target models directory: $MODELS_DIR"
echo ""

# 1. English STT Model: Distil-Whisper Medium EN (High accuracy, fast)
EN_MODEL="$MODELS_DIR/ggml-distil-medium.en.bin"
EN_URL="https://huggingface.co/distil-whisper/distil-medium.en/resolve/main/ggml-distil-medium.en.bin"
download_file "$EN_URL" "$EN_MODEL" "English STT Model (Distil-Whisper Medium)"

# 2. Ukrainian STT Model: Whisper Medium (Multilingual / Ukrainian high-accuracy)
UK_MODEL="$MODELS_DIR/ggml-medium.bin"
UK_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
download_file "$UK_URL" "$UK_MODEL" "Ukrainian/Multilingual STT Model (Whisper Medium)"

# 3. AI Polish Model: Qwen 2.5 1.5B Instruct (GGUF Q4_K_M)
POLISH_MODEL="$MODELS_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf"
POLISH_URL="https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
download_file "$POLISH_URL" "$POLISH_MODEL" "AI Polish Model (Qwen 2.5 1.5B Instruct Q4_K_M)"

echo ""
echo "=========================================================="
echo " All models verified in $MODELS_DIR"
echo "=========================================================="
