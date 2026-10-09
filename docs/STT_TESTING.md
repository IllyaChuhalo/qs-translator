# STT test — setup

## 1. System dependencies

```bash
# pw-record ships with pipewire, which you most likely already have installed
which pw-record || sudo pacman -S pipewire
```

## 2. Python environment

Arch marks the system pip as "externally managed" (PEP 668), so a venv is the
simplest way without resorting to `--break-system-packages`:

```bash
python -m venv ~/.local/share/translator-stt-venv
source ~/.local/share/translator-stt-venv/bin/activate.fish  # bash: bin/activate
pip install faster-whisper
```

## 3. Running the test

```bash
source ~/.local/share/translator-stt-venv/bin/activate
python record_transcribe.py small uk
```

- The first argument is the model size (`tiny`/`base`/`small`/`medium`/`large-v3`).
  Start with `small` — a decent quality/speed balance on CPU. If it is too slow
  on your hardware, try `base`. If you want maximum quality and have time to
  wait, use `medium`.
- The second argument is the language (`uk` or `en`). You can omit it
  entirely — whisper will then detect the language on the fly (worth trying
  both ways: with and without a language hint, comparing quality and speed).
- The first run downloads the model (cached in `~/.cache/huggingface`; later
  runs load the model almost instantly).

Speak after "🎙️ Recording..." and press Enter when you are done — you will see
the recognized text, the transcription time, and the language the model
detected on its own.

## What to evaluate

- Recognition quality for your pronunciation (uk and en separately)
- Transcription speed relative to the recording length (for example, how many
  seconds it took to recognize 3 s of speech)
- Whether `small` is enough or `medium` is needed
- How the model handles code-switching (if you mix Ukrainian with English
  terms in a single phrase)

Once you decide on the model, we will wire recording/transcription into the
microphone button itself in `shell.qml`.
