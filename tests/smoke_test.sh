#!/usr/bin/env bash
#
# End-to-end smoke test on a synthetic cohort.
#
# Runs both pipelines against generated data and asserts that the artifacts
# that matter actually appear. It checks plumbing, not model quality: the
# synthetic classes are well separated, so ~100% accuracy is expected and
# proves nothing about the real cohorts.
#
# Usage:
#   ./tests/smoke_test.sh            # both pipelines
#   ./tests/smoke_test.sh teacher    # teacher-only
#   ./tests/smoke_test.sh unified    # teacher + student distillation
#
# Runtime: roughly a minute on CPU.

set -e
set -o pipefail
export PYTHONIOENCODING=utf-8

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

WHICH="${1:-both}"
DATA_DIR="data/input_dataset"
TMP_CONFIG_DIR="config/.smoke"
FAILURES=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Reuse the runners' interpreter resolution rather than duplicating it.
if [ -x "./.venv/bin/python" ]; then PYTHON_EXEC="./.venv/bin/python"
elif [ -x "./venv/bin/python" ]; then PYTHON_EXEC="./venv/bin/python"
else
    PYTHON_EXEC=""
    for c in python3 python py; do
        if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then
            PYTHON_EXEC="$(command -v "$c")"; break
        fi
    done
    [ -z "$PYTHON_EXEC" ] && { echo "no working Python found"; exit 1; }
fi

check() {   # check <description> <path>
    if [ -e "$2" ]; then
        echo -e "  ${GREEN}✓${NC} $1"
    else
        echo -e "  ${RED}✗${NC} $1  (missing: $2)"
        FAILURES=$((FAILURES + 1))
    fi
}

count_at_least() {  # count_at_least <description> <glob-dir> <pattern> <n>
    local found
    found=$(find "$2" -name "$3" 2>/dev/null | wc -l)
    if [ "$found" -ge "$4" ]; then
        echo -e "  ${GREEN}✓${NC} $1 ($found found)"
    else
        echo -e "  ${RED}✗${NC} $1 (found $found, expected >= $4)"
        FAILURES=$((FAILURES + 1))
    fi
}

echo "════════════════════════════════════════════════════════════"
echo " EcoMap smoke test  (synthetic data, no real cohort needed)"
echo "════════════════════════════════════════════════════════════"

echo -e "\n${YELLOW}[1] Generating synthetic dataset${NC}"
$PYTHON_EXEC tests/make_synthetic_dataset.py --out "$DATA_DIR"

mkdir -p "$TMP_CONFIG_DIR"

# ---------------------------------------------------------------- teacher ---
if [ "$WHICH" = "both" ] || [ "$WHICH" = "teacher" ]; then
    echo -e "\n${YELLOW}[2] Teacher pipeline${NC}"
    rm -rf smoke_results

    $PYTHON_EXEC - <<'PY'
import io
s = io.open('config/modular_flexible.yaml', encoding='utf-8').read()
s = s.replace('n_epochs: 200', 'n_epochs: 12')
s = s.replace('n_folds: 5', 'n_folds: 2')
s = s.replace('output_dir: "./results_test_end_end_part2"', 'output_dir: "./smoke_results"')
io.open('config/.smoke/teacher.yaml', 'w', encoding='utf-8', newline='\n').write(s)
PY

    ./run_pipeline.sh config/.smoke/teacher.yaml > /tmp/ecomap_smoke_teacher.log 2>&1 \
        || { echo -e "${RED}teacher pipeline exited non-zero${NC}";
             tail -30 /tmp/ecomap_smoke_teacher.log; exit 1; }

    check "training results"        smoke_results/training/metrics/training_results.json
    check "per-spot predictions"    smoke_results/training/metrics/predictions_all_spots.csv
    check "confusion matrix"        smoke_results/training/visualizations/01_confusion_matrix.png
    count_at_least "per-fold models saved"        smoke_results/training/models '*.pth' 2
    count_at_least "spatial maps (one per patient)" smoke_results/post-training '*_spatial_ecotype_map.png' 3
    count_at_least "3D landscapes"                  smoke_results/post-training '*_3d_landscape.html' 3

    # Coordinates must be real, not the all-NaN placeholders.
    $PYTHON_EXEC - <<'PY' || FAILURES=$((FAILURES + 1))
import sys, pandas as pd
d = pd.read_csv('smoke_results/training/metrics/predictions_all_spots.csv')
ok = d['x_coord'].notna().any() and d['y_coord'].notna().any()
print(("  \033[0;32m✓\033[0m " if ok else "  \033[0;31m✗\033[0m ")
      + f"spatial coordinates populated ({d['x_coord'].notna().sum()}/{len(d)})")
sys.exit(0 if ok else 1)
PY
fi

# ---------------------------------------------------------------- unified ---
if [ "$WHICH" = "both" ] || [ "$WHICH" = "unified" ]; then
    echo -e "\n${YELLOW}[3] Unified teacher-student pipeline${NC}"
    rm -rf smoke_unified

    $PYTHON_EXEC - <<'PY'
import io
s = io.open('config/modular_unified_teacher_student_flexible.yaml', encoding='utf-8').read()
for k, v in (('./YOUR_DATA/YOUR_MORPHOLOGY_EMBEDDINGS.csv', './data/input_dataset/image_encoder_embeddings.csv'),
             ('./YOUR_DATA/YOUR_GENE_EMBEDDINGS.csv', './data/input_dataset/gene_embeddings.csv'),
             ('./YOUR_DATA/YOUR_CELL_COMPOSITION_EMBEDDINGS.csv', './data/input_dataset/cell_composition_embeddings.csv'),
             ('./YOUR_DATA/', './data/input_dataset/'),
             ('./YOUR_OUTPUT/TEACHER_CUSTOM_0.6_PCA', './smoke_unified/TEACHER'),
             ('./YOUR_OUTPUT/STUDENT_CUSTOM_0.6_PCA', './smoke_unified/STUDENT'),
             ('n_epochs: 200', 'n_epochs: 10'),
             ('n_epochs: 150', 'n_epochs: 10'),
             ('n_folds: 5', 'n_folds: 3')):
    s = s.replace(k, v)
io.open('config/.smoke/unified.yaml', 'w', encoding='utf-8', newline='\n').write(s)
PY

    ./run_unified_pipeline.sh config/.smoke/unified.yaml > /tmp/ecomap_smoke_unified.log 2>&1 \
        || { echo -e "${RED}unified pipeline exited non-zero${NC}";
             tail -30 /tmp/ecomap_smoke_unified.log; exit 1; }

    check "ensemble teacher"      smoke_unified/TEACHER/teacher_model_ENSEMBLE.pt
    check "ensemble summary"      smoke_unified/TEACHER/ensemble_teacher_summary.json
    check "student results"       smoke_unified/STUDENT/training/metrics/student_training_results.json
    check "student predictions"   smoke_unified/STUDENT/training/metrics/student_predictions.csv
    count_at_least "student fold models"    smoke_unified/STUDENT/training/models '*.pth' 3
    count_at_least "teacher spatial maps"   smoke_unified/TEACHER/post-training '*_spatial_ecotype_map.png' 3

    # Teacher and student must be cross-validated over the same number of folds,
    # or their reported metrics are not comparable.
    $PYTHON_EXEC - <<'PY' || FAILURES=$((FAILURES + 1))
import sys, json, glob
n_teacher = json.load(open('smoke_unified/TEACHER/ensemble_teacher_summary.json',
                           encoding='utf-8'))['n_folds']
n_student = len(glob.glob('smoke_unified/STUDENT/training/models/*.pth'))
ok = n_teacher == n_student
print(("  \033[0;32m✓\033[0m " if ok else "  \033[0;31m✗\033[0m ")
      + f"teacher/student fold counts agree (teacher={n_teacher}, student={n_student})")
sys.exit(0 if ok else 1)
PY
fi

rm -rf "$TMP_CONFIG_DIR"

echo
echo "════════════════════════════════════════════════════════════"
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN} SMOKE TEST PASSED${NC}"
    echo "════════════════════════════════════════════════════════════"
    exit 0
else
    echo -e "${RED} SMOKE TEST FAILED: $FAILURES check(s)${NC}"
    echo "════════════════════════════════════════════════════════════"
    exit 1
fi
