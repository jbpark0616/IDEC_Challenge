"""Readable PyTorch reference for Winograd F(2x2, 3x3).

This is a correctness model, not an optimized implementation.  It intentionally
keeps the transforms visible so it can become the golden model for RTL.
"""

from __future__ import annotations

import torch
from torch.nn import functional as F


def _matrices(*, dtype: torch.dtype, device: torch.device) -> tuple[torch.Tensor, ...]:
    bt = torch.tensor(
        [[1, 0, -1, 0], [0, 1, 1, 0], [0, -1, 1, 0], [0, 1, 0, -1]],
        dtype=dtype,
        device=device,
    )
    g = torch.tensor(
        [[1, 0, 0], [0.5, 0.5, 0.5], [0.5, -0.5, 0.5], [0, 0, 1]],
        dtype=dtype,
        device=device,
    )
    at = torch.tensor(
        [[1, 1, 1, 0], [0, 1, -1, -1]], dtype=dtype, device=device
    )
    return bt, g, at


def transform_weights(weight: torch.Tensor) -> torch.Tensor:
    """Transform spatial KxCx3x3 kernels into KxCx4x4 Winograd weights."""
    if weight.ndim != 4 or weight.shape[-2:] != (3, 3):
        raise ValueError(f"expected [K,C,3,3] weights, got {tuple(weight.shape)}")
    _, g, _ = _matrices(dtype=weight.dtype, device=weight.device)
    return torch.matmul(torch.matmul(g, weight), g.t())


def winograd_conv2d(
    x: torch.Tensor, weight: torch.Tensor, bias: torch.Tensor | None = None
) -> torch.Tensor:
    """Compute stride-1, valid 3x3 cross-correlation via F(2x2,3x3).

    PyTorch calls this operation convolution but implements cross-correlation.
    The transform below follows the same convention.  Odd output dimensions are
    zero-padded only to complete the final tile and cropped after reconstruction.
    """
    return winograd_conv2d_from_transformed(x, transform_weights(weight), bias)


def winograd_conv2d_from_transformed(
    x: torch.Tensor, transformed_weight: torch.Tensor, bias: torch.Tensor | None = None
) -> torch.Tensor:
    """Compute F(2x2,3x3) from already transformed KxCx4x4 weights."""
    if x.ndim != 4 or transformed_weight.ndim != 4:
        raise ValueError("x and weight must both be rank-4 tensors")
    if transformed_weight.shape[-2:] != (4, 4) or x.shape[1] != transformed_weight.shape[1]:
        raise ValueError("expected matching-channel KxCx4x4 transformed weights")

    n, channels, height, width = x.shape
    kernels = transformed_weight.shape[0]
    out_h, out_w = height - 2, width - 2
    if out_h <= 0 or out_w <= 0:
        raise ValueError("input must be at least 3x3")

    padded_out_h = (out_h + 1) // 2 * 2
    padded_out_w = (out_w + 1) // 2 * 2
    x = F.pad(x, (0, padded_out_w - out_w, 0, padded_out_h - out_h))

    bt, _, at = _matrices(dtype=x.dtype, device=x.device)
    # unfold: [N, C*16, tiles] -> [N, tiles, C, 4, 4]
    columns = F.unfold(x, kernel_size=4, stride=2)
    tile_count = columns.shape[-1]
    tiles = columns.transpose(1, 2).reshape(n, tile_count, channels, 4, 4)

    v = torch.matmul(torch.matmul(bt, tiles), bt.t())
    # Element-wise multiply and input-channel reduction.
    m = torch.einsum("nlcij,kcij->nlkij", v, transformed_weight)
    y_tiles = torch.matmul(torch.matmul(at, m), at.t())

    tile_rows, tile_cols = padded_out_h // 2, padded_out_w // 2
    y = (
        y_tiles.reshape(n, tile_rows, tile_cols, kernels, 2, 2)
        .permute(0, 3, 1, 4, 2, 5)
        .reshape(n, kernels, padded_out_h, padded_out_w)
    )
    y = y[:, :, :out_h, :out_w]
    if bias is not None:
        y = y + bias.reshape(1, -1, 1, 1)
    return y
