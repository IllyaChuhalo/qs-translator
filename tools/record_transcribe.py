#!/usr/bin/env python3
"""Standalone push-to-talk STT test script using PipeWire and Whisper."""

import subprocess
import sys
import tempfile
import time
from pathlib import Path


def record_until_enter(wav_path: str) -> None:
    """Records audio to a WAV file via pw-record until the user presses Enter."""
    proc = subprocess.Popen(
        ["pw-record", "--rate", "16000", "--channels", "1", "--format", "s16", wav_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    print("🎙️  Recording... press Enter to stop.")
    input()
    proc.terminate()
    proc.wait(timeout=5)


def main() -> None:
    model_size = sys.argv[1] if len(sys.argv) > 1 else "small"
    language = sys.argv[2] if len(sys.argv) > 2 else None

    print(
        f"Loading model '{model_size}' (first run downloads it, ~150MB-1.5GB depending on size)..."
    )
    t0 = time.time()
    from faster_whisper import WhisperModel

    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    print(f"Model loaded in {time.time() - t0:.1f}s")

    with tempfile.TemporaryDirectory() as tmp:
        wav_path = str(Path(tmp) / "capture.wav")
        record_until_enter(wav_path)

        print("Transcribing...")
        t0 = time.time()
        segments, info = model.transcribe(
            wav_path,
            language=language,
            beam_size=5,
            vad_filter=True,
            condition_on_previous_text=False,
        )
        text = " ".join(seg.text.strip() for seg in segments).strip()
        elapsed = time.time() - t0

        print()
        print(f"Detected language: {info.language} (p={info.language_probability:.2f})")
        print(f"Transcription time: {elapsed:.2f}s")
        print(f"Result: {text!r}")


if __name__ == "__main__":
    main()
