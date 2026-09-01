"""Export a trained QAT checkpoint as a self-describing integer model package."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch

from integer_inference import INT18_PROFILE
from models import QATWinograd3x3
from winograd import transform_weights


def write_decimal(path: Path, tensor: torch.Tensor, columns: int) -> None:
    values = tensor.detach().cpu().to(torch.int64).numpy().reshape(-1, columns)
    np.savetxt(path, values, fmt="%d")


def write_float(path: Path, tensor: torch.Tensor, columns: int) -> None:
    values = tensor.detach().cpu().to(torch.float64).numpy().reshape(-1, columns)
    np.savetxt(path, values, fmt="%.10e")


def write_hex(path: Path, tensor: torch.Tensor, columns: int, bits: int) -> None:
    mask = (1 << bits) - 1
    digits = (bits + 3) // 4
    values = tensor.detach().cpu().to(torch.int64).numpy().reshape(-1, columns)
    with path.open("w", encoding="ascii", newline="\n") as output:
        for row in values:
            output.write(" ".join(f"{int(value) & mask:0{digits}x}" for value in row))
            output.write("\n")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--checkpoint",
        type=Path,
        default=Path(__file__).parent / "runs" / "qat_winograd3x3_97.pt",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).parent / "export" / "qat_winograd3x3_97",
    )
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    weight_bits = int(saved.get("args", {}).get("weight_bits", 8))
    model = QATWinograd3x3(weight_bits=weight_bits).eval()
    model.load_float_state_dict(saved["model"])

    input_scale = float(model.input_quant.scale)
    activation1_scale = float(model.activation1_quant.scale)
    activation2_scale = float(model.activation2_quant.scale)
    conv1_u_scale = float(model.conv1.u_quant.scale)
    conv2_u_scale = float(model.conv2.u_quant.scale)
    fc_weight_scale = float(model.fc.weight_quant.scale)

    conv1_u = model.conv1.u_quant.integer(transform_weights(model.conv1.weight))
    conv2_u = model.conv2.u_quant.integer(transform_weights(model.conv2.weight))
    fc_weight = model.fc.weight_quant.integer(model.fc.weight)
    conv1_output_scale = input_scale * conv1_u_scale
    conv2_output_scale = activation1_scale * conv2_u_scale
    fc_output_scale = activation2_scale * fc_weight_scale
    conv1_bias = torch.round(model.conv1.bias.detach() / conv1_output_scale).to(torch.int64)
    conv2_bias = torch.round(model.conv2.bias.detach() / conv2_output_scale).to(torch.int64)
    fc_bias = torch.round(model.fc.bias.detach() / fc_output_scale).to(torch.int64)

    tensors = {
        "conv1_u": (conv1_u, [3, 1, 4, 4], 4, weight_bits),
        "conv1_bias": (conv1_bias, [3], 1, 16),
        "conv2_u": (conv2_u, [3, 3, 4, 4], 4, weight_bits),
        "conv2_bias": (conv2_bias, [3], 1, 16),
        "fc_weight": (fc_weight, [10, 75], 75, weight_bits),
        "fc_bias": (fc_bias, [10], 1, 16),
    }
    tensor_manifest: dict[str, dict[str, object]] = {}
    generated_files: list[Path] = []
    for name, (tensor, shape, columns, bits) in tensors.items():
        decimal_path = args.output_dir / f"{name}_signed.txt"
        hex_path = args.output_dir / f"{name}_twos_complement.hex"
        write_decimal(decimal_path, tensor, columns)
        write_hex(hex_path, tensor, columns, bits)
        generated_files.extend((decimal_path, hex_path))
        tensor_manifest[name] = {
            "shape": shape,
            "order": "row-major",
            "signed": True,
            "bits": bits,
            "decimal_file": decimal_path.name,
            "hex_file": hex_path.name,
        }

    # Spatial master weights are retained for training traceability, not inference.
    for name, tensor in (("conv1_g_fp32", model.conv1.weight), ("conv2_g_fp32", model.conv2.weight)):
        path = args.output_dir / f"{name}.txt"
        write_float(path, tensor, 3)
        generated_files.append(path)

    fractional_bits = 24
    conv1_multiplier = round((conv1_output_scale / activation1_scale) * (1 << fractional_bits))
    conv2_multiplier = round((conv2_output_scale / activation2_scale) * (1 << fractional_bits))
    manifest = {
        "format_version": 1,
        "model": f"QATWinograd3x3W{weight_bits}",
        "source_checkpoint": str(args.checkpoint),
        "source_checkpoint_epoch": saved.get("epoch"),
        "source_checkpoint_accuracy_percent": 100.0 * float(saved.get("accuracy", 0.0)),
        "tensor_order": {
            "activation": "NCHW",
            "winograd_u": "output_channel,input_channel,row,column",
            "fc_weight": "output_class,input_feature",
            "flatten": "channel,row,column",
        },
        "widths": {
            "input_activation_unsigned": 8,
            "stored_activation_unsigned": 8,
            "winograd_u_signed": weight_bits,
            "winograd_v_signed": 11,
            "compute_signed": 18,
            "bias_storage_signed": 16,
            "fc_weight_signed": weight_bits,
        },
        "scales": {
            "input": input_scale,
            "conv1_u": conv1_u_scale,
            "conv1_output_accumulator": conv1_output_scale,
            "activation1": activation1_scale,
            "conv2_u": conv2_u_scale,
            "conv2_output_accumulator": conv2_output_scale,
            "activation2": activation2_scale,
            "fc_weight": fc_weight_scale,
            "fc_output_accumulator": fc_output_scale,
        },
        "requantization": {
            "rounding": "add_half_then_arithmetic_right_shift_for_nonnegative_relu_output",
            "saturation": "unsigned_8bit_0_to_255",
            "fractional_bits": fractional_bits,
            "conv1_multiplier": conv1_multiplier,
            "conv2_multiplier": conv2_multiplier,
        },
        "signed_overflow": "saturate",
        "integer_rounding": "round_to_nearest_ties_to_even",
        "tensors": tensor_manifest,
        "files_sha256": {path.name: sha256(path) for path in generated_files},
    }
    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"exported={args.output_dir}")
    print(f"manifest={manifest_path}")


if __name__ == "__main__":
    main()
