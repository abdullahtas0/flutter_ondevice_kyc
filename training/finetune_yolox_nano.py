#!/usr/bin/env python3
"""Fine-tune YOLOX-Nano on synthetic card images.

The script does not download identity photos. It draws cards, writes YOLO
labels, and prints the Apache-2.0 YOLOX training command for Colab.

Classes:
  0 id_card
  1 mrz_zone
  2 credit_card_numbers

Usage:
  python training/finetune_yolox_nano.py --generate training/out/synthetic --count 8
"""

from __future__ import annotations

import argparse
import json
import struct
import zlib
from pathlib import Path


def _png(width: int, height: int, rgb: bytes) -> bytes:
    if len(rgb) != width * height * 3:
        raise ValueError("rgb buffer has the wrong length")
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)
        raw.extend(rgb[y * stride : (y + 1) * stride])

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(
        b"IDAT", zlib.compress(bytes(raw), 9)
    ) + chunk(b"IEND", b"")


def _fill(rgb: bytearray, width: int, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int]) -> None:
    for y in range(y0, y1):
        for x in range(x0, x1):
            i = (y * width + x) * 3
            rgb[i : i + 3] = bytes(color)


def _yolo(class_id: int, x0: int, y0: int, x1: int, y1: int, width: int, height: int) -> str:
    cx = ((x0 + x1) / 2) / width
    cy = ((y0 + y1) / 2) / height
    bw = (x1 - x0) / width
    bh = (y1 - y0) / height
    return f"{class_id} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}"


def generate(out_dir: Path, count: int) -> None:
    images = out_dir / "images"
    labels = out_dir / "labels"
    images.mkdir(parents=True, exist_ok=True)
    labels.mkdir(parents=True, exist_ok=True)
    width, height = 416, 416
    records: list[tuple[str, list[tuple[int, int, int, int, int]]]] = []
    for index in range(count):
        rgb = bytearray(width * height * 3)
        identity = index % 2 == 0
        x0, y0, x1, y1 = 48, 110, 368, 312
        _fill(rgb, width, x0, y0, x1, y1, (232, 226, 210))
        lines = [_yolo(0, x0, y0, x1, y1, width, height)]
        boxes = [(0, x0, y0, x1 - x0, y1 - y0)]
        if identity:
            band_y0 = y0 + int((y1 - y0) * 0.62)
            band_x0, band_x1, band_y1 = x0 + 16, x1 - 16, y1 - 12
            _fill(rgb, width, band_x0, band_y0, band_x1, band_y1, (36, 40, 44))
            lines.append(_yolo(1, band_x0, band_y0, band_x1, band_y1, width, height))
            boxes.append((1, band_x0, band_y0, band_x1 - band_x0, band_y1 - band_y0))
        else:
            band_y0 = y0 + int((y1 - y0) * 0.38)
            band_y1 = y0 + int((y1 - y0) * 0.58)
            band_x0, band_x1 = x0 + 24, x1 - 24
            _fill(rgb, width, band_x0, band_y0, band_x1, band_y1, (20, 20, 20))
            lines.append(_yolo(2, band_x0, band_y0, band_x1, band_y1, width, height))
            boxes.append((2, band_x0, band_y0, band_x1 - band_x0, band_y1 - band_y0))
        stem = f"card_{index:04d}"
        (images / f"{stem}.png").write_bytes(_png(width, height, bytes(rgb)))
        (labels / f"{stem}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        records.append((stem, boxes))
    _write_coco(out_dir, records, width, height)
    print(f"wrote {count} images to {out_dir}")
    print("next, from a YOLOX checkout (Apache-2.0):")
    print("  python tools/train.py -f training/yolox_nano_kyc.py -d 1 -b 8 -c yolox_nano.pth")


def _write_coco(out_dir: Path, records: list, width: int, height: int) -> None:
    categories = [
        {"id": 1, "name": "id_card"},
        {"id": 2, "name": "mrz_zone"},
        {"id": 3, "name": "credit_card_numbers"},
    ]
    images = []
    annotations = []
    ann_id = 1
    for image_id, (stem, boxes) in enumerate(records, start=1):
        images.append(
            {"id": image_id, "file_name": f"{stem}.png", "width": width, "height": height}
        )
        for class_id, x, y, box_w, box_h in boxes:
            annotations.append(
                {
                    "id": ann_id,
                    "image_id": image_id,
                    "category_id": class_id + 1,
                    "bbox": [x, y, box_w, box_h],
                    "area": box_w * box_h,
                    "iscrowd": 0,
                }
            )
            ann_id += 1
    payload = json.dumps(
        {"images": images, "annotations": annotations, "categories": categories}
    )
    annotations_dir = out_dir / "annotations"
    annotations_dir.mkdir(parents=True, exist_ok=True)
    (annotations_dir / "instances_train.json").write_text(payload, encoding="utf-8")
    (annotations_dir / "instances_val.json").write_text(payload, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", type=Path, help="directory for images and labels")
    parser.add_argument("--count", type=int, default=8)
    args = parser.parse_args()
    if args.generate is None:
        parser.error("pass --generate")
    generate(args.generate, args.count)


if __name__ == "__main__":
    main()
