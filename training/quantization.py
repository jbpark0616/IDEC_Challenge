"""Small, explicit fake-quantization modules for Winograd QAT experiments."""

from __future__ import annotations

import torch
from torch import nn


class FakeQuantizer(nn.Module):
    """Per-tensor 8-bit fake quantizer with an EMA maximum observer.

    The integer grid is used in the forward pass, while the straight-through
    estimator passes gradients to the floating-point master tensor.
    """

    def __init__(self, *, signed: bool, bits: int = 8, momentum: float = 0.95) -> None:
        super().__init__()
        if bits < 2:
            raise ValueError("bits must be at least 2")
        self.signed = signed
        self.bits = bits
        self.momentum = momentum
        self.qmin = -(1 << (bits - 1)) if signed else 0
        self.qmax = (1 << (bits - 1)) - 1 if signed else (1 << bits) - 1
        self.register_buffer("scale", torch.tensor(1.0))
        self.register_buffer("initialized", torch.tensor(False))
        self.observer_enabled = True

    def observe(self, x: torch.Tensor) -> None:
        maximum = x.detach().abs().amax() if self.signed else x.detach().clamp_min(0).amax()
        new_scale = (maximum / self.qmax).clamp_min(torch.finfo(x.dtype).eps)
        if not bool(self.initialized):
            self.scale.copy_(new_scale)
            self.initialized.fill_(True)
        else:
            self.scale.mul_(self.momentum).add_(new_scale * (1.0 - self.momentum))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        if self.training and self.observer_enabled:
            self.observe(x)
        scale = self.scale.to(dtype=x.dtype, device=x.device)
        quantized = torch.clamp(torch.round(x / scale), self.qmin, self.qmax)
        dequantized = quantized * scale
        return x + (dequantized - x).detach()

    def integer(self, x: torch.Tensor) -> torch.Tensor:
        """Return integer codes using the currently stored scale."""
        scale = self.scale.to(dtype=x.dtype, device=x.device)
        return torch.clamp(torch.round(x / scale), self.qmin, self.qmax).to(torch.int32)

    def extra_repr(self) -> str:
        return f"signed={self.signed}, bits={self.bits}, scale={self.scale.item():.8g}"
