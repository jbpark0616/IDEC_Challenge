"""CNN model definitions used to separate architecture changes from quantization."""

from __future__ import annotations

import torch
from torch import nn
from torch.nn import functional as F

from quantization import FakeQuantizer
from winograd import transform_weights, winograd_conv2d, winograd_conv2d_from_transformed


class Baseline5x5(nn.Module):
    """Official 5x5 competition model, expressed with current PyTorch APIs."""

    def __init__(self) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(1, 3, kernel_size=5)
        self.conv2 = nn.Conv2d(3, 3, kernel_size=5)
        self.fc = nn.Linear(3 * 4 * 4, 10)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = F.relu(F.max_pool2d(self.conv1(x), 2))
        x = F.relu(F.max_pool2d(self.conv2(x), 2))
        return self.fc(torch.flatten(x, 1))


class Spatial3x3(nn.Module):
    """3x3 candidate with the same channel counts and layer ordering.

    Shape flow: 28 -> conv 26 -> pool 13 -> conv 11 -> pool 5 -> FC 75.
    The spatial kernels remain the trainable master weights; they can later be
    transformed and fake-quantized in a Winograd-aware forward path.
    """

    def __init__(self) -> None:
        super().__init__()
        self.conv1 = nn.Conv2d(1, 3, kernel_size=3)
        self.conv2 = nn.Conv2d(3, 3, kernel_size=3)
        self.fc = nn.Linear(3 * 5 * 5, 10)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = F.relu(F.max_pool2d(self.conv1(x), 2))
        x = F.relu(F.max_pool2d(self.conv2(x), 2))
        return self.fc(torch.flatten(x, 1))


class WinogradConv2d(nn.Module):
    """Trainable 3x3 layer evaluated through the Winograd reference path."""

    def __init__(self, in_channels: int, out_channels: int) -> None:
        super().__init__()
        reference = nn.Conv2d(in_channels, out_channels, kernel_size=3)
        self.weight = nn.Parameter(reference.weight.detach().clone())
        self.bias = nn.Parameter(reference.bias.detach().clone())

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return winograd_conv2d(x, self.weight, self.bias)


class Winograd3x3(nn.Module):
    """Same network as Spatial3x3, with both convolutions run via Winograd."""

    def __init__(self) -> None:
        super().__init__()
        self.conv1 = WinogradConv2d(1, 3)
        self.conv2 = WinogradConv2d(3, 3)
        self.fc = nn.Linear(3 * 5 * 5, 10)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = F.relu(F.max_pool2d(self.conv1(x), 2))
        x = F.relu(F.max_pool2d(self.conv2(x), 2))
        return self.fc(torch.flatten(x, 1))


class QATWinogradConv2d(WinogradConv2d):
    """Winograd layer that fake-quantizes transformed weights U."""

    def __init__(self, in_channels: int, out_channels: int, *, weight_bits: int = 8) -> None:
        super().__init__(in_channels, out_channels)
        self.u_quant = FakeQuantizer(signed=True, bits=weight_bits)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        u = self.u_quant(transform_weights(self.weight))
        return winograd_conv2d_from_transformed(x, u, self.bias)


class QATLinear(nn.Linear):
    """Linear layer with signed fake-quantized weights."""

    def __init__(self, in_features: int, out_features: int, *, weight_bits: int = 8) -> None:
        super().__init__(in_features, out_features)
        self.weight_quant = FakeQuantizer(signed=True, bits=weight_bits)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return F.linear(x, self.weight_quant(self.weight), self.bias)


class QATWinograd3x3(nn.Module):
    """PyTorch QAT model for the proposed fused Winograd network.

    Activations stored between operations are unsigned INT8. Transformed
    Winograd weights and FC weights are signed INT8. Bias and accumulation stay
    floating-point for now; bit-accurate accumulator emulation is a later,
    separate numerical step after accuracy is established.
    """

    def __init__(self, *, weight_bits: int = 8) -> None:
        super().__init__()
        self.weight_bits = weight_bits
        self.input_quant = FakeQuantizer(signed=False)
        self.conv1 = QATWinogradConv2d(1, 3, weight_bits=weight_bits)
        self.activation1_quant = FakeQuantizer(signed=False)
        self.conv2 = QATWinogradConv2d(3, 3, weight_bits=weight_bits)
        self.activation2_quant = FakeQuantizer(signed=False)
        self.fc = QATLinear(3 * 5 * 5, 10, weight_bits=weight_bits)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.input_quant(x)
        x = self.activation1_quant(F.relu(F.max_pool2d(self.conv1(x), 2)))
        x = self.activation2_quant(F.relu(F.max_pool2d(self.conv2(x), 2)))
        return self.fc(torch.flatten(x, 1))

    def load_float_state_dict(self, state_dict: dict[str, torch.Tensor]) -> None:
        missing, unexpected = self.load_state_dict(state_dict, strict=False)
        quantizer_buffers = (".scale", ".initialized")
        real_missing = [key for key in missing if not key.endswith(quantizer_buffers)]
        if real_missing or unexpected:
            raise RuntimeError(f"incompatible checkpoint: missing={real_missing}, unexpected={unexpected}")

    def reset_weight_observers(self) -> None:
        """Discard source quantization scales after changing the weight precision."""
        for quantizer in (self.conv1.u_quant, self.conv2.u_quant, self.fc.weight_quant):
            quantizer.scale.fill_(1.0)
            quantizer.initialized.zero_()
