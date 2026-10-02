# translator — Quickshell Popup for ii / dots-hyprland

A fast, keyboard-centric popup translator (`uk` ↔ `en`) with real-time streaming voice input (STT) and local AI speech polishing (Qwen 2.5 SLM) for Hyprland and Quickshell. Visually and thematically integrated with [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) ("ii").

It runs as an independent Quickshell configuration (`qs -c translator`) — **neither a fork nor a patch of `ii` itself**, ensuring upstream `ii` updates never affect or break it.

---

## Features

- **Layer-Shell Overlay**: Floating window centered at the bottom of the screen; does not reserve screen space or shift tiled windows (`exclusiveZone: -1`).
- **Two-Way Language Tracking**: Translation direction automatically tracks Hyprland's active keyboard layout (`uk` ↔ `en`), including switching direction on the fly while typing or speaking.
- **Dual-Engine Streaming Voice Input (STT)**:
  - **Real-Time Streaming**: As you speak, partial transcriptions (`PARTIAL:`) appear directly in the text field every ~300ms using a lightweight Whisper `base` model running concurrently in the background.
  - **High-Accuracy Final Pass**: Once speech concludes (detected by trailing silence RMS VAD or a manual click), high-accuracy Whisper `medium` (on CUDA) or `small` (on CPU) finalizes the sentence with beam search (`RESULT:`).
  - **NVIDIA CUDA GPU Acceleration**: Runs natively on NVIDIA GPUs with dynamic CUDA 12 runtime loading. Transcribing 5 seconds of audio takes only **~0.7s on an RTX 3050 Laptop GPU** (~7.2x faster than CPU). Automatically falls back to optimized multi-threaded CPU AVX2 (`int8`) on systems without NVIDIA GPUs.
  - **Live Audio Visualizer**: 5-band dynamic volume visualizer animated in real time inside the mic button during recording.
- **Local AI Polish (Qwen 2.5 1.5B Instruct GGUF)**:
  - Compact local SLM running asynchronously via `llama-cpp-python`.
  - Removes conversational filler words (*ну*, *типу*, *короче* / *um*, *uh*, *like*), handles speech self-corrections, fixes recognition typos, restores missing Ukrainian apostrophes (*комп'ютер*, *зв'язок*, *пам'ять*), and formats punctuation before translation.
  - Toggled directly via the sparkles icon (`auto_awesome`) positioned inside the right side of the input field.
- **Smart Translation Backend**: Uses Google Translate (free `gtx` endpoint) first; automatically fails over to a local [LibreTranslate](https://libretranslate.com/) Docker container if Google returns a rate limit (HTTP 429).
- **Fast Action**: Pressing `Enter` copies the translation to the clipboard and automatically pastes it into the active window (`wl-copy` + `wtype`). `Escape` dismisses the popup without pasting.
- **Adaptive Material 3 Palette**: Colors and radii are read directly from `ii`'s live `matugen` color palette (`colors.json`) upon wallpaper or theme changes.

---

## Installation

All dependencies, Python virtual environment, Quickshell configs, GPU acceleration setup, and model downloads are automated in a single installer:

```bash
git clone https://github.com/IllyaChuhalo/qs-translator.git translator
cd translator
./scripts/install.sh
```

During installation, the script will:
1. Check for required system binaries (`pw-record`, `wtype`, `wl-copy`, `hyprctl`, `python3`, `qs`).
2. Copy the interface and backend scripts to `~/.config/quickshell/translator/`.
3. Create an isolated Python virtual environment at `~/.local/share/translator-stt-venv`.
4. **Detect Hardware Acceleration**: If an NVIDIA GPU is detected, it prompts to install CUDA 12 runtime packages (`nvidia-cublas-cu12`, `nvidia-cudnn-cu12`) for GPU acceleration.
5. Verify and download local models (faster-whisper and Qwen 2.5 1.5B GGUF).

---

## Hyprland Keybind Configuration

Add the shortcut binding to `~/.config/hypr/custom/keybinds.lua` (or your Hyprland keybind config):

```lua
-- Toggle translator popup (e.g., Super + T):
bind({ "SUPER" }, "T", function()
    awm.spawn("qs -c translator ipc call translator toggle")
end)
```

Reload Hyprland:
```bash
hyprctl reload
```

---

## Architecture

```
+-------------------------------------------------------------------------+
|                         Quickshell GUI (shell.qml)                      |
|  - WlrLayershell Overlay                                                |
|  - TextInput (inputField)  <---+                                        |
|  - AI Polish Icon Button       | (PARTIAL: / RESULT: / POLISHED:)       |
|  - Dynamic Matugen Theming     |                                        |
+--------------------------------+----------------------------------------+
                                 |  stdin / stdout (IPC)
                                 v
+-------------------------------------------------------------------------+
|                       STT & SLM Daemon (stt_daemon.py)                  |
|                                                                         |
|  [Hardware Layer]                                                       |
|    - NVIDIA CUDA Dynamic Preloader (ctypes CDLL)                        |
|    - Auto-detection: CUDA (float16) <---> CPU AVX2 (int8)               |
|                                                                         |
|  [Streaming Engine] (Whisper "base")                                    |
|    - Decoupled background thread processing PCM buffer every ~300ms     |
|    - Emits: PARTIAL:<text>                                              |
|                                                                         |
|  [Final Engine] (Whisper "medium" on GPU / "small" on CPU)              |
|    - Beam-search transcription on trailing silence (RMS VAD)            |
|    - Emits: RESULT:<text>                                               |
|                                                                         |
|  [AI Polish Engine] (Qwen 2.5 1.5B Instruct GGUF via llama-cpp)         |
|    - Custom ChatML prompts for Ukrainian and English text polish        |
|    - Emits: POLISHED:<text>                                             |
+-------------------------------------------------------------------------+
```

### STT & SLM Daemon Protocol (line-based over stdin / stdout)

| Command (stdin) | Description |
|---|---|
| `START` | Begin audio recording with automatic language detection |
| `START:<lang>` | Begin recording with a language hint (`START:uk` or `START:en`) |
| `STOP` | Force-stop recording immediately and finalize transcription |
| `POLISH:<text>` | Submit transcribed text to Qwen 2.5 for speech polish |

| Event (stdout) | Description |
|---|---|
| `LOADING` | Models started loading in the background |
| `STREAM_READY` | Streaming Whisper base model ready |
| `MODEL_READY` | Final transcription Whisper model ready |
| `DEVICE:<device>` | Inference device being used (`cuda` or `cpu`) |
| `POLISH_READY` | Qwen 2.5 SLM model ready |
| `LISTENING` | PipeWire audio capture in progress |
| `LEVEL:<0.0-1.0>` | Real-time audio amplitude for UI visualizer |
| `PARTIAL:<text>` | Intermediate streaming transcription during active speech |
| `PROCESSING` | Recording finished, running final pass transcription |
| `RESULT:<text>` | Final transcribed text |
| `POLISHED:<text>` | Cleaned, polished text returned from SLM |
| `ERROR:<msg>` | Error notification |

---

## Configuration

| Setting | File | Default | Description |
|---|---|---|---|
| Silence Threshold (RMS) | `stt/stt_daemon.py` | `0.032` | Energy threshold separating speech from background noise |
| Trailing Silence Timeout | `stt/stt_daemon.py` | `550` ms | Silence duration required to auto-stop recording |
| Daemon Keep-Alive | `qs/shell.qml` | `45000` ms | Idle time before models unload after popup closes |
| Translation Debounce | `qs/shell.qml` | `550` ms | Delay between text input and HTTP translation request |
| AI Polish Model | `download_models.sh` | `Qwen 2.5 1.5B Q4_K_M` | Stored in `~/.local/share/translator/models/` |
| Matugen Color Palette | `qs/Colors.qml` | `colors.json` | Path to `ii`'s live generated colors |

---

## Manual Testing & Verification

Run the Quickshell popup in a terminal to view live logs:
```bash
qs -c translator
```

In a separate terminal, toggle the popup surface:
```bash
qs -c translator ipc call translator toggle
```

Test the STT daemon standalone from the command line:
```bash
~/.local/share/translator-stt-venv/bin/python ~/.config/quickshell/translator/stt_daemon.py
```
Type `START:uk`, speak a phrase into your microphone, and wait for silence detection or type `STOP`.

---

## License

MIT — see [LICENSE](LICENSE) for details.
