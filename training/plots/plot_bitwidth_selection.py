"""Generate the report figure supporting the selected 18-bit datapath."""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import MultipleLocator


ROOT = Path(__file__).resolve().parents[2]
RUNS = ROOT / "training" / "runs"
OUTPUT = ROOT / "docs" / "figures"
COMPETITION_BASELINE = 96.0


def best_history(name: str) -> float:
    history = json.loads((RUNS / name).read_text(encoding="utf-8"))
    return 100.0 * max(item["accuracy"] for item in history)


def integer_accuracy(name: str) -> float:
    report = json.loads((RUNS / name).read_text(encoding="utf-8"))
    return float(report["accuracy_percent"])


def saturation_counts(name: str) -> list[int]:
    report = json.loads((RUNS / name).read_text(encoding="utf-8"))
    events = report["saturations"]
    return [
        sum(count for key, count in events.items() if key.startswith(prefix))
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
    fp32 = best_history("spatial3x3_97_history.json")
    qat = best_history("qat_winograd3x3_97_history.json")
    integer = integer_accuracy("integer_inference_97.json")
    int18 = integer_accuracy("integer_inference_int18.json")
    int17 = integer_accuracy("integer_inference_int17.json")
    int16 = integer_accuracy("integer_inference_int16.json")

    plt.rcParams.update(
        {
            "font.family": "serif",
            "font.size": 8,
            "axes.titlesize": 9,
            "axes.labelsize": 8,
            "axes.linewidth": 0.7,
            "xtick.labelsize": 7,
            "ytick.labelsize": 7,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )

    blue = "#2B5C8A"
    red = "#A73030"
    gray = "#666666"
    light_gray = "#D6D6D6"

    figure = plt.figure(figsize=(7.2, 3.55), constrained_layout=True)
    grid_spec = figure.add_gridspec(2, 2, width_ratios=(1.45, 1.0), height_ratios=(1.15, 1.0))
    stage_axis = figure.add_subplot(grid_spec[:, 0])
    width_axis = figure.add_subplot(grid_spec[0, 1])
    heat_axis = figure.add_subplot(grid_spec[1, 1])

    # (a) Sequential numerical refinement is better represented as a trajectory.
    stage_names = ["Official\nbaseline", "FP32\n3x3", "Winograd\nQAT", "Integer\ngolden", "INT18\nlimited"]
    stage_values = [COMPETITION_BASELINE, fp32, qat, integer, int18]
    stage_x = np.arange(len(stage_names))
    stage_axis.plot(stage_x, stage_values, color=blue, linewidth=1.2, zorder=2)
    stage_axis.scatter(
        stage_x,
        stage_values,
        s=31,
        facecolors="white",
        edgecolors=blue,
        linewidths=1.2,
        zorder=3,
    )
    stage_axis.axhline(
        COMPETITION_BASELINE, color=gray, linewidth=0.8, linestyle=(0, (3, 2)), zorder=1
    )
    for x_value, accuracy in zip(stage_x, stage_values, strict=True):
        stage_axis.annotate(
            f"{accuracy:.2f}",
            (x_value, accuracy),
            xytext=(0, 7),
            textcoords="offset points",
            ha="center",
            fontsize=7,
        )
    stage_axis.set_xticks(stage_x, stage_names)
    stage_axis.set_ylim(95.78, 97.25)
    stage_axis.set_ylabel("MNIST test accuracy (%)")
    stage_axis.set_title("(a) Numerical refinement", loc="left")
    stage_axis.yaxis.set_major_locator(MultipleLocator(0.25))
    stage_axis.grid(axis="y", color=light_gray, linewidth=0.45)
    stage_axis.text(
        0.02,
        0.04,
        "official baseline = 96.0%",
        transform=stage_axis.transAxes,
        color=gray,
        fontsize=6.8,
    )

    # (b) Absolute accuracy makes the 16-bit cliff unambiguous.
    widths = np.array([18, 17, 16])
    width_values = np.array([int18, int17, int16])
    width_axis.plot(widths, width_values, color=blue, linewidth=1.1, zorder=2)
    width_axis.scatter(widths[:2], width_values[:2], s=30, color=blue, zorder=3)
    width_axis.scatter(widths[2], width_values[2], s=34, color=red, marker="s", zorder=3)
    width_axis.axhline(
        COMPETITION_BASELINE, color=gray, linewidth=0.8, linestyle=(0, (3, 2))
    )
    for width, accuracy in zip(widths, width_values, strict=True):
        width_axis.annotate(
            f"{accuracy:.2f}",
            (width, accuracy),
            xytext=(0, 5 if width != 16 else -10),
            textcoords="offset points",
            ha="center",
            va="bottom" if width != 16 else "top",
            fontsize=7,
            color=red if width == 16 else "black",
        )
    width_axis.set_xlim(18.35, 15.65)
    width_axis.set_ylim(85.5, 98.0)
    width_axis.set_xticks(widths)
    width_axis.set_ylabel("Accuracy (%)")
    width_axis.set_title("(b) Width sensitivity", loc="left")
    width_axis.grid(axis="y", color=light_gray, linewidth=0.45)

    # (c) Saturation counts explain why INT18 is selected over INT17.
    saturation = np.array(
        [
            saturation_counts("integer_inference_int18.json"),
            saturation_counts("integer_inference_int17.json"),
            saturation_counts("integer_inference_int16.json"),
        ],
        dtype=np.int64,
    )
    transformed = np.log10(saturation + 1)
    image = heat_axis.imshow(transformed, cmap="Blues", vmin=0, vmax=max(1, transformed.max()))
    heat_axis.set_xticks(np.arange(3), ["Conv1", "Conv2", "FC"])
    heat_axis.set_yticks(np.arange(3), ["18 bit", "17 bit", "16 bit"])
    heat_axis.set_title("(c) Saturation events", loc="left")
    for row in range(3):
        for column in range(3):
            heat_axis.text(
                column,
                row,
                compact_count(int(saturation[row, column])),
                ha="center",
                va="center",
                fontsize=6.8,
                color="white" if transformed[row, column] > 0.58 * transformed.max() else "black",
            )
    colorbar = figure.colorbar(image, ax=heat_axis, fraction=0.046, pad=0.04)
    colorbar.set_label(r"$\log_{10}(N+1)$", fontsize=7)
    colorbar.ax.tick_params(labelsize=6)

    for axis in (stage_axis, width_axis):
        axis.spines["top"].set_visible(False)
        axis.spines["right"].set_visible(False)
    for spine in heat_axis.spines.values():
        spine.set_linewidth(0.45)

    OUTPUT.mkdir(parents=True, exist_ok=True)
    png = OUTPUT / "winograd_bitwidth_selection.png"
    pdf = OUTPUT / "winograd_bitwidth_selection.pdf"
    figure.savefig(png, dpi=300, bbox_inches="tight", facecolor="white")
    figure.savefig(pdf, bbox_inches="tight", facecolor="white")
    plt.close(figure)
    print(f"saved={png}")
    print(f"saved={pdf}")


if __name__ == "__main__":
    main()
