# Baseline versus Winograd accelerator comparison

The comparison uses the same dense-equivalent convention as the referenced
competition baseline report.

```text
N_MAC,baseline = 5*5*1*3 + 5*5*3*3 + 48 = 348
N_MAC,proposed = 3*3*1*3 + 3*3*3*3 + 75 = 183

TOPS = 2 * N_MAC * frequency / 1e12
TOPS/W = TOPS / power_W
```

At 476 MHz and 335 mW, the baseline yields 0.331296 TOPS and 0.988943
TOPS/W. At 1 GHz and 16.5962 mW, the proposed design yields 0.366 TOPS and
22.053241 TOPS/W. The table rounds the proposed power to 16.60 mW.

`baseline_vs_winograd.csv` is the numerical source for the publication table
and comparison plot in `docs/figures`.
