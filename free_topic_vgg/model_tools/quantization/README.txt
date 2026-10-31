Winograd-aware quantization: fixed-transform starting point
2026-10-28

Purpose
Reduce transformed U/V storage and memory traffic before adding SRAM macros.
Keep designated F(2,3) matrices, 16-core topology, MAC schedule and V lifetime.
The software scripts do not change checkpoints. The subsequent U8 RTL work
is documented in rtl_u8/REPORT_KO.txt; the original RTL is in rtl_u8/baseline/.

Current status (2026-10-28, after returned Colab results)
Official test: U16/V16 94.11%, U8/V16 94.15%, U8/V8 93.94%.
Downloaded predictions and checkpoint hash were audited in rtl_u8/colab_audit.json.
U8 packed SRAM loading/readout is implemented. The sixteen-core top defaults
to U8_PACKED=1; legacy tests explicitly select U16 where required.
U8 is signed INT8, two channel rows per 64-bit SRAM word. Per-K shifts restore
the scale before the existing INT16 MAC. V remains INT16; no 8-bit MAC claim.
rtl_u8/export/ holds checked packed payloads and per-K shifts for all 13 Convs.
Layer/original-MAC/16-core two-layer tests pass; full VGG RTL and PPA remain open.
The following sections retain the original experiment rationale and sequence.

Current implemented baseline
Spatial weights were already INT8; U = G2 * W_int8 * G2^T was exact INT16.
The integer model previously scored 9411/10000 vs FP32 9416/10000.
These are existing integer_vgg/manifest.json results, not this U8 experiment.

probe.py evaluates U16/U12/U10/U8 with the same activation calibration and FCs.
One nonnegative integer shift per output channel, shared over C and all 16
Winograd coordinates. Round-half-up to signed symmetric U, restoring the scale
after reduction and before output transform. V remains exact, ACC is not INT8.
The U16 Winograd implementation must equal direct integer convolution at every
Conv layer of the first test image. All 13 Conv, 5 pool, 3 FC execute in software.
Only trained weights determine U shifts; test labels are not calibration inputs.
The first-100 test run is a smoke check, not final model accuracy or QAT.

Original quantization experiment sequence
1. Use a held-out training validation set for quantization policy selection.
2. U8/V16 first: quantify error and storage benefit with fixed transformations.
3. U8/V8: calibrate V on training images. Use a common scale over input-channel
   reduction; initially share it over the whole layer. Detect row zeros after
   V quantization so bypass agrees with the operands actually supplied to MAC.
4. Add fake quantization at these boundaries during fine-tuning (QAT), keeping
   matrices fixed. Learn/fine-tune weights rather than silently replacing the
   hardware transforms. Match rounding, saturation, bias and requantization.
5. Lock scales and evaluate all 10000 official test images once policy is fixed.
6. Only then change SRAM packing/unpacking RTL and measure bit-exact outputs,
   U traffic, V occupancy, sparse issue counts and cycles with the same workload.

Hardware implications
U16 -> U8 halves U payload if packed. 512x512x4x4 U: 8MiB -> 4MiB,
excluding per-output scales. Parameter count and MAC count do not decrease.
Four coefficients of a row use 32 rather than 64 bits; filling only the lower
32 bits of the existing 64-bit word does not double capacity or halve traffic.
Packing two channel-row records per SRAM word needs an address/unpack adapter.
With this packing the same U banks can hold more output-channel weights.
V16 -> V8 would halve V payload, but is not measured in the initial probe.
Measured U8 loading cycles are now in rtl_u8/REPORT_KO.txt. PPA and QAT
accuracy are not claimed; the early probe alone did not measure hardware.

Primary references reviewed
WinoTrain: Winograd-Aware Training for Accurate Full 8-bit Convolution
Acceleration. DAC 2023. Institutional abstract/proceedings record:
https://iris.polito.it/handle/11583/2982761
Uses quantization-aware training across Winograd steps and few scale factors.
We have not reproduced its full training method or claimed its accuracy.

Searching for Winograd-aware Quantized Networks. MLSys 2020.
https://github.com/jafermarq/WinogradAwareNets
Official implementation. Learning transformation matrices is part of that
work; we deliberately keep the existing hardware matrices fixed in this probe.

Reproduce (PowerShell)
& 'C:\Users\jbpar\miniconda3\envs\idec-winograd\python.exe' free_topic_vgg/model_tools/quantization/probe.py --images 100
Outputs: artifacts/summary.json, REPORT.txt, u8_candidates.pt.
Public CIFAR test batch is read from the existing archive and its official
MD5 verified; the WSL-owned extracted directory is not modified.

Implemented second phase
evaluate_uv.py calibrates layer-wise V shifts with a 2041-bin integer histogram
on the existing 500 train calibration images. It minimizes reconstruction MSE
over shift values 0..4. U scale policy remains fixed and per-output-channel.
V is quantized before zero-row counting. U and V shifts are restored after
channel reduction, before output transform; existing bias/requant are retained.
It compares U16/V16 (exact direct-conv reference), U8/V16 and U8/V8.
The 1000-image validation set is balanced, deterministic, and excludes the 500
calibration images. The pretrained checkpoint did see these training images;
this is NOT independent test accuracy. These indices should also be excluded
from future QAT training. No QAT has run yet.

Colab handoff
colab/Winograd_U8_V8_Validation.ipynb and colab/winograd_uv8_bundle.zip.
1. Open the notebook in Colab and select an available GPU runtime.
2. Execute upload cell and choose the bundle. Its SHA256 is verified.
3. Run data preparation and arithmetic tests, then the 100-image benchmark.
4. Run the full test cell, download winograd_uv8_results.zip afterwards.
The notebook benchmarks float64 integer-oracle evaluation; a GPU is not
guaranteed to accelerate this workload. It reports projected full-test time.
This notebook evaluates PTQ, not QAT training. GPU execution is not locally
verified; its device-specific arithmetic test must pass before evaluation.
The local 1000-image run took about 302s; same CPU full-test estimate ~50min.
