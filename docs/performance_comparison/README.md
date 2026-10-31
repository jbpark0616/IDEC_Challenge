# Baseline versus Winograd accelerator comparison

Primary metric: the Busan award report's virtual dense-MAC-count convention,
as requested by the user. This is not sustained measured hardware throughput.
The proposed count 183 is a nominal unrolled dense reference, not the number
of physical MAC lanes (16). The previous warning that the convention itself
was invalid was too broad; it is valid as a declared reference-based index.

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

The preceding values and CSV/figures describe the older design. For the final
995.83-cycle design, at 1 GHz with post-synthesis VCD power:

| Design | Virtual dense MAC count | Power (mW) | Busan-convention TOPS/W |
|---|---:|---:|---:|
| Busan final design (reported) | 348 | 35.7 | 19.496 |
| Our final design, ICG OFF | 183 | 16.25643 | 22.51417 |
| Our final design, ICG ON | 183 | 7.860995 | 46.55899 |

These use the same numerator convention adapted to each model. The award
report's power activity settings have not been reproduced in our environment.
The separate workload/energy metric (7.31035 TOPS/W) is supplementary and must
not replace or be mixed with this primary competition comparison.

`baseline_vs_winograd.csv` is the numerical source for the publication table
and comparison plot in `docs/report_assets/designated_topic/figures`.
