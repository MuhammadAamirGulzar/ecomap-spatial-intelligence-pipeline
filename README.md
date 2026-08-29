# EcoMap — Spatial Intelligence Pipeline

Multimodal prediction of tumour **ecotypes** from spatial transcriptomics, with
knowledge distillation into a morphology-only student model.

A *teacher* learns from three modalities — H&E morphology, gene expression and
cell-type composition — and distils what it knows into a *student* that sees
only the H&E image embeddings. The point is to measure how much of the
multimodal signal survives when the expensive modalities are removed at
inference time.

---

## Contents

1. [The two pipelines](#1-the-two-pipelines)
2. [Quick start](#2-quick-start)
3. [Verifying your setup](#3-verifying-your-setup)
4. [Input data](#4-input-data)
5. [Configuration](#5-configuration)
6. [Model architecture](#6-model-architecture)
7. [Ablation studies](#7-ablation-studies)
8. [Output layout](#8-output-layout)
9. [Repository layout](#9-repository-layout)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. The two pipelines

Both are supported; pick by which question you are asking.

| | `run_pipeline.sh` | `run_unified_pipeline.sh` |
|---|---|---|
| **Trains** | Teacher only | Teacher → ensemble → student |
| **Configs** | `config/modular_*.yaml` | `config/modular_unified_teacher_student_*.yaml` |
| **Stages** | Load → validate → PCA → validate → train → post-training viz → spatial viz | Load → PCA → teacher → ensemble teacher → student (distillation) → spatial viz |
| **Use when** | Tuning the multimodal model, or you want the full QC and validation reports | Running the distillation experiment end to end |

```bash
./run_pipeline.sh         config/modular_GEO.yaml
./run_unified_pipeline.sh config/modular_unified_teacher_student_GEO.yaml
```

The teacher-only runner produces more diagnostics (correlation matrices,
per-modality QC, preprocessing validation). The unified runner is the shorter
path to a teacher/student comparison.

---

## 2. Quick start

```bash
git clone https://github.com/MuhammadAamirGulzar/ecomap-spatial-intelligence-pipeline.git
cd ecomap-spatial-intelligence-pipeline

python3 -m venv .venv
source .venv/bin/activate          # Windows (Git Bash): source .venv/Scripts/activate
pip install -r requirements.txt
```

Either `.venv/` or `venv/` works — the runners detect both, and fall back to
whatever `python` is on `PATH` (an activated conda environment, for instance).

Then place your data (see [Input data](#4-input-data)), point a config at it,
and run one of the two scripts above.

---

## 3. Verifying your setup

The real cohorts are large, so you do not need them to check that the pipeline
works:

```bash
./tests/smoke_test.sh
```

This generates a small synthetic cohort, runs both pipelines against it, and
asserts that the models, spatial maps, 3D landscapes, ensemble teacher and
student results all appear. About a minute on CPU. See
[`tests/README.md`](tests/README.md).

> It exercises plumbing, not science. Synthetic accuracy near 100% is expected
> and says nothing about real tissue.
>
> It **overwrites `data/input_dataset/`**, so do not run it on top of a real
> dataset stored there.

---

## 4. Input data

Datasets are distributed separately:
[Google Drive — dataset folder](https://drive.google.com/drive/folders/1h2mY0to3B52E_IKbG4DPKqhckzK-08o-?usp=sharing)

Place these in the directory your config's `input_dataset` points at
(`data/input_dataset/` by default):

| File | Contents |
|---|---|
| `image_encoder_embeddings.csv` | Morphology embeddings (e.g. UNI 1024D, CONCH, H-Optimus) |
| `gene_embeddings.csv` | Gene-expression embeddings (e.g. scVI 128D) |
| `cell_composition_embeddings.csv` | Cell-type composition (e.g. RCTD — 25D GEO, 15D Zenodo) |
| `barcode_labels.csv` | Per-spot class labels |
| `barcode_metadata.csv` | `barcode`, `patient_id`, `x_coord`, `y_coord` |
| `label_mapping.json` | `{"labels": {"<index>": "<ecotype name>"}}` |

Embedding CSVs are a `barcode` column followed by one column per dimension. All
three must cover the same barcodes.

**`x_coord` / `y_coord` are required.** Spatial figures are drawn in real tissue
space, so without them the spatial stages have nothing to plot.

Formats that have caused trouble before:

- The barcode column in `barcode_metadata.csv` may be called `barcode` or
  `original_barcode`; both are accepted.
- Labels may be 0- or 1-indexed. Training always works 0-indexed internally, and
  the mapping back to ecotype names is corrected using `label_mapping.json`, so
  1-indexed label files are handled — but the mapping file must agree with the
  label file.
- Ecotype names come from `label_mapping.json`. Names outside the reference five
  are fine; they are assigned generated colours.

---

## 5. Configuration

Everything is config-driven; changing a run should never require editing code.

| Config | Dataset |
|---|---|
| `modular_GEO.yaml` | GEO cohort |
| `modular_Zenodo.yaml` | Zenodo cohort |
| `modular_hest_ischia_labels.yaml` | HEST, ISCHIA+RCTD labels (Focal Loss, AdamW, LayerNorm, LR scheduling, gradient clipping) |
| `modular_flexible.yaml` | Template for a new dataset |
| `modular_unified_teacher_student_*.yaml` | The same cohorts, teacher + student |

Keys worth checking before a run:

```yaml
input_dataset:            # where your CSVs live
embeddings:
  image_encoder:
    pca_variance: 0.95    # variance retained, or null for no reduction
teacher:                  # named 'training:' in the teacher-only configs
  hidden_dims: [256, 128, 64]
  learning_rate: 0.001
  n_epochs: 200
  early_stopping_patience: 20
pipeline:
  n_folds: 5              # honoured by both teacher and student
  random_seed: 42
output_dir: "./results"
```

Paths are relative to the repository root. Keep them relative — an absolute path
pointing at one machine's drive is the most common reason a config that "works"
for one person fails for everyone else.

---

## 6. Model architecture

**Teacher (multimodal).** Fused morphology + gene + cell-composition input
(1177D for GEO before PCA), hidden layers `[256, 128, 64]`. Trained with
stratified K-fold cross-validation; the per-fold models are then averaged into a
frozen ensemble teacher, and that ensemble is what the student distils from.

**Student (morphology-only).** Morphology embeddings alone, hidden layers
`[128, 64, 32]`, trained against the ensemble teacher's soft targets.

The student is expected to score below the teacher — roughly 79% against 88% on
GEO. That gap is the measurement: it is the cost of dropping gene expression and
cell composition, not a defect.

---

## 7. Ablation studies

Ready-made configs drop a modality from the *student* while the teacher keeps
all three:

```bash
./run_unified_pipeline.sh config/modular_unified_teacher_student_GEO_student_cellonly.yaml
./run_unified_pipeline.sh config/modular_unified_teacher_student_GEO_student_geneonly.yaml
```

For other sweeps, copy a config and vary `pca_variance`, `hidden_dims`,
`learning_rate` or `n_folds`, giving each run its own `output_dir` so results do
not overwrite each other.

Comparisons are only meaningful when teacher and student share `n_folds` and
`random_seed`. Both now read those from the config.

---

## 8. Output layout

```
<output_dir>/
├── preprocessing/
│   ├── metrics/              QC reports, barcode alignment, value ranges
│   └── visualizations/       modality correlation matrices, spatial heatmaps
├── training/
│   ├── metrics/              training_results.json, predictions_all_spots.csv,
│   │                         label_encoder.pkl, fold histories
│   ├── models/               fold_N_best_model.pth  (inputs to the ensemble)
│   └── visualizations/       confusion matrix, training curves, per-class accuracy
├── post-training/
│   └── visualizations/       per patient: spatial ecotype map, confidence
│                             heatmap, neighbourhood analysis, 3D landscape
└── .working/                 intermediate arrays and fitted PCA models
```

The unified pipeline writes a `TEACHER/` and a `STUDENT/` tree in this shape,
plus `teacher_model_ENSEMBLE.pt` and `ensemble_teacher_summary.json`.

---

## 9. Repository layout

```
pipeline/                    every module here runs
├── load_input_embeddings.py         CSV → NumPy, barcode alignment
├── validate_initial_embeddings.py   input QC
├── preprocess_embeddings.py         PCA, fusion, saves PCA models for reuse
├── validate_and_visualize_preprocessing.py
├── train_mlp.py                     teacher, K-fold CV
├── build_ensemble_teacher.py        averages folds into a frozen teacher
├── train_student_model_unified.py   student + distillation
├── post_training_visualizations.py  confusion matrices, training curves
├── create_spatial_visualizations.py spatial maps, 3D landscapes
├── student_visualizations.py        teacher/student comparisons
├── metrics_tracker.py
└── extract_configs.py               splits a unified config for each stage

config/                      dataset and ablation configs
tests/                       synthetic-data smoke test
archive/                     modules no longer wired in — see archive/README.md
run_pipeline.sh              teacher-only orchestrator
run_unified_pipeline.sh      teacher + student orchestrator
```

---

## 10. Troubleshooting

**A stage crashes but the run reports "SUCCESSFUL".** Fixed — if you still see
it, you are on an old checkout. Stages are piped into `tee`, which placed them
in a subshell where `set -e` and `exit 1` could not stop the parent; both
runners now set `pipefail`.

**Spatial figures are empty, or `Dropped N rows with missing coordinates`.**
`barcode_metadata.csv` is missing, unreadable, or lacks `x_coord`/`y_coord`.
Look for `⚠ Could not load spatial metadata` early in the log — training
continues without coordinates and only the plots come out blank.

**Classes missing from spatial plots.** The names in `label_mapping.json` must
match the classes present. Unrecognised names are now given generated colours
rather than being dropped silently, and the log lists them.

**`UnicodeEncodeError` / `UnicodeDecodeError` on Windows.** The runners set
`PYTHONIOENCODING=utf-8` and configs are read as UTF-8. If you invoke a stage
directly rather than through a runner, export it yourself.

**`bad interpreter: /bin/bash^M`.** A CRLF checkout. `.gitattributes` pins shell
scripts to LF; re-clone, or run `git add --renormalize .`.

**Config changes appear to have no effect.** Confirm you passed the config you
edited — the runners echo the path they loaded. Note that `n_folds` and
`random_seed` were previously ignored by the teacher; they are honoured now.

**Out of memory.** Lower `batch_size`, or reduce `pca_variance` to shrink the
fused dimensionality.

---

## Provenance

This branch consolidates three sources: the `main` and `student` branches of the
team repository (`Nabeeha-Shafiq/EcoMap-FYP25`) and this fork. `student` forked
from `main` and the two then diverged, each gaining fixes the other never
received, so the merge is a union rather than a fast-forward and both histories
are preserved. `git log --merges` shows the integration points.

## License

MIT — see [LICENSE](LICENSE).
