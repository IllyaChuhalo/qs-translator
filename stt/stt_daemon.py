#!/usr/bin/env python3
"""
Resident STT daemon for the translator popup's mic button.

Protocol (line-based, newline-terminated, over stdin/stdout):
  stdin  "START"        -> begin recording immediately, auto-detect language;
                           auto-stops on trailing silence. Works even before
                           the model has finished loading — the model loads
                           in the background in parallel with recording.
  stdin  "START:<lang>" -> same, but hint the language (e.g. "START:uk") for
                           much better accuracy on short/ambiguous audio
  stdin  "STOP"         -> force-stop the current recording early (manual fallback)
  stdout "LOADING"      -> model started loading in the background (once, at startup)
  stdout "MODEL_READY"  -> model finished loading (informational; recording
                           doesn't wait on this)
  stdout "LISTENING"    -> recording in progress
  stdout "PROCESSING"   -> recording stopped, transcribing now
  stdout "WAITING_MODEL"-> (rare) you stopped talking before the model finished
                           loading; transcription is waiting on it
  stdout "RESULT:<text>"-> final transcript (may be empty if nothing usable was said)
  stdout "ERROR:<msg>"  -> something went wrong; daemon stays alive

Recording and model-loading are independent: the mic starts capturing
the instant START arrives, while the model loads in a background
thread. As long as you talk for roughly as long as the model takes to
load (~1-3s for `medium`), you never see any load-related wait at all —
it happens behind your own speech.

The model loads once and stays resident so repeated mic presses don't
pay the ~1-3s model-load cost each time. Silence/speech detection is a
simple RMS-energy threshold (no external VAD library — one less thing
to fight with pip over).

Usage: python stt_daemon.py [model_size]
  model_size: tiny|base|small|medium|large-v3 (default: medium)
"""

import sys
import subprocess
import threading
import time

SAMPLE_RATE = 16000
FRAME_MS = 30
FRAME_BYTES = int(SAMPLE_RATE * FRAME_MS / 1000) * 2  # 16-bit mono PCM
SILENCE_TAIL_MS = 800   # stop after this much trailing silence following speech
MIN_SPEECH_MS = 250     # ignore blips/noise shorter than this
MAX_RECORD_MS = 20000   # hard safety cap regardless of VAD
SILENCE_RMS_THRESHOLD = 0.02  # tune this if it cuts too early/late for your mic/room

MODEL_SIZE = sys.argv[1] if len(sys.argv) > 1 else "medium"


def log(msg: str) -> None:
    print(msg, flush=True)


import numpy as np

model_holder = {"model": None}
model_ready = threading.Event()


def load_model():
    log("LOADING")
    from faster_whisper import WhisperModel
    model_holder["model"] = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")
    model_ready.set()
    log("MODEL_READY")


threading.Thread(target=load_model, daemon=True).start()

recording_lock = threading.Lock()
stop_event = threading.Event()


def record_and_transcribe(language: str | None) -> None:
    try:
        proc = subprocess.Popen(
            ["pw-record", "--rate", str(SAMPLE_RATE), "--channels", "1", "--format", "s16", "-"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        log("ERROR:pw-record not found")
        return

    log("LISTENING")

    frames = bytearray()
    silence_ms = 0
    speech_ms = 0
    started_speech = False
    t0 = time.time()
    frame_count = 0

    try:
        while True:
            if stop_event.is_set():
                break
            if (time.time() - t0) * 1000 > MAX_RECORD_MS:
                break

            chunk = proc.stdout.read(FRAME_BYTES)
            if not chunk or len(chunk) < FRAME_BYTES:
                break
            frames += chunk
            frame_count += 1

            samples = np.frombuffer(chunk, dtype=np.int16).astype(np.float32)
            rms = float(np.sqrt(np.mean(samples ** 2))) / 32768.0

            if frame_count % 3 == 0:
                level = min(1.0, rms * 6.0)  # crude gain so normal speech isn't tiny
                log(f"LEVEL:{level:.2f}")

            is_speech = rms > SILENCE_RMS_THRESHOLD
            if is_speech:
                speech_ms += FRAME_MS
                silence_ms = 0
                started_speech = True
            elif started_speech:
                silence_ms += FRAME_MS

            if started_speech and silence_ms >= SILENCE_TAIL_MS and speech_ms >= MIN_SPEECH_MS:
                break
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()

    log("PROCESSING")

    if speech_ms < MIN_SPEECH_MS:
        log("RESULT:")
        return

    if not model_ready.is_set():
        log("WAITING_MODEL")  # only shows up if you talked less than the model took to load
        model_ready.wait()

    try:
        audio = np.frombuffer(bytes(frames), dtype=np.int16).astype(np.float32) / 32768.0
        segments, info = model_holder["model"].transcribe(
            audio,
            language=language,
            beam_size=5,
            vad_filter=True,
            condition_on_previous_text=False,
        )
        text = " ".join(seg.text.strip() for seg in segments).strip()
        log(f"RESULT:{text}")
    except Exception as e:
        log(f"ERROR:transcription failed: {e}")


def main() -> None:
    for line in sys.stdin:
        cmd = line.strip()
        if cmd.startswith("START"):
            if recording_lock.locked():
                continue
            stop_event.clear()
            lang = None
            if ":" in cmd:
                lang = cmd.split(":", 1)[1].strip() or None

            def run(lang=lang):
                with recording_lock:
                    record_and_transcribe(lang)

            threading.Thread(target=run, daemon=True).start()
        elif cmd == "STOP":
            stop_event.set()


if __name__ == "__main__":
    main()
