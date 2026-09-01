"""Evaluate a saved checkpoint on the complete MNIST test set."""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

from models import Baseline5x5, QATWinograd3x3, Spatial3x3, Winograd3x3
from train import evaluate


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        required=True,
        choices=("baseline5x5", "spatial3x3", "winograd3x3", "qat_winograd3x3"),
    )
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).parent / "data")
    parser.add_argument("--batch-size", type=int, default=256)
    args = parser.parse_args()

    saved = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    weight_bits = int(saved.get("args", {}).get("weight_bits", 8))
    model_types = {
        "baseline5x5": Baseline5x5,
        "spatial3x3": Spatial3x3,
        "winograd3x3": Winograd3x3,
        "qat_winograd3x3": lambda: QATWinograd3x3(weight_bits=weight_bits),
    }
    model = model_types[args.model]()
    if isinstance(model, QATWinograd3x3):
        model.load_float_state_dict(saved["model"])
    else:
        model.load_state_dict(saved["model"])

    test_set = datasets.MNIST(
        args.data_dir, train=False, download=False, transform=transforms.ToTensor()
    )
    test_loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False)
    test_loss, accuracy = evaluate(model, test_loader)
    print(f"checkpoint={args.checkpoint}")
    print(f"saved_epoch={saved.get('epoch', 'unknown')}")
    print(f"test_loss={test_loss:.4f} accuracy={accuracy * 100:.2f}%")

    if isinstance(model, QATWinograd3x3):
        print("quantization_scales:")
        for name, module in model.named_modules():
            if hasattr(module, "scale"):
                print(f"  {name}={module.scale.item():.10g}")


if __name__ == "__main__":
    main()
