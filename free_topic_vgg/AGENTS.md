# Frozen design baseline

The user froze the current design on 2026-10-30. Read
`architecture/DESIGN_FREEZE_20261030.txt` before working on this project.

- Do not change RTL, source selection, hardware parameters, interfaces, storage placement, scheduling, or reuse/eviction behavior without explicit user authorization for that change.
- Profiling, synthesis, and test requests authorize measurement of this baseline, not architectural changes to make a test pass or improve a metric.
- Explain any proposed hardware change and its effect before seeking approval. Report discovered defects; do not silently repair frozen RTL.
- Keep experimental variants separate and create them only when authorized. Do not silently switch tests to legacy branches or old implementations.
- Preserve the baseline snapshot and hashes in `evidence/design_freeze_20261030/`; never regenerate them to conceal changes.
- The designated-topic root `verilog/` is a separate frozen design and must not be modified as part of free-topic work.
