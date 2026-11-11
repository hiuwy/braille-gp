import os
import sys
import subprocess
import urllib.request
import winsound

TEXT = ""

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PIPER_EXE = os.path.join(BASE_DIR, "piper_windows_amd64", "piper", "piper.exe")
MODEL = os.path.join(BASE_DIR, "en_US-libritts_r-medium.onnx")
OUTPUT_WAV = os.path.join(BASE_DIR, "output.wav")


def pythonTTS(text: str):
    if not text.strip():
        return

    # Auto-download the voice model files if you don't have them yet
    if not os.path.exists(MODEL):
        print("Downloading voice model (60 MB, one time only)...")
        base = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/"
        urllib.request.urlretrieve(base + "en_US-libritts_r-medium.onnx", MODEL)
        urllib.request.urlretrieve(base + "en_US-libritts_r-medium.onnx.json", MODEL + ".json")

    subprocess.run(
        [PIPER_EXE, "-m", MODEL, "-f", OUTPUT_WAV, "--length_scale", "1.5"],
        input=text.encode("utf-8"),
        check=True
    )

    winsound.PlaySound(OUTPUT_WAV, winsound.SND_FILENAME)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        pythonTTS(" ".join(sys.argv[1:]))
    elif TEXT:
        pythonTTS(TEXT)
