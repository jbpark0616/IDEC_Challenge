"""Evaluate only the exported TXT/JSON package and compare it with its checkpoint."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
from torch.nn import functional as F
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

from integer_inference import (
    INT18_PROFILE,
    RangeTracker,
    integer_forward,
    integer_winograd_conv2d,
    quantize_code,
    requantize_unsigned,
)
from models import QATWinograd3x3


def load_tensor(export_dir: Path, specification: dict[str, object]) -> torch.Tensor:
    path = export_dir / str(specification["decimal_file"])
    flat = np.loadtxt(path, dtype=np.int64).reshape(-1)
    shape = tuple(int(value) for value in specification["shape"])
    expected = int(np.prod(shape))
    if flat.size != expected:
        raise ValueError(f"{path} contains {flat.size} values; expected {expected}")
    return torch.from_numpy(flat.reshape(shape).copy()).to(torch.int64)


def load_hex_tensor(export_dir: Path, specification: dict[str, object]) -> torch.Tensor:
    path = export_dir / str(specification["hex_file"])
    bits = int(specification["bits"])
    unsigned = np.array(
        [int(token, 16) for token in path.read_text(encoding="ascii").split()], dtype=np.int64
    )
    sign = 1 << (bits - 1)
    signed = np.where(unsigned >= sign, unsigned - (1 << bits), unsigned)
    shape = tuple(int(value) for value in specification["shape"])
    return torch.from_numpy(signed.reshape(shape).copy()).to(torch.int64)


@torch.inference_mode()
def exported_forward(
    images: torch.Tensor,
    tensors: dict[str, torch.Tensor],
    manifest: dict[str, object],
    tracker: RangeTracker,
    profile: dict[str, int] | None = None,
) -> torch.Tensor:
    scales = manifest["scales"]
    requantization = manifest["requantization"]
    if profile is None:
        profile = {
            "v": 11,
            "product": 18,
            "m": 18,
            "y": 18,
            "fc_product": 18,
            "fc_acc": 18,
        }

    x = quantize_code(images, float(scales["input"]), 0, 255)
    x, scale = integer_winograd_conv2d(
        x,
        tensors["conv1_u"],
        tensors["conv1_bias"],
        float(scales["conv1_output_accumulator"]),
        tracker,
        "conv1",
        profile,
    )
    x = F.max_pool2d(x.clamp_min(0), 2)
    x = requantize_unsigned(
        x,
        scale,
        float(scales["activation1"]),
        shift=int(requantization["fractional_bits"]),
    )
    x, scale = integer_winograd_conv2d(
        x,
        tensors["conv2_u"],
        tensors["conv2_bias"],
        float(scales["conv2_output_accumulator"]),
        tracker,
        "conv2",
        profile,
    )
    x = F.max_pool2d(x.clamp_min(0), 2)
    x = requantize_unsigned(
        x,
        scale,
        float(scales["activation2"]),
        shift=int(requantization["fractional_bits"]),
    )
    x = torch.flatten(x, 1)
    products = tracker.saturate("fc.product", x[:, None, :] * tensors["fc_weight"][None], 18)
    logits = torch.zeros_like(products[:, :, 0])
    for element in range(products.shape[2]):
        logits = tracker.saturate("fc.acc_add", logits + products[:, :, element], 18)
    return tracker.saturate("fc.bias_add", logits + tensors["fc_bias"], 18)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--export-dir",
        type=Path,
        default=Path(__file__).parent / "export" / "qat_winograd3x3_97",
    )
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).parent / "data")
    parser.add_argument("--batch-size", type=int, default=256)
    args = parser.parse_args()

    manifest = json.loads((args.export_dir / "manifest.json").read_text(encoding="utf-8"))
    tensors = {
        name: load_tensor(args.export_dir, specification)
        for name, specification in manifest["tensors"].items()
    }
    hex_decimal_mismatches = sum(
        int((tensors[name] != load_hex_tensor(args.export_dir, specification)).sum())
        for name, specification in manifest["tensors"].items()
    )
    if hex_decimal_mismatches:
        raise ValueError(f"HEX and signed-decimal exports differ at {hex_decimal_mismatches} values")
    saved = torch.load(Path(manifest["source_checkpoint"]), map_location="cpu", weights_only=False)
    weight_bits = int(manifest["widths"]["winograd_u_signed"])
    checkpoint_model = QATWinograd3x3(weight_bits=weight_bits).eval()
    checkpoint_model.load_float_state_dict(saved["model"])

    test_set = datasets.MNIST(
        args.data_dir, train=False, download=False, transform=transforms.ToTensor()
    )
    loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False)
    artifact_tracker = RangeTracker()
    reference_tracker = RangeTracker()
    correct = 0
    prediction_mismatches = 0
    logit_mismatches = 0
    predictions: list[torch.Tensor] = []
    labels_all: list[torch.Tensor] = []
    for images, labels in loader:
        artifact_logits = exported_forward(images, tensors, manifest, artifact_tracker)
        reference_logits = integer_forward(
            checkpoint_model, images, reference_tracker, INT18_PROFILE
        )
        artifact_prediction = artifact_logits.argmax(dim=1)
        reference_prediction = reference_logits.argmax(dim=1)
        correct += int((artifact_prediction == labels).sum())
        prediction_mismatches += int((artifact_prediction != reference_prediction).sum())
        logit_mismatches += int((artifact_logits != reference_logits).sum())
        predictions.append(artifact_prediction)
        labels_all.append(labels)

    predictions_tensor = torch.cat(predictions).numpy()
    labels_tensor = torch.cat(labels_all).numpy()
    np.savetxt(args.export_dir / "predictions_10000.txt", predictions_tensor, fmt="%d")
    np.savetxt(args.export_dir / "labels_10000.txt", labels_tensor, fmt="%d")
    total = len(test_set)
    result = {
        "accuracy_percent": 100.0 * correct / total,
        "correct": correct,
        "total": total,
        "prediction_mismatches_vs_checkpoint": prediction_mismatches,
        "logit_element_mismatches_vs_checkpoint": logit_mismatches,
        "hex_decimal_value_mismatches": hex_decimal_mismatches,
    }
    report_path = args.export_dir / "roundtrip_report.json"
    report_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"export_accuracy={result['accuracy_percent']:.2f}% ({correct}/{total})")
    print(f"prediction_mismatches={prediction_mismatches}")
    print(f"logit_element_mismatches={logit_mismatches}")
    print(f"hex_decimal_value_mismatches={hex_decimal_mismatches}")
    print(f"report={report_path}")


if __name__ == "__main__":
    main()
