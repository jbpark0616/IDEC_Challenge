"""Sweep aggressive integer formats on the official 1000-image competition set."""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

import torch
from torchvision import datasets, transforms

from evaluate_competition_input import load_hex_pixels
from evaluate_export import exported_forward, load_tensor
from integer_inference import RangeTracker


CASES = [
    {"name": "baseline", "u": 8, "v": 11, "compute": 18, "bias": 16},
    {"name": "compute17", "u": 8, "v": 11, "compute": 17, "bias": 16},
    {"name": "compute16", "u": 8, "v": 11, "compute": 16, "bias": 16},
    {"name": "v10", "u": 8, "v": 10, "compute": 18, "bias": 16},
    {"name": "v9", "u": 8, "v": 9, "compute": 18, "bias": 16},
    {"name": "u7", "u": 7, "v": 11, "compute": 18, "bias": 16},
    {"name": "u6", "u": 6, "v": 11, "compute": 18, "bias": 16},
    {"name": "u5", "u": 5, "v": 11, "compute": 18, "bias": 16},
    {"name": "u4", "u": 4, "v": 11, "compute": 18, "bias": 16},
    {"name": "bias14", "u": 8, "v": 11, "compute": 18, "bias": 14},
    {"name": "bias13", "u": 8, "v": 11, "compute": 18, "bias": 13},
    {"name": "bias12", "u": 8, "v": 11, "compute": 18, "bias": 12},
    {"name": "fc7", "u": 8, "v": 11, "compute": 18, "bias": 16, "fc": 7},
    {"name": "fc6", "u": 8, "v": 11, "compute": 18, "bias": 16, "fc": 6},
    {"name": "fc5", "u": 8, "v": 11, "compute": 18, "bias": 16, "fc": 5},
    {"name": "fc4", "u": 8, "v": 11, "compute": 18, "bias": 16, "fc": 4},
    {
        "name": "combined_u4_fc4_c18_b16",
        "u": 4,
        "v": 11,
        "compute": 18,
        "bias": 16,
        "fc": 4,
    },
    {"name": "combined_7_10_17_14", "u": 7, "v": 10, "compute": 17, "bias": 14},
    {"name": "combined_6_10_17_13", "u": 6, "v": 10, "compute": 17, "bias": 13},
    {
        "name": "combined_u7_fc7_c17_b14",
        "u": 7,
        "v": 11,
        "compute": 17,
        "bias": 14,
        "fc": 7,
    },
    {
        "name": "combined_u6_fc6_c17_b14",
        "u": 6,
        "v": 11,
        "compute": 17,
        "bias": 14,
        "fc": 6,
    },
    {
        "name": "combined_u6_fc6_c17_b13",
        "u": 6,
        "v": 11,
        "compute": 17,
        "bias": 13,
        "fc": 6,
    },
]


def signed_clip(value: torch.Tensor, bits: int) -> torch.Tensor:
    return value.clamp(-(1 << (bits - 1)), (1 << (bits - 1)) - 1)


def requantize_u(
    tensors: dict[str, torch.Tensor], manifest: dict[str, object], bits: int
) -> None:
    if bits == 8:
        return
    qmax = (1 << (bits - 1)) - 1
    scales = manifest["scales"]
    for layer, input_scale_name in (("conv1", "input"), ("conv2", "activation1")):
        u_name = f"{layer}_u"
        bias_name = f"{layer}_bias"
        accumulator_name = f"{layer}_output_accumulator"
        old_u_scale = float(scales[u_name])
        old_accumulator_scale = float(scales[accumulator_name])
        maximum_code = int(tensors[u_name].abs().max())
        new_u_scale = old_u_scale * maximum_code / qmax
        tensors[u_name] = torch.round(
            tensors[u_name].to(torch.float64) * old_u_scale / new_u_scale
        ).to(torch.int64).clamp(-qmax, qmax)
        new_accumulator_scale = float(scales[input_scale_name]) * new_u_scale
        tensors[bias_name] = torch.round(
            tensors[bias_name].to(torch.float64)
            * old_accumulator_scale
            / new_accumulator_scale
        ).to(torch.int64)
        scales[u_name] = new_u_scale
        scales[accumulator_name] = new_accumulator_scale


def requantize_fc(
    tensors: dict[str, torch.Tensor], manifest: dict[str, object], bits: int
) -> None:
    if bits == 8:
        return
    qmax = (1 << (bits - 1)) - 1
    scales = manifest["scales"]
    old_weight_scale = float(scales["fc_weight"])
    old_accumulator_scale = float(scales["fc_output_accumulator"])
    maximum_code = int(tensors["fc_weight"].abs().max())
    new_weight_scale = old_weight_scale * maximum_code / qmax
    tensors["fc_weight"] = torch.round(
        tensors["fc_weight"].to(torch.float64) * old_weight_scale / new_weight_scale
    ).to(torch.int64).clamp(-qmax, qmax)
    new_accumulator_scale = float(scales["activation2"]) * new_weight_scale
    tensors["fc_bias"] = torch.round(
        tensors["fc_bias"].to(torch.float64)
        * old_accumulator_scale
        / new_accumulator_scale
    ).to(torch.int64)
    scales["fc_weight"] = new_weight_scale
    scales["fc_output_accumulator"] = new_accumulator_scale


@torch.inference_mode()
def evaluate_case(
    images: torch.Tensor,
    labels: torch.Tensor,
    base_tensors: dict[str, torch.Tensor],
    base_manifest: dict[str, object],
    case: dict[str, int | str],
    batch_size: int,
) -> dict[str, object]:
    tensors = {name: value.clone() for name, value in base_tensors.items()}
    manifest = copy.deepcopy(base_manifest)
    requantize_u(tensors, manifest, int(case["u"]))
    requantize_fc(tensors, manifest, int(case.get("fc", 8)))
    bias_clipped_values = 0
    for name in ("conv1_bias", "conv2_bias", "fc_bias"):
        clipped = signed_clip(tensors[name], int(case["bias"]))
        bias_clipped_values += int((clipped != tensors[name]).sum())
        tensors[name] = clipped

    compute = int(case["compute"])
    profile = {
        "v": int(case["v"]),
        "product": compute,
        "m": compute,
        "y": compute,
        "fc_product": compute,
        "fc_acc": compute,
    }
    tracker = RangeTracker()
    predictions: list[torch.Tensor] = []
    for offset in range(0, images.shape[0], batch_size):
        logits = exported_forward(
            images[offset : offset + batch_size], tensors, manifest, tracker, profile
        )
        predictions.append(logits.argmax(dim=1))
    prediction = torch.cat(predictions)
    correct = int((prediction == labels).sum())
    return {
        **case,
        "accuracy_percent": 100.0 * correct / images.shape[0],
        "correct": correct,
        "total": int(images.shape[0]),
        "saturations": int(sum(tracker.saturations.values())),
        "saturations_by_stage": tracker.saturations,
        "bias_clipped_values": bias_clipped_values,
        "u_ranges": {
            "conv1": [int(tensors["conv1_u"].min()), int(tensors["conv1_u"].max())],
            "conv2": [int(tensors["conv2_u"].min()), int(tensors["conv2_u"].max())],
        },
    }


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
    parser.add_argument(
        "--dataset", choices=("competition", "mnist"), default="competition"
    )
    parser.add_argument(
        "--mnist-data-dir", type=Path, default=Path(__file__).parent / "data"
    )
    parser.add_argument(
        "--case",
        action="append",
        dest="case_names",
        help="Evaluate only the named case; may be supplied more than once.",
    )
    args = parser.parse_args()

    manifest = json.loads((args.export_dir / "manifest.json").read_text(encoding="utf-8"))
    tensors = {
        name: load_tensor(args.export_dir, specification)
        for name, specification in manifest["tensors"].items()
    }
    if args.dataset == "competition":
        pixels = load_hex_pixels(args.input_file)
        images = torch.from_numpy(pixels.copy()).to(torch.float32).div_(255.0)
        labels = torch.arange(images.shape[0], dtype=torch.int64) % 10
        dataset_name = str(args.input_file)
        output_name = "competition_bitwidth_sweep.json"
    else:
        test_set = datasets.MNIST(
            args.mnist_data_dir, train=False, download=False, transform=transforms.ToTensor()
        )
        images = torch.stack([test_set[index][0] for index in range(len(test_set))])
        labels = torch.tensor([test_set[index][1] for index in range(len(test_set))])
        dataset_name = f"MNIST test set at {args.mnist_data_dir}"
        output_name = "mnist_bitwidth_sweep.json"

    results = []
    selected_cases = CASES
    if args.case_names:
        selected_cases = [case for case in CASES if case["name"] in args.case_names]
        missing = sorted(set(args.case_names) - {str(case["name"]) for case in selected_cases})
        if missing:
            raise ValueError(f"unknown case name(s): {', '.join(missing)}")
    for case in selected_cases:
        result = evaluate_case(images, labels, tensors, manifest, case, args.batch_size)
        results.append(result)
        print(
            f"{result['name']:<24} {result['accuracy_percent']:6.2f}% "
            f"({result['correct']}/{result['total']}) sat={result['saturations']}"
        )

    output = {
        "dataset": dataset_name,
        "note": "U-bit cases recalibrate one symmetric per-layer U scale without retraining.",
        "results": results,
    }
    output_path = args.export_dir / output_name
    output_path.write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(f"report={output_path}")


if __name__ == "__main__":
    main()
