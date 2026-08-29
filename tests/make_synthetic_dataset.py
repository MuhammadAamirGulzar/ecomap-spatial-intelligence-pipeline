#!/usr/bin/env python3
"""
Generate a small synthetic cohort in the pipeline's input format.

The real cohorts (GEO / Zenodo / HEST) are large and distributed separately, so
there is otherwise no way to exercise the pipeline. This produces a dataset of
the right *shape* - not real biology - so the plumbing can be tested in ~1 min.

Deliberate choices, each of which has caught a real bug:

  * Patient IDs are PA/PB/PC, not P1..P5. The visualization code used to carry
    a hardcoded PATIENTS = ['P1'..'P5'] list; anything else silently produced
    no plots.
  * Labels are 1-indexed (1..5), not 0-indexed. Training converts them to
    0-indexed, and the mapping back to ecotype names has to account for the
    shift or every plot is mislabelled.
  * Ecotype names are NOT the reference five. The plotting palette used to be a
    fixed five-name dict, and classes missing from it were dropped from figures
    without warning.
  * The metadata barcode column is named 'barcode'. train_mlp.py used to
    require 'original_barcode' and swallow the KeyError, emitting all-NaN
    coordinates.

Usage:
    python tests/make_synthetic_dataset.py [--out data/input_dataset] [--seed 0]
"""

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

# Intentionally not the reference ecotype names, and intentionally 1-indexed.
ECOTYPES = {1: 'Fibrotic', 2: 'Immune', 3: 'Tumor', 4: 'Necrotic', 5: 'Normal'}
PATIENTS = ['PA', 'PB', 'PC']


def build(out_dir: Path, n_per_patient: int, seed: int) -> int:
    rng = np.random.default_rng(seed)
    out_dir.mkdir(parents=True, exist_ok=True)

    barcodes, labels, meta = [], [], []
    for patient in PATIENTS:
        for i in range(n_per_patient):
            barcode = f"{patient}_{i:04d}"
            barcodes.append(barcode)
            labels.append((barcode, int(rng.integers(1, len(ECOTYPES) + 1))))
            meta.append((barcode, patient,
                         float(rng.uniform(0, 100)), float(rng.uniform(0, 100))))

    y = np.array([lbl for _, lbl in labels])

    def modality(dim: int, separation: float) -> np.ndarray:
        """Class-separable features, so training reaches a non-trivial accuracy."""
        centres = rng.normal(0, separation, size=(len(ECOTYPES) + 1, dim))
        return np.vstack([centres[c] + rng.normal(0, 1.0, dim) for c in y])

    for name, dim, sep in (('image_encoder_embeddings', 64, 3.0),
                           ('gene_embeddings', 48, 2.5),
                           ('cell_composition_embeddings', 25, 2.0)):
        (pd.DataFrame(modality(dim, sep), index=barcodes)
           .rename_axis('barcode').reset_index()
           .to_csv(out_dir / f'{name}.csv', index=False))

    (pd.DataFrame(labels, columns=['barcode', 'label'])
       .set_index('barcode').to_csv(out_dir / 'barcode_labels.csv'))

    (pd.DataFrame(meta, columns=['barcode', 'patient_id', 'x_coord', 'y_coord'])
       .to_csv(out_dir / 'barcode_metadata.csv', index=False))

    with open(out_dir / 'label_mapping.json', 'w', encoding='utf-8') as f:
        json.dump({'labels': {str(k): v for k, v in ECOTYPES.items()}}, f, indent=2)

    return len(barcodes)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', default='data/input_dataset',
                        help='output directory (default: data/input_dataset)')
    parser.add_argument('--spots-per-patient', type=int, default=90)
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    out_dir = Path(args.out)
    n = build(out_dir, args.spots_per_patient, args.seed)
    print(f"Synthetic dataset written to {out_dir}")
    print(f"  {n} spots | patients={PATIENTS} | labels 1..{len(ECOTYPES)} (1-indexed)")
    print(f"  ecotypes: {list(ECOTYPES.values())}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
