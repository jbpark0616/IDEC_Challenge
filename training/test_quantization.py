"""Checks for the PyTorch-only QAT path."""

from __future__ import annotations

import unittest

import torch

from models import QATWinograd3x3, Spatial3x3
from quantization import FakeQuantizer


class QuantizationTests(unittest.TestCase):
    def test_fake_quant_codes_stay_in_range(self) -> None:
        quantizer = FakeQuantizer(signed=True).train()
        values = torch.linspace(-3, 3, 1001, requires_grad=True)
        output = quantizer(values)
        codes = quantizer.integer(output)
        self.assertGreaterEqual(codes.min().item(), -128)
        self.assertLessEqual(codes.max().item(), 127)
        output.sum().backward()
        torch.testing.assert_close(values.grad, torch.ones_like(values))

    def test_float_checkpoint_initializes_qat_model(self) -> None:
        torch.manual_seed(5)
        float_model = Spatial3x3()
        qat_model = QATWinograd3x3()
        qat_model.load_float_state_dict(float_model.state_dict())
        torch.testing.assert_close(qat_model.conv1.weight, float_model.conv1.weight)
        torch.testing.assert_close(qat_model.conv2.weight, float_model.conv2.weight)
        torch.testing.assert_close(qat_model.fc.weight, float_model.fc.weight)

    def test_qat_model_observes_scales_and_backpropagates(self) -> None:
        torch.manual_seed(6)
        model = QATWinograd3x3().train()
        images = torch.rand(2, 1, 28, 28)
        loss = torch.nn.functional.cross_entropy(model(images), torch.tensor([1, 8]))
        loss.backward()
        self.assertTrue(bool(model.input_quant.initialized))
        self.assertTrue(bool(model.conv1.u_quant.initialized))
        self.assertTrue(bool(model.activation2_quant.initialized))
        self.assertGreater(model.conv1.weight.grad.abs().sum().item(), 0.0)


if __name__ == "__main__":
    unittest.main()
