#!/usr/bin/env python3
"""Export the detector and recognizer, and refuse dynamic quantization.

YOLOX-Nano stays FP32 unless a calibration directory is passed to
quantize_detector_static. The recognizer stays FP32. If the Paddle
dictionary has no '<' filler, the MRZ head must be trained on the synthetic
alphabet instead of the English recognizer.

Usage:
  python training/export_models.py --self-test
  python training/export_models.py --check-dict path/to/en_dict.txt
  python training/export_models.py --write-checksums assets/models
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import tempfile
from pathlib import Path

BUDGET_BYTES = 15 * 1024 * 1024
MRZ_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<"


def filler_present(dictionary: Path) -> bool:
    text = dictionary.read_text(encoding="utf-8")
    lines = [line.replace("\r", "") for line in text.split("\n")]
    return "<" in lines


def prepare_mrz_alphabet(destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(MRZ_ALPHABET) + "\n", encoding="utf-8")
    print(f"wrote MRZ alphabet to {destination}")
    print("The English dictionary has no '<' filler.")
    print("Train a CTC recognizer on synthetic MRZ lines with this alphabet.")
    print("Keep the recognizer FP32. Check digits still gate the result.")


def quantize_detector_static(model_in: Path, model_out: Path, calibration_dir: Path) -> None:
    images = list(calibration_dir.glob("*.png")) + list(calibration_dir.glob("*.jpg"))
    if not calibration_dir.is_dir() or not images:
        raise SystemExit(
            "Static INT8 needs a directory of calibration images. "
            "The detector is not quantized with dynamic weight-only conversion."
        )
    try:
        from onnxruntime.quantization import CalibrationDataReader, QuantType, quantize_static
    except ImportError as error:
        raise SystemExit("onnxruntime quantization extras are not installed") from error

    class Reader(CalibrationDataReader):
        def __init__(self) -> None:
            self._done = False

        def get_next(self):
            if self._done:
                return None
            self._done = True
            raise SystemExit(
                "Add a preprocessing reader for 1x3x416x416 BGR tensors before running static INT8. "
                "If mAP drops, keep the FP32 onnx."
            )

    quantize_static(
        str(model_in),
        str(model_out),
        Reader(),
        weight_type=QuantType.QInt8,
    )


def write_checksums(directory: Path) -> int:
    files = sorted(
        path
        for path in directory.iterdir()
        if path.is_file() and path.suffix in {".onnx", ".txt"} and path.name != "CHECKSUMS.txt"
    )
    total = sum(path.stat().st_size for path in files)
    lines = [
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}  {path.stat().st_size}"
        for path in files
    ]
    if not lines:
        lines = ["pending  card_detector.onnx", "pending  text_rec.onnx", "pending  en_dict.txt"]
    (directory / "CHECKSUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    if total > BUDGET_BYTES:
        raise SystemExit(f"model budget exceeded: {total} bytes > {BUDGET_BYTES}")
    print(f"checksums written, onnx+dict bytes={total}")
    return total


def self_test() -> None:
    source = Path(__file__).read_text(encoding="utf-8")
    forbidden = "quantize_" + "dynamic("
    if forbidden in source:
        raise SystemExit("dynamic weight quantization must stay out of this script")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        missing = root / "missing.txt"
        missing.write_text("A\nB\n0\n1\n", encoding="utf-8")
        if filler_present(missing):
            raise SystemExit("filler check should fail when < is absent")
        present = root / "present.txt"
        present.write_text("A\n<\n0\n", encoding="utf-8")
        if not filler_present(present):
            raise SystemExit("filler check should pass when < is a line")
        prepare_mrz_alphabet(root / "mrz_dict.txt")
        alphabet = (root / "mrz_dict.txt").read_text(encoding="utf-8").split()
        if "<" not in alphabet:
            raise SystemExit("MRZ alphabet dropped the filler")
        empty = root / "models"
        empty.mkdir()
        if write_checksums(empty) != 0:
            raise SystemExit("empty model dir should report zero bytes")
    print("export self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--check-dict", type=Path)
    parser.add_argument("--write-checksums", type=Path)
    parser.add_argument("--prepare-mrz-alphabet", type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.check_dict:
        if filler_present(args.check_dict):
            print("dictionary contains '<'")
            return
        print("dictionary has no '<' filler")
        sys.exit(2)
    if args.prepare_mrz_alphabet:
        prepare_mrz_alphabet(args.prepare_mrz_alphabet)
        return
    if args.write_checksums:
        write_checksums(args.write_checksums)
        return
    parser.error("choose --self-test, --check-dict, --prepare-mrz-alphabet, or --write-checksums")


if __name__ == "__main__":
    main()
