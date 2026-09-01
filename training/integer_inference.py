"""Integer golden inference for the trained Winograd QAT model.

All Winograd transforms, products, reductions, biases, pooling, and FC MACs are
performed on integer codes.  int64 is used as an overflow-free container while
the observed ranges are collected to determine the required hardware widths.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from torch.nn import functional as F
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

from models import QATWinograd3x3
from winograd import transform_weights


BT = torch.tensor(
    [[1, 0, -1, 0], [0, 1, 1, 0], [0, -1, 1, 0], [0, 1, 0, -1]],
    dtype=torch.int64,
)
AT = torch.tensor([[1, 1, 1, 0], [0, 1, -1, -1]], dtype=torch.int64)


class RangeTracker:
    def __init__(self) -> None:
        self.ranges: dict[str, list[int]] = {}
        self.saturations: dict[str, int] = {}

    def observe(self, name: str, value: torch.Tensor) -> None:
        minimum = int(value.min())
        maximum = int(value.max())
        if name not in self.ranges:
            self.ranges[name] = [minimum, maximum]
        else:
            self.ranges[name][0] = min(self.ranges[name][0], minimum)
            self.ranges[name][1] = max(self.ranges[name][1], maximum)

    @staticmethod
    def signed_bits(minimum: int, maximum: int) -> int:
        bits = 1
        while minimum < -(1 << (bits - 1)) or maximum > (1 << (bits - 1)) - 1:
            bits += 1
        return bits

    def report(self) -> dict[str, dict[str, int]]:
        return {
            name: {
                "min": limits[0],
                "max": limits[1],
                "signed_bits": self.signed_bits(*limits),
            }
            for name, limits in self.ranges.items()
        }

    def saturate(self, name: str, value: torch.Tensor, bits: int | None) -> torch.Tensor:
        if bits is None:
            return value
        minimum = -(1 << (bits - 1))
        maximum = (1 << (bits - 1)) - 1
        clipped = int(((value < minimum) | (value > maximum)).sum())
        self.saturations[name] = self.saturations.get(name, 0) + clipped
        return value.clamp(minimum, maximum)


EXACT_PROFILE: dict[str, int | None] = {
    "v": None,
    "product": None,
    "m": None,
    "y": None,
    "fc_product": None,
    "fc_acc": None,
}

INT18_PROFILE: dict[str, int | None] = {
    "v": 11,
    "product": 18,
    "m": 18,
    "y": 18,
    "fc_product": 18,
    "fc_acc": 18,
}


def narrow_profile(bits: int) -> dict[str, int | None]:
    return {
        "v": 11,
        "product": bits,
        "m": bits,
        "y": bits,
        "fc_product": bits,
        "fc_acc": bits,
    }


def quantize_code(value: torch.Tensor, scale: torch.Tensor, qmin: int, qmax: int) -> torch.Tensor:
    return torch.round(value / float(scale)).clamp(qmin, qmax).to(torch.int64)


def requantize_unsigned(
    value: torch.Tensor, source_scale: float, target_scale: float, *, shift: int = 24
) -> torch.Tensor:
    """Requantize nonnegative codes using an integer multiplier and right shift."""
    multiplier = round((source_scale / target_scale) * (1 << shift))
    if multiplier <= 0:
        raise ValueError("requantization multiplier must be positive")
    rounded = (value * multiplier + (1 << (shift - 1))) >> shift
    return rounded.clamp(0, 255).to(torch.int64)


def integer_winograd_conv2d(
    x_code: torch.Tensor,
    u_code: torch.Tensor,
    bias_code: torch.Tensor,
    output_scale: float,
    tracker: RangeTracker,
    name: str,
    profile: dict[str, int | None],
) -> tuple[torch.Tensor, float]:
    """Return unrequantized integer convolution output and its real scale."""
    n, channels, height, width = x_code.shape
    kernels = u_code.shape[0]
    out_h, out_w = height - 2, width - 2
    padded_out_h = (out_h + 1) // 2 * 2
    padded_out_w = (out_w + 1) // 2 * 2
    x_code = F.pad(x_code, (0, padded_out_w - out_w, 0, padded_out_h - out_h))

    # [N,C,H,W] -> [N,C,tile_row,tile_col,4,4]
    tiles = x_code.unfold(2, 4, 2).unfold(3, 4, 2)
    v = torch.matmul(torch.matmul(BT, tiles), BT.t())
    tracker.observe(f"{name}.V", v)
    v = tracker.saturate(f"{name}.V", v, profile["v"])

    products = v[:, None] * u_code[None, :, :, None, None]
    tracker.observe(f"{name}.product", products)
    products = tracker.saturate(f"{name}.product", products, profile["product"])
    m = torch.zeros_like(products[:, :, 0])
    for channel in range(channels):
        m = tracker.saturate(f"{name}.M_add", m + products[:, :, channel], profile["m"])
    tracker.observe(f"{name}.M", m)

    # A^T M A with saturation after every adder, matching a two-stage RTL tree.
    row0 = tracker.saturate(f"{name}.AT_left", m[..., 0, :] + m[..., 1, :], profile["y"])
    row0 = tracker.saturate(f"{name}.AT_left", row0 + m[..., 2, :], profile["y"])
    row1 = tracker.saturate(f"{name}.AT_left", m[..., 1, :] - m[..., 2, :], profile["y"])
    row1 = tracker.saturate(f"{name}.AT_left", row1 - m[..., 3, :], profile["y"])
    transformed_rows = torch.stack((row0, row1), dim=-2)
    col0 = tracker.saturate(
        f"{name}.AT_right",
        transformed_rows[..., 0] + transformed_rows[..., 1],
        profile["y"],
    )
    col0 = tracker.saturate(
        f"{name}.AT_right", col0 + transformed_rows[..., 2], profile["y"]
    )
    col1 = tracker.saturate(
        f"{name}.AT_right",
        transformed_rows[..., 1] - transformed_rows[..., 2],
        profile["y"],
    )
    col1 = tracker.saturate(
        f"{name}.AT_right", col1 - transformed_rows[..., 3], profile["y"]
    )
    y_tiles = torch.stack((col0, col1), dim=-1)
    tracker.observe(f"{name}.Y_before_bias", y_tiles)
    tile_rows, tile_cols = padded_out_h // 2, padded_out_w // 2
    y = (
        y_tiles.permute(0, 1, 2, 4, 3, 5)
        .reshape(n, kernels, padded_out_h, padded_out_w)
        [:, :, :out_h, :out_w]
    )

    bias_code = bias_code.to(torch.int64)
    tracker.observe(f"{name}.bias", bias_code)
    y = tracker.saturate(
        f"{name}.bias_add", y + bias_code.reshape(1, -1, 1, 1), profile["y"]
    )
    tracker.observe(f"{name}.Y_after_bias", y)
    return y, output_scale


@torch.inference_mode()
def integer_forward(
    model: QATWinograd3x3,
    images: torch.Tensor,
    tracker: RangeTracker,
    profile: dict[str, int | None] = EXACT_PROFILE,
) -> torch.Tensor:
    input_scale = float(model.input_quant.scale)
    x = quantize_code(images, model.input_quant.scale, 0, 255)
    tracker.observe("input.code", x)

    u1 = model.conv1.u_quant.integer(transform_weights(model.conv1.weight)).to(torch.int64)
    tracker.observe("conv1.U", u1)
    conv1_scale = input_scale * float(model.conv1.u_quant.scale)
    conv1_bias = torch.round(model.conv1.bias.detach() / conv1_scale).to(torch.int64)
    x, scale = integer_winograd_conv2d(
        x,
        u1,
        conv1_bias,
        conv1_scale,
        tracker,
        "conv1",
        profile,
    )
    x = F.max_pool2d(x.clamp_min(0), 2)
    tracker.observe("conv1.post_pool_relu", x)
    x = requantize_unsigned(x, scale, float(model.activation1_quant.scale))
    tracker.observe("activation1.code", x)

    u2 = model.conv2.u_quant.integer(transform_weights(model.conv2.weight)).to(torch.int64)
    tracker.observe("conv2.U", u2)
    conv2_scale = float(model.activation1_quant.scale) * float(model.conv2.u_quant.scale)
    conv2_bias = torch.round(model.conv2.bias.detach() / conv2_scale).to(torch.int64)
    x, scale = integer_winograd_conv2d(
        x,
        u2,
        conv2_bias,
        conv2_scale,
        tracker,
        "conv2",
        profile,
    )
    x = F.max_pool2d(x.clamp_min(0), 2)
    tracker.observe("conv2.post_pool_relu", x)
    x = requantize_unsigned(x, scale, float(model.activation2_quant.scale))
    tracker.observe("activation2.code", x)

    x = torch.flatten(x, 1)
    fc_weight = model.fc.weight_quant.integer(model.fc.weight).to(torch.int64)
    tracker.observe("fc.weight", fc_weight)
    products = x[:, None, :] * fc_weight[None]
    tracker.observe("fc.product", products)
    products = tracker.saturate("fc.product", products, profile["fc_product"])
    logits = torch.zeros_like(products[:, :, 0])
    for element in range(products.shape[2]):
        logits = tracker.saturate(
            "fc.acc_add", logits + products[:, :, element], profile["fc_acc"]
        )
    tracker.observe("fc.acc_before_bias", logits)
    fc_scale = float(model.activation2_quant.scale) * float(model.fc.weight_quant.scale)
    fc_bias = torch.round(model.fc.bias.detach() / fc_scale).to(torch.int64)
    tracker.observe("fc.bias", fc_bias)
    logits = tracker.saturate("fc.bias_add", logits + fc_bias, profile["fc_acc"])
    tracker.observe("fc.acc_after_bias", logits)
    return logits


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--checkpoint",
        type=Path,
        default=Path(__file__).parent / "runs" / "qat_winograd3x3_97.pt",
    )
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).parent / "data")
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument(
        "--profile",
        choices=("exact", "int18", "int17", "int16", "int15", "int14", "int13", "int12"),
        default="exact",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path(__file__).parent / "runs" / "integer_inference_97.json",
    )
    args = parser.parse_args()

    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    weight_bits = int(saved.get("args", {}).get("weight_bits", 8))
    model = QATWinograd3x3(weight_bits=weight_bits).eval()
    model.load_float_state_dict(saved["model"])
    test_set = datasets.MNIST(
        args.data_dir, train=False, download=False, transform=transforms.ToTensor()
    )
    loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False)

    tracker = RangeTracker()
    profiles = {
        "exact": EXACT_PROFILE,
        "int18": INT18_PROFILE,
        "int17": narrow_profile(17),
        "int16": narrow_profile(16),
        "int15": narrow_profile(15),
        "int14": narrow_profile(14),
        "int13": narrow_profile(13),
        "int12": narrow_profile(12),
    }
    profile = profiles[args.profile]
    correct = 0
    total = 0
    for images, labels in loader:
        logits = integer_forward(model, images, tracker, profile)
        correct += int((logits.argmax(dim=1) == labels).sum())
        total += labels.numel()

    result = {
        "checkpoint": str(args.checkpoint),
        "correct": correct,
        "total": total,
        "accuracy_percent": 100.0 * correct / total,
        "requantization_fractional_bits": 24,
        "width_profile": profile,
        "ranges": tracker.report(),
        "saturations": tracker.saturations,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"integer_accuracy={result['accuracy_percent']:.2f}% ({correct}/{total})")
    print("observed_ranges:")
    for name, values in result["ranges"].items():
        print(
            f"  {name:28s} min={values['min']:9d} max={values['max']:9d} "
            f"signed_bits={values['signed_bits']}"
        )
    print("saturations:")
    for name, count in result["saturations"].items():
        print(f"  {name:28s} count={count}")
    print(f"report={args.report}")


if __name__ == "__main__":
    main()
