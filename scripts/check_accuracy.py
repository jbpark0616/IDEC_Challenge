#!/usr/bin/env python3
"""
Parse xsim simulation log and report PASS/FAIL vs baseline accuracy.

Log formats recognized:
  - top_tb_1000:  "Accuracy : NN%"                  (from PDF slide 25)
  - top_tb:       "$finish called at time : ..."    (single-image, just completion check)
"""
import argparse
import re
import sys
from pathlib import Path

BASELINE_PERCENT = 96.0  # per KNU IDEC 2026 CCDC PDF slide 25


def parse_accuracy(text: str):
    m = re.search(r"Accuracy\s*:\s*(\d+(?:\.\d+)?)\s*%", text)
    return float(m.group(1)) if m else None


def sim_finished(text: str) -> bool:
    return "$finish called" in text or "$finish" in text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logfile", type=Path)
    ap.add_argument("--baseline", type=float, default=BASELINE_PERCENT,
                    help=f"Required accuracy %% (default {BASELINE_PERCENT})")
    args = ap.parse_args()

    if not args.logfile.exists():
        print(f"[FAIL] Log not found: {args.logfile}")
        sys.exit(2)

    text = args.logfile.read_text(errors="replace")

    acc = parse_accuracy(text)
    if acc is None:
        if sim_finished(text):
            print("[PASS] Simulation finished (single-image TB, no accuracy metric)")
            sys.exit(0)
        print("[FAIL] Simulation did not complete — check log")
        sys.exit(1)

    delta = acc - args.baseline
    status = "PASS" if acc + 1e-9 >= args.baseline else "FAIL"
    print(f"[{status}] Accuracy {acc:.1f}%   baseline {args.baseline:.1f}%   Δ {delta:+.1f}")
    sys.exit(0 if status == "PASS" else 1)


if __name__ == "__main__":
    main()
