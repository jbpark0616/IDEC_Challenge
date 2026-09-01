"""Generate the publication figure for the final W4A8 compute-width sweep."""

from __future__ import annotations

import csv
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import LogNorm


ROOT = Path(__file__).resolve().parents[2]
RUNS = ROOT / "training" / "runs"
OUTPUT = ROOT / "docs" / "figures"
DATA_OUTPUT = ROOT / "docs" / "numerical_precision"
WIDTHS = [18, 17, 16, 15, 14, 13, 12]


def load_report(width: int) -> dict:
    path = RUNS / f"integer_inference_w4_int{width}.json"
    return json.loads(path.read_text(encoding="utf-8"))


def block_saturations(report: dict) -> list[int]:
    events = report["saturations"]
    return [
        sum(value for key, value in events.items() if key.startswith(prefix))
        for prefix in ("conv1.", "conv2.", "fc.")
    ]


def compact_count(value: int) -> str:
    if value == 0:
        return "0"
    if value >= 1_000_000:
        return f"{value / 1_000_000:.2f}M"
    if value >= 1_000:
        return f"{value / 1_000:.1f}k"
    return str(value)


def main() -> None:
    reports = [load_report(width) for width in WIDTHS]
    accuracy = np.array([report["accuracy_percent"] for report in reports])
    saturation = np.array([block_saturations(report) for report in reports], dtype=np.int64)

    plt.rcParams.update(
        {
            "font.family": "serif",
            "font.size": 8,
            "axes.labelsize": 8,
            "axes.linewidth": 0.7,
            "xtick.labelsize": 7,
            "ytick.labelsize": 7,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "svg.fonttype": "none",
        }
    )

    blue = "#2B5C8A"
    red = "#A73030"
    gray = "#666666"
    light_gray = "#D6D6D6"

    figure, (accuracy_axis, saturation_axis) = plt.subplots(
        1, 2, figsize=(7.2, 2.75), gridspec_kw={"width_ratios": (1.05, 1.0)}
    )

    plot_widths = np.array(WIDTHS)
    accuracy_axis.plot(plot_widths, accuracy, color=blue, linewidth=1.15, zorder=2)
    accuracy_axis.scatter(
        plot_widths,
        accuracy,
        s=28,
        facecolors="white",
        edgecolors=blue,
        linewidths=1.1,
        zorder=3,
    )
    accuracy_axis.scatter([18], [accuracy[0]], s=34, color=blue, zorder=4)
    accuracy_axis.scatter([12], [accuracy[-1]], s=34, color=red, marker="s", zorder=4)
    for width, value in zip(plot_widths, accuracy, strict=True):
        if width in (18, 14, 13, 12):
            accuracy_axis.annotate(
                f"{value:.2f}",
                (width, value),
                xytext=(0, 7 if width != 12 else -12),
                textcoords="offset points",
                ha="center",
                va="bottom" if width != 12 else "top",
                fontsize=7,
                color=red if width == 12 else "black",
            )
    accuracy_axis.axvline(18, color=gray, linewidth=0.75, linestyle=(0, (3, 2)))
    accuracy_axis.text(17.88, 94.05, "current RTL", color=gray, fontsize=6.8, rotation=90)
    accuracy_axis.set_xlim(18.35, 11.65)
    accuracy_axis.set_ylim(93.2, 96.7)
    accuracy_axis.set_xticks(plot_widths)
    accuracy_axis.set_xlabel("Compute width (bit)")
    accuracy_axis.set_ylabel("MNIST test accuracy (%)")
    accuracy_axis.grid(axis="y", color=light_gray, linewidth=0.45)
    accuracy_axis.spines["top"].set_visible(False)
    accuracy_axis.spines["right"].set_visible(False)

    display = saturation.astype(float)
    display[display == 0] = 0.5
    image = saturation_axis.imshow(
        display,
        cmap="Blues",
        norm=LogNorm(vmin=0.5, vmax=max(1.0, float(display.max()))),
        aspect="auto",
    )
    saturation_axis.set_xticks(np.arange(3), ["Conv1", "Conv2", "FC"])
    saturation_axis.set_yticks(np.arange(len(WIDTHS)), [f"{width} bit" for width in WIDTHS])
    saturation_axis.set_xlabel("Compute block")
    for row in range(len(WIDTHS)):
        for column in range(3):
            value = int(saturation[row, column])
            color = "white" if value > 0.12 * saturation.max() else "black"
            saturation_axis.text(
                column,
                row,
                compact_count(value),
                ha="center",
                va="center",
                fontsize=6.8,
                color=color,
            )
    for spine in saturation_axis.spines.values():
        spine.set_linewidth(0.55)
    colorbar = figure.colorbar(image, ax=saturation_axis, fraction=0.046, pad=0.04)
    colorbar.set_label("Saturation events", fontsize=7)
    colorbar.ax.tick_params(labelsize=6)

    figure.text(0.27, 0.01, "(a) Accuracy", ha="center", va="bottom", fontsize=8)
    figure.text(0.75, 0.01, "(b) Saturation events", ha="center", va="bottom", fontsize=8)
    figure.subplots_adjust(left=0.09, right=0.96, top=0.96, bottom=0.22, wspace=0.38)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    DATA_OUTPUT.mkdir(parents=True, exist_ok=True)
    for suffix in ("png", "pdf", "svg"):
        figure.savefig(
            OUTPUT / f"winograd_w4_compute_width_sweep.{suffix}",
            dpi=300 if suffix == "png" else None,
            bbox_inches="tight",
            facecolor="white",
        )
    plt.close(figure)

    with (DATA_OUTPUT / "w4_compute_width_sweep.csv").open(
        "w", newline="", encoding="utf-8"
    ) as file:
        writer = csv.writer(file)
        writer.writerow(["compute_bits", "accuracy_percent", "conv1_saturation", "conv2_saturation", "fc_saturation"])
        for width, value, counts in zip(WIDTHS, accuracy, saturation, strict=True):
            writer.writerow([width, f"{value:.2f}", *map(int, counts)])

    print(f"saved={OUTPUT / 'winograd_w4_compute_width_sweep.svg'}")
    print(f"saved={DATA_OUTPUT / 'w4_compute_width_sweep.csv'}")


if __name__ == "__main__":
    main()
