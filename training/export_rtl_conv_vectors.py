"""Generate one-image RTL vectors for the two-convolution Winograd engine.

The generated golden files use the exact exported INT4/INT18 arithmetic, so a
passing RTL test proves that Bank A -> Conv1 -> Bank B -> Conv2 -> Bank A is a
real data path rather than only a zero-weight control-flow test.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
from torch.nn import functional as F

from evaluate_export import load_tensor
from integer_inference import (
    INT18_PROFILE,
    RangeTracker,
    integer_winograd_conv2d,
    requantize_unsigned,
)


def load_hex_image(path: Path) -> torch.Tensor:
    values = np.array(
        [int(token, 16) for token in path.read_text(encoding="ascii").split()],
        dtype=np.int64,
    )
    if values.size != 28 * 28:
        raise ValueError(f"{path} contains {values.size} pixels; expected 784")
    return torch.from_numpy(values.reshape(1, 1, 28, 28).copy())


def write_hex(path: Path, tensor: torch.Tensor, bits: int) -> None:
    mask = (1 << bits) - 1
    digits = (bits + 3) // 4
    values = tensor.detach().cpu().reshape(-1).tolist()
    path.write_text(
        "".join(f"{int(value) & mask:0{digits}x}\n" for value in values),
        encoding="ascii",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--export-dir",
        type=Path,
        default=Path(__file__).parent / "export" / "qat_winograd3x3_w4_frozen_aug",
    )
    parser.add_argument(
        "--image",
        type=Path,
        default=Path(__file__).parents[1] / "data" / "0_0.txt",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).parents[1] / "verification" / "data" / "two_conv_real",
    )
    args = parser.parse_args()

    manifest = json.loads((args.export_dir / "manifest.json").read_text(encoding="utf-8"))
    tensors = {
        name: load_tensor(args.export_dir, specification)
        for name, specification in manifest["tensors"].items()
    }
    scales = manifest["scales"]
    shift = int(manifest["requantization"]["fractional_bits"])
    tracker = RangeTracker()
    image = load_hex_image(args.image)

    conv1, conv1_scale = integer_winograd_conv2d(
        image,
        tensors["conv1_u"],
        tensors["conv1_bias"],
        float(scales["conv1_output_accumulator"]),
        tracker,
        "conv1",
        INT18_PROFILE,
    )
    activation1 = F.max_pool2d(conv1.clamp_min(0), 2)
    activation1 = requantize_unsigned(
        activation1, conv1_scale, float(scales["activation1"]), shift=shift
    )

    conv2, conv2_scale = integer_winograd_conv2d(
        activation1,
        tensors["conv2_u"],
        tensors["conv2_bias"],
        float(scales["conv2_output_accumulator"]),
        tracker,
        "conv2",
        INT18_PROFILE,
    )
    activation2 = F.max_pool2d(conv2.clamp_min(0), 2)
    activation2 = requantize_unsigned(
        activation2, conv2_scale, float(scales["activation2"]), shift=shift
    )
    flat = activation2.reshape(1, -1)
    products = tracker.saturate(
        "fc.product", flat[:, None, :] * tensors["fc_weight"][None], 18
    )
    logits = torch.zeros_like(products[:, :, 0])
    for feature in range(products.shape[2]):
        logits = tracker.saturate(
            "fc.acc_add", logits + products[:, :, feature], 18
        )
    logits = tracker.saturate("fc.bias_add", logits + tensors["fc_bias"], 18)
    decision = logits.argmax(dim=1)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    write_hex(args.output_dir / "image_u8.hex", image, 8)
    write_hex(args.output_dir / "conv1_activation_u8.hex", activation1, 8)
    write_hex(args.output_dir / "conv2_activation_u8.hex", activation2, 8)
    write_hex(args.output_dir / "fc_logits_s18.hex", logits, 18)
    write_hex(args.output_dir / "decision.hex", decision, 4)
    metadata = {
        "source_image": str(args.image),
        "source_export": str(args.export_dir),
        "image_shape": list(image.shape),
        "conv1_activation_shape": list(activation1.shape),
        "conv2_activation_shape": list(activation2.shape),
        "conv1_multiplier": int(manifest["requantization"]["conv1_multiplier"]),
        "conv2_multiplier": int(manifest["requantization"]["conv2_multiplier"]),
        "decision": int(decision.item()),
    }
    (args.output_dir / "metadata.json").write_text(
        json.dumps(metadata, indent=2), encoding="utf-8"
    )
    print(f"generated={args.output_dir}")
    print(
        f"conv1_features={activation1.numel()} conv2_features={activation2.numel()} "
        f"decision={int(decision.item())}"
    )


if __name__ == "__main__":
    main()
