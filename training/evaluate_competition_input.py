"""Evaluate the exported integer model on the competition's 1000-image stream."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch

from evaluate_export import exported_forward, load_hex_tensor, load_tensor
from integer_inference import RangeTracker


PIXELS_PER_IMAGE = 28 * 28


def load_hex_pixels(path: Path) -> np.ndarray:
    tokens = path.read_text(encoding="ascii").split()
    values = np.fromiter((int(token, 16) for token in tokens), dtype=np.int64)
    if values.size % PIXELS_PER_IMAGE:
        raise ValueError(
            f"{path} contains {values.size} pixels; expected a multiple of {PIXELS_PER_IMAGE}"
        )
    if values.size == 0 or values.min() < 0 or values.max() > 255:
        raise ValueError(f"{path} contains values outside unsigned INT8")
    return values.reshape(-1, 1, 28, 28)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--export-dir",
        type=Path,
        default=Path(__file__).parent / "export" / "qat_winograd3x3_97",
    )
    parser.add_argument(
        "--input-file",
        type=Path,
        default=Path(__file__).parent.parent / "data" / "input_1000.txt",
    )
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

    pixel_codes = load_hex_pixels(args.input_file)
    images = torch.from_numpy(pixel_codes.copy()).to(torch.float32).div_(255.0)
    labels = torch.arange(images.shape[0], dtype=torch.int64) % 10

    tracker = RangeTracker()
    prediction_batches: list[torch.Tensor] = []
    with torch.inference_mode():
        for offset in range(0, images.shape[0], args.batch_size):
            logits = exported_forward(
                images[offset : offset + args.batch_size], tensors, manifest, tracker
            )
            prediction_batches.append(logits.argmax(dim=1))
    predictions = torch.cat(prediction_batches)
    correct = int((predictions == labels).sum())

    np.savetxt(
        args.export_dir / "competition_predictions_1000.txt", predictions.numpy(), fmt="%d"
    )
    np.savetxt(args.export_dir / "competition_labels_1000.txt", labels.numpy(), fmt="%d")
    result = {
        "input_file": str(args.input_file),
        "image_count": int(images.shape[0]),
        "pixels_per_image": PIXELS_PER_IMAGE,
        "pixel_count": int(pixel_codes.size),
        "pixel_order": "image,row,column (row-major)",
        "label_rule": "image_index_modulo_10",
        "accuracy_percent": 100.0 * correct / images.shape[0],
        "correct": correct,
        "total": int(images.shape[0]),
        "hex_decimal_value_mismatches": hex_decimal_mismatches,
        "observed_ranges": tracker.report(),
        "saturations": tracker.saturations,
    }
    report_path = args.export_dir / "competition_1000_report.json"
    report_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(f"competition_accuracy={result['accuracy_percent']:.2f}% ({correct}/{images.shape[0]})")
    print(f"images={images.shape[0]} pixels_per_image={PIXELS_PER_IMAGE}")
    print(f"hex_decimal_value_mismatches={hex_decimal_mismatches}")
    print(f"report={report_path}")


if __name__ == "__main__":
    main()
