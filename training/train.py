"""Train either the official 5x5 baseline or the float 3x3 candidate."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
from torch import nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

from models import Baseline5x5, QATWinograd3x3, Spatial3x3, Winograd3x3
from quantization import FakeQuantizer


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        choices=("baseline5x5", "spatial3x3", "winograd3x3", "qat_winograd3x3"),
        default="baseline5x5",
    )
    parser.add_argument("--epochs", type=int, default=9)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).parent / "data")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).parent / "runs")
    parser.add_argument("--init-checkpoint", type=Path)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--optimizer", choices=("sgd", "adam"), default="sgd")
    parser.add_argument("--lr", type=float)
    parser.add_argument("--momentum", type=float, default=0.5)
    parser.add_argument(
        "--lr-milestones",
        type=str,
        default="",
        help="Comma-separated epochs after which to decay the learning rate",
    )
    parser.add_argument("--lr-gamma", type=float, default=0.1)
    parser.add_argument("--run-name", type=str)
    parser.add_argument("--weight-bits", type=int, choices=range(2, 9), default=8)
    parser.add_argument("--augment", action="store_true")
    parser.add_argument(
        "--freeze-observers-after",
        type=int,
        help="Disable all fake-quant observers after this many completed epochs; 0 freezes immediately.",
    )
    return parser.parse_args()


@torch.inference_mode()
def evaluate(model: nn.Module, loader: DataLoader) -> tuple[float, float]:
    model.eval()
    loss_sum = 0.0
    correct = 0
    for images, labels in loader:
        logits = model(images)
        loss_sum += nn.functional.cross_entropy(logits, labels, reduction="sum").item()
        correct += (logits.argmax(dim=1) == labels).sum().item()
    return loss_sum / len(loader.dataset), correct / len(loader.dataset)


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    test_transform = transforms.ToTensor()
    train_transform = test_transform
    if args.augment:
        train_transform = transforms.Compose(
            [transforms.RandomAffine(degrees=5, translate=(0.05, 0.05)), transforms.ToTensor()]
        )
    train_set = datasets.MNIST(
        args.data_dir, train=True, download=True, transform=train_transform
    )
    test_set = datasets.MNIST(
        args.data_dir, train=False, download=True, transform=test_transform
    )
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True)
    test_loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False)

    model_types = {
        "baseline5x5": Baseline5x5,
        "spatial3x3": Spatial3x3,
        "winograd3x3": Winograd3x3,
        "qat_winograd3x3": lambda: QATWinograd3x3(weight_bits=args.weight_bits),
    }
    if args.model != "qat_winograd3x3" and args.weight_bits != 8:
        raise ValueError("--weight-bits is only valid for qat_winograd3x3")
    model = model_types[args.model]()
    if args.init_checkpoint is not None:
        saved = torch.load(args.init_checkpoint, map_location="cpu", weights_only=False)
        if isinstance(model, QATWinograd3x3):
            model.load_float_state_dict(saved["model"])
            source_bits = int(saved.get("args", {}).get("weight_bits", 8))
            if source_bits != args.weight_bits:
                model.reset_weight_observers()
                print(f"reset_weight_observers={source_bits}bit_to_{args.weight_bits}bit")
        else:
            model.load_state_dict(saved["model"])
        print(f"initialized_from={args.init_checkpoint}")
    learning_rate = args.lr if args.lr is not None else (0.01 if args.optimizer == "sgd" else 0.001)
    if args.optimizer == "sgd":
        optimizer = torch.optim.SGD(model.parameters(), lr=learning_rate, momentum=args.momentum)
    else:
        optimizer = torch.optim.Adam(model.parameters(), lr=learning_rate)

    milestones = [int(value) for value in args.lr_milestones.split(",") if value.strip()]
    scheduler = torch.optim.lr_scheduler.MultiStepLR(
        optimizer, milestones=milestones, gamma=args.lr_gamma
    )

    history: list[dict[str, float | int]] = []
    best_accuracy = -1.0
    run_name = args.run_name or args.model
    checkpoint = args.output_dir / f"{run_name}.pt"
    for epoch in range(1, args.epochs + 1):
        if args.freeze_observers_after is not None and epoch > args.freeze_observers_after:
            for module in model.modules():
                if isinstance(module, FakeQuantizer):
                    module.observer_enabled = False
            if epoch == args.freeze_observers_after + 1:
                print(f"observers_frozen_before_epoch={epoch}")
        model.train()
        for images, labels in train_loader:
            optimizer.zero_grad()
            loss = nn.functional.cross_entropy(model(images), labels)
            loss.backward()
            optimizer.step()
        test_loss, accuracy = evaluate(model, test_loader)
        current_lr = optimizer.param_groups[0]["lr"]
        history.append(
            {"epoch": epoch, "test_loss": test_loss, "accuracy": accuracy, "lr": current_lr}
        )
        print(
            f"epoch={epoch:02d} lr={current_lr:.6g} "
            f"test_loss={test_loss:.4f} accuracy={accuracy * 100:.2f}%",
            flush=True,
        )
        if accuracy > best_accuracy:
            best_accuracy = accuracy
            torch.save(
                {
                    "model": model.state_dict(),
                    "args": vars(args),
                    "epoch": epoch,
                    "accuracy": accuracy,
                },
                checkpoint,
            )
        scheduler.step()

    history_path = args.output_dir / f"{run_name}_history.json"
    history_path.write_text(json.dumps(history, indent=2), encoding="utf-8")
    print(f"best_accuracy={best_accuracy * 100:.2f}% saved={checkpoint}")
    print(f"history={history_path}")


if __name__ == "__main__":
    main()
