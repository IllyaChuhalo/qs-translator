#!/usr/bin/env python3
"""STT and AI text polish resident daemon communicating via stdin/stdout."""

import ctypes
import glob
import os
import subprocess
import sys
import threading
import time

import numpy as np


def _preload_nvidia_libs() -> None:
    """Preloads CUDA runtime libraries from virtualenv site-packages if present."""
    venv_base = sys.prefix
    py_ver = f"python{sys.version_info.major}.{sys.version_info.minor}"
    nvidia_base = os.path.join(venv_base, "lib", py_ver, "site-packages", "nvidia")
    if os.path.isdir(nvidia_base):
        for sub in ["cuda_nvrtc", "cublas", "cudnn"]:
            lib_dir = os.path.join(nvidia_base, sub, "lib")
            if os.path.isdir(lib_dir):
                for so in sorted(glob.glob(os.path.join(lib_dir, "*.so*"))):
                    try:
                        ctypes.CDLL(so)
                    except Exception:
                        pass


_preload_nvidia_libs()

cuda_available = False
try:
    import ctranslate2

    if ctranslate2.get_cuda_device_count() > 0:
        cuda_available = True
except Exception:
    cuda_available = False

SAMPLE_RATE = 16000
FRAME_MS = 30
FRAME_BYTES = int(SAMPLE_RATE * FRAME_MS / 1000) * 2
SILENCE_TAIL_MS = 550
MIN_SPEECH_MS = 250
MAX_RECORD_MS = 25000
SILENCE_RMS_THRESHOLD = 0.032
CPU_THREADS = min(8, max(4, os.cpu_count() or 4))

if cuda_available:
    DEVICE = "cuda"
    COMPUTE_TYPE = "float16"
    DEFAULT_MODEL = "medium"
else:
    DEVICE = "cpu"
    COMPUTE_TYPE = "int8"
    DEFAULT_MODEL = "small"

MODEL_SIZE = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MODEL
MODELS_DIR = os.path.expanduser(
    os.environ.get("TRANSLATOR_MODELS_DIR", "~/.local/share/translator/models")
)
POLISH_MODEL_PATH = os.path.join(MODELS_DIR, "qwen2.5-1.5b-instruct-q4_k_m.gguf")


def log(msg: str) -> None:
    print(msg, flush=True)


stream_holder = {"model": None}
stream_ready = threading.Event()

final_holder = {"model": None}
final_ready = threading.Event()

llm_holder = {"model": None}
llm_ready = threading.Event()


def load_models_bg() -> None:
    """Loads speech recognition and text polish models in background threads."""
    log("LOADING")

    def load_whispers():
        try:
            from faster_whisper import WhisperModel

            stream_holder["model"] = WhisperModel(
                "base", device=DEVICE, compute_type=COMPUTE_TYPE, cpu_threads=CPU_THREADS
            )
            stream_ready.set()
            log("STREAM_READY")

            final_holder["model"] = WhisperModel(
                MODEL_SIZE, device=DEVICE, compute_type=COMPUTE_TYPE, cpu_threads=CPU_THREADS
            )
            final_ready.set()
            log("MODEL_READY")
            log(f"DEVICE:{DEVICE}")
        except Exception as e:
            log(f"ERROR:Whisper load failed: {e}")

    def load_llm():
        if os.path.exists(POLISH_MODEL_PATH):
            try:
                from llama_cpp import Llama

                llm_holder["model"] = Llama(
                    model_path=POLISH_MODEL_PATH,
                    n_ctx=512,
                    n_gpu_layers=33 if cuda_available else 0,
                    n_threads=CPU_THREADS,
                    verbose=False,
                )
                llm_ready.set()
                log("POLISH_READY")
            except Exception as e:
                log(f"ERROR:LLM load failed: {e}")
        else:
            log(f"ERROR:Polish model not found at {POLISH_MODEL_PATH}")

    t_whisper = threading.Thread(target=load_whispers, daemon=True)
    t_llm = threading.Thread(target=load_llm, daemon=True)
    t_whisper.start()
    t_llm.start()


threading.Thread(target=load_models_bg, daemon=True).start()

recording_lock = threading.Lock()
stop_event = threading.Event()


def polish_text(text: str) -> str:
    """Cleans speech disfluencies, punctuation, and typos using local LLM."""
    text = text.strip()
    if not text:
        return ""

    if not llm_ready.is_set():
        llm_ready.wait(timeout=3.0)

    if not llm_holder["model"]:
        return text

    is_uk = any("\u0400" <= c <= "\u04ff" for c in text)
    if is_uk:
        prompt = f"""<|im_start|>system
Ти — автокоректор та редактор усного тексту.
Виправ опечатки (особливо апострофи в словах: комп'ютер, зв'язок, пам'ять), пунктуацію, великі літери та видали слова-паразити на початку речення (ну, короче, типу).
Виведи ТІЛЬКИ виправлене речення без лапок і коментарів.
<|im_end|>
<|im_start|>user
ну короче скинь мені лінк на компютер<|im_end|>
<|im_start|>assistant
Скинь мені лінк на комп'ютер.<|im_end|>
<|im_start|>user
ну типу перевір цей звязок<|im_end|>
<|im_start|>assistant
Перевір цей зв'язок.<|im_end|>
<|im_start|>user
{text}<|im_end|>
<|im_start|>assistant
"""
    else:
        prompt = f"""<|im_start|>system
You are a speech text auto-correct editor.
Fix typos, speech recognition errors, punctuation, capitalization, and remove filler words (um, uh, like, you know).
Output ONLY the corrected sentence without quotes or comments.
<|im_end|>
<|im_start|>user
um like can you send me the link<|im_end|>
<|im_start|>assistant
Can you send me the link?<|im_end|>
<|im_start|>user
{text}<|im_end|>
<|im_start|>assistant
"""
    try:
        res = llm_holder["model"](
            prompt,
            max_tokens=128,
            temperature=0.0,
            stop=["<|im_end|>", "\n"],
        )
        cleaned = res["choices"][0]["text"].strip()
        cleaned = cleaned.strip("\"' \n")
        if cleaned.startswith("Вихід:"):
            cleaned = cleaned[len("Вихід:") :].strip()
        if cleaned.startswith("Output:"):
            cleaned = cleaned[len("Output:") :].strip()
        return cleaned if cleaned else text
    except Exception as e:
        log(f"ERROR:Polish inference error: {e}")
        return text


def record_and_transcribe(language: str | None) -> None:
    """Captures PipeWire audio until silence and transcribes with Whisper."""
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
    recording_active = threading.Event()
    recording_active.set()

    initial_prompt = (
        "Це транскрипція української або англійської мови."
        if language == "uk"
        else "English and Ukrainian voice speech."
    )

    def streaming_worker():
        """Streams partial transcription results at regular intervals while speech is active."""
        last_processed_len = 0
        while recording_active.is_set():
            time.sleep(0.30)
            if not started_speech or not stream_ready.is_set():
                continue
            cur_len = len(frames)
            if cur_len - last_processed_len < FRAME_BYTES * 8:
                continue
            last_processed_len = cur_len
            audio_snap = np.frombuffer(bytes(frames), dtype=np.int16).astype(np.float32) / 32768.0
            try:
                segs, _ = stream_holder["model"].transcribe(
                    audio_snap,
                    language=language,
                    beam_size=1,
                    temperature=0.0,
                    initial_prompt=initial_prompt,
                    vad_filter=False,
                    without_timestamps=True,
                    condition_on_previous_text=False,
                )
                partial_text = " ".join(s.text.strip() for s in segs).strip()
                if partial_text and recording_active.is_set():
                    log(f"PARTIAL:{partial_text}")
            except Exception:
                pass

    stream_thread = threading.Thread(target=streaming_worker, daemon=True)
    stream_thread.start()

    try:
        while True:
            if stop_event.is_set():
                break
            if (time.time() - t0) * 1000 >= MAX_RECORD_MS:
                break

            chunk = proc.stdout.read(FRAME_BYTES)
            if not chunk or len(chunk) < FRAME_BYTES:
                break

            frames.extend(chunk)
            frame_count += 1

            samples = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
            rms = float(np.sqrt(np.mean(samples**2)))

            if frame_count % 2 == 0:
                visual_level = min(1.0, max(0.0, (rms - 0.01) / 0.15))
                log(f"LEVEL:{visual_level:.2f}")

            if rms >= SILENCE_RMS_THRESHOLD:
                speech_ms += FRAME_MS
                silence_ms = 0
                if speech_ms >= MIN_SPEECH_MS:
                    started_speech = True
            elif started_speech:
                silence_ms += FRAME_MS

            if started_speech and silence_ms >= SILENCE_TAIL_MS and speech_ms >= MIN_SPEECH_MS:
                break
    finally:
        recording_active.clear()
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()

    log("PROCESSING")

    if speech_ms < MIN_SPEECH_MS:
        log("RESULT:")
        return

    if not final_ready.is_set():
        log("WAITING_MODEL")
        final_ready.wait()

    try:
        audio = np.frombuffer(bytes(frames), dtype=np.int16).astype(np.float32) / 32768.0
        model = final_holder["model"] or stream_holder["model"]
        segments, _ = model.transcribe(
            audio,
            language=language,
            beam_size=2,
            initial_prompt=initial_prompt,
            vad_filter=True,
            without_timestamps=True,
            condition_on_previous_text=False,
        )
        text = " ".join(seg.text.strip() for seg in segments).strip()
        log(f"RESULT:{text}")
    except Exception as e:
        log(f"ERROR:transcription failed: {e}")


def main() -> None:
    for line in sys.stdin:
        cmd = line.strip()
        if not cmd:
            continue
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
        elif cmd.startswith("POLISH:"):
            raw_text = cmd[len("POLISH:") :].strip()

            def run_polish(t=raw_text):
                cleaned = polish_text(t)
                log(f"POLISHED:{cleaned}")

            threading.Thread(target=run_polish, daemon=True).start()


if __name__ == "__main__":
    main()
