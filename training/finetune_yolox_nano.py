#!/usr/bin/env python3
"""Draw a synthetic card set for YOLOX-Nano.

No identity photograph is downloaded or embedded. Each image is a light
rectangle, slightly rotated, with either a dark MRZ band or a PAN band,
pasted on clutter. Train and validation do not share a file.

YOLOX reads this layout from training/yolox_nano_kyc.py:

  out/train2017/*.png
  out/val2017/*.png
  out/annotations/instances_train.json
  out/annotations/instances_val.json

Classes, matching the Dart head:
  0 id_card
  1 mrz_zone
  2 credit_card_numbers

Usage:
  python training/finetune_yolox_nano.py --self-test
  python training/finetune_yolox_nano.py --generate training/out/synthetic --count 1200
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

CANVAS = 416
CATEGORIES = [
    {"id": 1, "name": "id_card"},
    {"id": 2, "name": "mrz_zone"},
    {"id": 3, "name": "credit_card_numbers"},
]


def generate(out_dir: Path, count: int, seed: int) -> None:
    if count < 5:
        raise SystemExit("count must be at least 5 so train and val both exist")
    rng = random.Random(seed)
    splits: dict[str, list[tuple[str, list[tuple[int, float, float, float, float]]]]] = {
        "train2017": [],
        "val2017": [],
    }
    for index in range(count):
        split = "val2017" if index % 5 == 0 else "train2017"
        stem = f"card_{index:04d}"
        image, boxes = _scene(rng)
        folder = out_dir / split
        folder.mkdir(parents=True, exist_ok=True)
        image.save(folder / f"{stem}.png")
        splits[split].append((stem, boxes))
    for split, records in splits.items():
        _write_coco(out_dir, split, records)
    summary = {
        "seed": seed,
        "count": count,
        "train": len(splits["train2017"]),
        "val": len(splits["val2017"]),
        "classes": [item["name"] for item in CATEGORIES],
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote {summary['train']} train and {summary['val']} val images to {out_dir}"
    )


def _scene(rng: random.Random) -> tuple[Image.Image, list[tuple[int, float, float, float, float]]]:
    background = Image.new("RGB", (CANVAS, CANVAS), _color(rng, 24, 90))
    draw = ImageDraw.Draw(background)
    for _ in range(rng.randint(4, 8)):
        x0 = rng.randint(0, CANVAS - 30)
        y0 = rng.randint(0, CANVAS - 30)
        x1 = min(CANVAS - 1, x0 + rng.randint(24, 160))
        y1 = min(CANVAS - 1, y0 + rng.randint(16, 120))
        draw.rectangle([x0, y0, x1, y1], fill=_color(rng, 40, 210))
    _speckle(background, rng, 10)

    identity = rng.random() < 0.7
    card_w = rng.randint(210, 300)
    card_h = int(round(card_w / rng.uniform(1.52, 1.66)))
    angle = rng.uniform(-14, 14)
    card = Image.new("RGB", (card_w, card_h), _color(rng, 206, 246))
    card_draw = ImageDraw.Draw(card)
    card_draw.rectangle([1, 1, card_w - 2, card_h - 2], outline=_color(rng, 110, 170))
    local: list[tuple[int, tuple[int, int, int, int]]] = []
    if identity:
        top = int(card_h * rng.uniform(0.58, 0.70))
        bottom = card_h - rng.randint(8, 14)
        left = rng.randint(10, 18)
        right = card_w - rng.randint(10, 18)
        band = (left, top, right, bottom)
        card_draw.rectangle(band, fill=_color(rng, 16, 48))
        for line in range(3):
            y = top + int((bottom - top) * (line + 1) / 4)
            card_draw.line(
                [(left + 6, y), (right - 6, y)],
                fill=_color(rng, 64, 100),
                width=2,
            )
        local.append((1, band))
        glare_bottom = max(6, top - 6)
        _glare(card, rng, glare_bottom)
    else:
        top = int(card_h * rng.uniform(0.34, 0.48))
        height = max(28, int(card_h * rng.uniform(0.16, 0.22)))
        left = rng.randint(16, 28)
        right = card_w - rng.randint(16, 28)
        band = (left, top, right, min(card_h - 8, top + height))
        card_draw.rectangle(band, fill=_color(rng, 12, 36))
        local.append((2, band))
        _glare(card, rng, top)

    mask = Image.new("L", (card_w, card_h), 255)
    rotated = card.rotate(angle, expand=True, resample=Image.BICUBIC, fillcolor=(0, 0, 0))
    rotated_mask = mask.rotate(angle, expand=True, resample=Image.BICUBIC, fillcolor=0)
    max_left = CANVAS - rotated.width
    max_top = CANVAS - rotated.height
    if max_left < 0 or max_top < 0:
        raise RuntimeError("rotated card does not fit on the canvas")
    origin_x = rng.randint(0, max_left)
    origin_y = rng.randint(0, max_top)
    background.paste(rotated, (origin_x, origin_y), rotated_mask)

    offset_x = (rotated.width - card_w) / 2
    offset_y = (rotated.height - card_h) / 2
    center_x = card_w / 2
    center_y = card_h / 2
    boxes = [
        (
            0,
            *_shift(_map_box((0, 0, card_w - 1, card_h - 1), center_x, center_y, angle, offset_x, offset_y), origin_x, origin_y),
        )
    ]
    for class_id, box in local:
        boxes.append(
            (
                class_id,
                *_shift(_map_box(box, center_x, center_y, angle, offset_x, offset_y), origin_x, origin_y),
            )
        )
    return background, boxes


def _map_box(
    box: tuple[int, int, int, int],
    center_x: float,
    center_y: float,
    angle: float,
    offset_x: float,
    offset_y: float,
) -> tuple[float, float, float, float]:
    x0, y0, x1, y1 = box
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    mapped = []
    for x, y in corners:
        rx, ry = _rotate_point(x, y, center_x, center_y, angle)
        mapped.append((rx + offset_x, ry + offset_y))
    xs = [point[0] for point in mapped]
    ys = [point[1] for point in mapped]
    return min(xs), min(ys), max(xs), max(ys)


def _shift(
    box: tuple[float, float, float, float],
    origin_x: int,
    origin_y: int,
) -> tuple[float, float, float, float]:
    x0, y0, x1, y1 = box
    return x0 + origin_x, y0 + origin_y, x1 + origin_x, y1 + origin_y


def _rotate_point(x: float, y: float, cx: float, cy: float, degrees: float) -> tuple[float, float]:
    radians = math.radians(degrees)
    dx, dy = x - cx, y - cy
    cos_a, sin_a = math.cos(radians), math.sin(radians)
    return cx + dx * cos_a - dy * sin_a, cy + dx * sin_a + dy * cos_a


def _glare(card: Image.Image, rng: random.Random, bottom: int) -> None:
    if bottom < 12:
        return
    glare = Image.new("RGB", card.size, (255, 255, 255))
    mask = Image.new("L", card.size, 0)
    draw = ImageDraw.Draw(mask)
    x0 = rng.randint(8, max(9, card.width // 3))
    x1 = rng.randint(card.width // 2, card.width - 8)
    draw.rectangle([x0, 6, x1, bottom], fill=rng.randint(40, 80))
    card.paste(glare, (0, 0), mask)


def _speckle(image: Image.Image, rng: random.Random, amount: int) -> None:
    pixels = image.load()
    width, height = image.size
    for y in range(0, height, 3):
        for x in range(0, width, 3):
            delta = rng.randint(-amount, amount)
            red, green, blue = pixels[x, y]
            pixels[x, y] = (
                _clamp(red + delta),
                _clamp(green + delta),
                _clamp(blue + delta),
            )


def _color(rng: random.Random, low: int, high: int) -> tuple[int, int, int]:
    return (_clamp(rng.randint(low, high)), _clamp(rng.randint(low, high)), _clamp(rng.randint(low, high)))


def _clamp(value: int) -> int:
    return max(0, min(255, value))


def _write_coco(
    out_dir: Path,
    split: str,
    records: list[tuple[str, list[tuple[int, float, float, float, float]]]],
) -> None:
    images = []
    annotations = []
    ann_id = 1
    for image_id, (stem, boxes) in enumerate(records, start=1):
        images.append(
            {
                "id": image_id,
                "file_name": f"{stem}.png",
                "width": CANVAS,
                "height": CANVAS,
            }
        )
        for class_id, x0, y0, x1, y1 in boxes:
            width = x1 - x0
            height = y1 - y0
            annotations.append(
                {
                    "id": ann_id,
                    "image_id": image_id,
                    "category_id": class_id + 1,
                    "bbox": [round(x0, 2), round(y0, 2), round(width, 2), round(height, 2)],
                    "area": round(width * height, 2),
                    "iscrowd": 0,
                }
            )
            ann_id += 1
    payload = {
        "images": images,
        "annotations": annotations,
        "categories": CATEGORIES,
    }
    name = "instances_train.json" if split == "train2017" else "instances_val.json"
    annotations_dir = out_dir / "annotations"
    annotations_dir.mkdir(parents=True, exist_ok=True)
    (annotations_dir / name).write_text(json.dumps(payload), encoding="utf-8")


def self_test() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        first = Path(tmp) / "one"
        second = Path(tmp) / "two"
        generate(first, 8, seed=1)
        generate(second, 8, seed=1)
        _assert_layout(first)
        digest_a = hashlib.sha256((first / "train2017" / "card_0001.png").read_bytes()).hexdigest()
        digest_b = hashlib.sha256((second / "train2017" / "card_0001.png").read_bytes()).hexdigest()
        if digest_a != digest_b:
            raise SystemExit("the same seed did not redraw the same card")
    rotated = _rotate_point(4, 1, 2, 1, 90)
    if abs(rotated[0] - 2) > 1e-6 or abs(rotated[1] - 3) > 1e-6:
        raise SystemExit("rotation is not counter-clockwise")
    print("synthetic self-test passed")


def _assert_layout(out_dir: Path) -> None:
    summary = json.loads((out_dir / "summary.json").read_text(encoding="utf-8"))
    if summary["train"] != 6 or summary["val"] != 2:
        raise SystemExit("8 images should split into 6 train and 2 val")
    train_names = {path.name for path in (out_dir / "train2017").glob("*.png")}
    val_names = {path.name for path in (out_dir / "val2017").glob("*.png")}
    if train_names & val_names:
        raise SystemExit("train and val share a file")
    seen_bands = set()
    for split, json_name in (
        ("train2017", "instances_train.json"),
        ("val2017", "instances_val.json"),
    ):
        payload = json.loads((out_dir / "annotations" / json_name).read_text(encoding="utf-8"))
        images = {image["id"]: image for image in payload["images"]}
        by_image: dict[int, list[dict]] = {image_id: [] for image_id in images}
        for ann in payload["annotations"]:
            by_image[ann["image_id"]].append(ann)
        for image_id, image in images.items():
            anns = by_image[image_id]
            if len(anns) != 2:
                raise SystemExit("each card needs the card box and one band")
            if {ann["category_id"] for ann in anns} - {1, 2, 3}:
                raise SystemExit("unknown category")
            picture = Image.open(out_dir / split / image["file_name"]).convert("RGB")
            if picture.size != (CANVAS, CANVAS):
                raise SystemExit("canvas is not 416")
            for ann in anns:
                x, y, width, height = ann["bbox"]
                if width < 8 or height < 8:
                    raise SystemExit("box is too small")
                if x < -0.5 or y < -0.5 or x + width > CANVAS + 0.5 or y + height > CANVAS + 0.5:
                    raise SystemExit("box leaves the canvas")
                if ann["category_id"] == 1:
                    continue
                seen_bands.add(ann["category_id"])
                cx = int(x + width / 2)
                cy = int(y + height / 2)
                red, green, blue = picture.getpixel((cx, cy))
                if (red + green + blue) / 3 >= 140:
                    raise SystemExit("band center is not dark, so the box missed the ink")
    if seen_bands != {2, 3}:
        raise SystemExit("the set is missing an MRZ band or a PAN band")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", type=Path, help="directory for the YOLOX coco layout")
    parser.add_argument("--count", type=int, default=8)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.generate is None:
        parser.error("pass --generate or --self-test")
    generate(args.generate, args.count, args.seed)


if __name__ == "__main__":
    main()
