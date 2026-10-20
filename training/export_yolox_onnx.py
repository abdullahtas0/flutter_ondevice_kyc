#!/usr/bin/env python3
"""Export a YOLOX-Nano checkpoint the Dart head can decode.

The graph keeps sigmoid on objectness and class scores, and leaves box
deltas raw. NMS stays in Dart. This script does not quantize.
"""

from __future__ import annotations

import argparse


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-f", "--exp-file", required=True)
    parser.add_argument("-c", "--ckpt", required=True)
    parser.add_argument("-o", "--output", required=True)
    args = parser.parse_args()

    import torch
    from yolox.exp import get_exp

    exp = get_exp(args.exp_file, None)
    model = exp.get_model()
    try:
        checkpoint = torch.load(args.ckpt, map_location="cpu", weights_only=False)
    except TypeError:
        checkpoint = torch.load(args.ckpt, map_location="cpu")
    state = checkpoint["model"] if isinstance(checkpoint, dict) and "model" in checkpoint else checkpoint
    model.load_state_dict(state)
    model.eval()
    model.head.decode_in_inference = False
    dummy = torch.randn(1, 3, exp.test_size[0], exp.test_size[1])
    export_args = {
        "input_names": ["images"],
        "output_names": ["output"],
        "opset_version": 11,
    }
    try:
        torch.onnx.export(model, dummy, args.output, dynamo=False, **export_args)
    except TypeError:
        torch.onnx.export(model, dummy, args.output, **export_args)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
