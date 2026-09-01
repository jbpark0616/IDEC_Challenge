"""Unit tests for integer inference primitives."""

from __future__ import annotations

import unittest

import torch

from integer_inference import RangeTracker, narrow_profile, requantize_unsigned


class IntegerInferenceTests(unittest.TestCase):
    def test_required_signed_width(self) -> None:
        self.assertEqual(RangeTracker.signed_bits(-128, 127), 8)
        self.assertEqual(RangeTracker.signed_bits(-129, 127), 9)
        self.assertEqual(RangeTracker.signed_bits(0, 255), 9)

    def test_fixed_point_requantization_matches_rounding(self) -> None:
        values = torch.arange(0, 10000, dtype=torch.int64)
        actual = requantize_unsigned(values, 0.00021, 0.014, shift=24)
        expected = torch.round(values * (0.00021 / 0.014)).clamp(0, 255).to(torch.int64)
        self.assertLessEqual((actual - expected).abs().max().item(), 1)

    def test_signed_saturation(self) -> None:
        tracker = RangeTracker()
        values = torch.tensor([-200000, -131072, 0, 131071, 200000])
        actual = tracker.saturate("acc", values, 18)
        expected = torch.tensor([-131072, -131072, 0, 131071, 131071])
        torch.testing.assert_close(actual, expected)
        self.assertEqual(tracker.saturations["acc"], 2)

    def test_narrow_profile_preserves_v_width(self) -> None:
        profile = narrow_profile(17)
        self.assertEqual(profile["v"], 11)
        self.assertEqual(profile["m"], 17)
        self.assertEqual(profile["fc_acc"], 17)


if __name__ == "__main__":
    unittest.main()
