# EcoMap Spatial Intelligence Pipeline

End-to-end pipeline for multimodal ecotype prediction from spatial transcriptomics datasets.

This project supports data loading, validation, preprocessing, model training, and post-training visualization in a single workflow.

Maintainer: muhammadaamirgulzar

## Overview

The pipeline runs these stages:

| Stage | Description |
|---|---|
| 1 | Load and validate modality inputs (image, gene, cell composition) |
| 2 | Generate initial QC and validation reports |
| 3 | Run preprocessing and PCA reduction (configurable) |
| 4 | Train classifier with cross-validation |
| 5 | Export metrics, model artifacts, and predictions |
| 6 | Build spatial and performance visualizations |

## Project Structure

| Path | Purpose |
|---|---|
| `config/` | Dataset and training configuration files |
| `pipeline/` | Python pipeline modules |
| `run_pipeline.sh` | End-to-end orchestration script |
| `requirements.txt` | Python dependencies |

## Quick Start

### 1. Clone and enter the project

```bash
git clone https://github.com/MuhammadAamirGulzar/ecomap-spatial-intelligence-pipeline.git
cd ecomap-spatial-intelligence-pipeline
```

### 2. Create and activate a virtual environment

```bash
python -m venv .venv
source .venv/bin/activate
```

On Windows PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

### 3. Install dependencies

```bash
pip install -r requirements.txt
```

### 4. Select or edit a config file

| Config | Use Case |
|---|---|
| `config/modular_flexible.yaml` | Custom datasets |
| `config/modular_GEO.yaml` | GEO dataset template |
| `config/modular_Zenodo.yaml` | Zenodo dataset template |
| `config/modular_hest_ischia_labels.yaml` | HEST Ischia labels template |

### 5. Run the full pipeline

```bash
bash run_pipeline.sh config/modular_flexible.yaml
```

## Input Data Requirements

Each dataset directory should provide:

| File | Required |
|---|---|
| `barcode_labels.csv` | Yes |
| `barcode_metadata.csv` | Yes |
| `label_mapping.json` | Yes |
| Image embedding CSV | Yes |
| Gene embedding CSV | Yes |
| Cell composition embedding CSV | Yes |

For spatial maps, `barcode_metadata.csv` must include `x_coord`, `y_coord`, and `patient_id`.

## Output Artifacts

Outputs are written under the configured `output.output_dir` and include:

1. Validation and QC reports
2. Preprocessed arrays and optional PCA models
3. Training metrics, checkpoints, and fold summaries
4. Post-training visualizations (confusion matrices, spatial maps, neighborhood plots)
5. Pipeline execution log

## Troubleshooting

Pipeline fails early:
Check all input file paths in the selected config file.

Unexpected model performance:
Verify modality files and class mappings are aligned and have matching barcodes.

Missing spatial visualizations:
Verify metadata contains valid `x_coord` and `y_coord` values.

## License

This repository is released under a non-commercial license. See `LICENSE`.

Commercial use is not permitted.
