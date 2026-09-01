"""Numerical equivalence tests for the Winograd correctness model."""

from __future__ import annotations

import unittest

import torch
from torch.nn import functional as F

from winograd import winograd_conv2d


class WinogradTests(unittest.TestCase):
    def test_matches_conv2d_for_even_output(self) -> None:
        self._check(shape=(2, 3, 12, 12), kernels=3)

    def test_matches_conv2d_for_odd_output_and_single_channel(self) -> None:
        self._check(shape=(2, 1, 13, 13), kernels=3)

    def test_gradient_reaches_spatial_weights(self) -> None:
        torch.manual_seed(2)
        x = torch.randn(1, 1, 6, 6, dtype=torch.float64)
        weight = torch.randn(2, 1, 3, 3, dtype=torch.float64, requires_grad=True)
        winograd_conv2d(x, weight).square().mean().backward()
        self.assertIsNotNone(weight.grad)
        self.assertGreater(weight.grad.abs().sum().item(), 0.0)

    def _check(self, shape: tuple[int, int, int, int], kernels: int) -> None:
        torch.manual_seed(1)
        x = torch.randn(*shape, dtype=torch.float64)
        weight = torch.randn(kernels, shape[1], 3, 3, dtype=torch.float64)
        bias = torch.randn(kernels, dtype=torch.float64)
        expected = F.conv2d(x, weight, bias)
        actual = winograd_conv2d(x, weight, bias)
        torch.testing.assert_close(actual, expected, rtol=1e-12, atol=1e-12)


if __name__ == "__main__":
    unittest.main()
