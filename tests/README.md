# Tests

The project has no unit tests; this is an end-to-end smoke test. It exists
because the real cohorts (GEO / Zenodo / HEST) are large and distributed
separately, so there was previously no way to run the pipeline at all without
first obtaining tens of gigabytes of data.

```bash
./tests/smoke_test.sh            # both pipelines  (~1-2 min, CPU)
./tests/smoke_test.sh teacher    # teacher only
./tests/smoke_test.sh unified    # teacher + student distillation
```

It generates a synthetic cohort, runs the pipeline(s), and asserts that the
artifacts that matter actually appear — models, per-fold checkpoints, spatial
maps, 3D landscapes, the ensemble teacher and the student results.

## What it does and does not tell you

It checks **plumbing**, not science. The synthetic classes are well separated,
so accuracy lands near 100% and says nothing about performance on real tissue.
What it does catch is the failure mode this pipeline is prone to: a stage that
breaks, or quietly produces empty output, while the run still reports success.

## Why the synthetic data looks the way it does

Each property below was chosen to reproduce a bug that had shipped:

| Property | Bug it guards against |
|---|---|
| Patients `PA/PB/PC`, not `P1..P5` | A hardcoded `PATIENTS = ['P1'..'P5']` list meant any other cohort silently produced no plots. |
| Labels 1-indexed (`1..5`) | Training converts labels to 0-indexed; without the shift correction every figure is mislabelled. |
| Ecotype names outside the reference five | The plotting palette was a fixed five-name dict, and classes absent from it were dropped from figures with no warning. |
| Metadata barcode column named `barcode` | `train_mlp.py` required `original_barcode` and swallowed the `KeyError`, emitting all-NaN coordinates that made every spatial figure empty. |

So a "boring" change to the generator — renaming a patient, 0-indexing the
labels — quietly weakens the test. Prefer adding cases over editing these.

## Outputs

Written to `smoke_results/` and `smoke_unified/`, both git-ignored. Full logs
land in `/tmp/ecomap_smoke_*.log`. The generated dataset goes to
`data/input_dataset/`, which is also ignored — note this **overwrites** that
directory, so do not run the smoke test on top of a real dataset kept there.
