"""Whole-model checks before quantization is introduced."""

from __future__ import annotations

import unittest

import torch

from models import Spatial3x3, Winograd3x3


class ModelTests(unittest.TestCase):
    def test_spatial_and_winograd_logits_match(self) -> None:
        torch.manual_seed(3)
        spatial = Spatial3x3().double().eval()
        winograd = Winograd3x3().double().eval()
        winograd.load_state_dict(spatial.state_dict())

        images = torch.randn(2, 1, 28, 28, dtype=torch.float64)
        with torch.no_grad():
            expected = spatial(images)
            actual = winograd(images)
        torch.testing.assert_close(actual, expected, rtol=1e-11, atol=1e-11)

    def test_whole_model_backpropagation(self) -> None:
        torch.manual_seed(4)
        model = Winograd3x3()
        images = torch.randn(2, 1, 28, 28)
        labels = torch.tensor([2, 7])
        loss = torch.nn.functional.cross_entropy(model(images), labels)
        loss.backward()

        for name, parameter in model.named_parameters():
            self.assertIsNotNone(parameter.grad, name)
            self.assertTrue(torch.isfinite(parameter.grad).all(), name)


if __name__ == "__main__":
    unittest.main()
