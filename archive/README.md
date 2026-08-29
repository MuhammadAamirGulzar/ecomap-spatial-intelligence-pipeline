# Archived modules

These modules are **not part of any pipeline run**. Nothing in `pipeline/`,
`run_pipeline.sh` or `run_unified_pipeline.sh` imports or invokes them.

They were moved here (rather than deleted) so that `pipeline/` contains exactly
the code that executes, while the work itself stays available. Full history is
preserved — `git log --follow archive/<file>` shows it.

| Module | Status | Notes |
|---|---|---|
| `extract_teacher_model.py` | Superseded, still valid | Extracts and freezes the single **best fold** as the teacher. `pipeline/build_ensemble_teacher.py` replaced it with a weight-averaged ensemble across all folds ("Instead of extracting the single best fold…"). Single-best is a reasonable ablation to compare against, so this is kept deliberately. |
| `train_student_model.py` | Superseded | Predecessor of `pipeline/train_student_model_unified.py`. Its documented entry point references `config/modular_Student_GEO.yaml`, which does not exist in this repo, so it cannot be run as written. |
| `error_handling.py` | Never integrated | `ConfigValidator` / `DimensionChecker` utilities. Never imported anywhere. Wiring these into the runners' preflight checks would be a genuine improvement — the pipeline currently fails late, mid-training, on bad configs. |

## Restoring one

```bash
git mv archive/<file>.py pipeline/
```

Then add the import or runner stage it needs. If you restore
`extract_teacher_model.py` as an alternative to the ensemble teacher, note that
`run_unified_pipeline.sh` expects the artifact name written by
`build_ensemble_teacher.py`.
