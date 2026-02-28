# BalanceOpt

Standalone Python tool to fit a full-game mathematical balance model for block-puzzle survival runs.

## What it models

- 3-peak smooth speed curve + logarithmic tail per difficulty.
- Min-of-scales time control (`no mercy`, drag, DDA, micro, skills).
- Board pressure / well pressure dynamics with stochastic noise.
- Generator fairness quality signal with pity and decay.
- Dual-drop stress process with cap and stagger gap.
- Skill system with unlock days, per-skill rank schedule, cooldown, and charges.
- Hazard-based death process and stochastic run simulation.

## Files

- `default_targets.py`: default targets, bucket/day mapping, and optimization bounds.
- `model.py`: simulator + objective function.
- `optimizer.py`: random search + local evolution strategy.
- `run_fit.py`: CLI entry; writes outputs.

## Usage

From repository root:

```bash
python Tools/BalanceOpt/run_fit.py --runs 800 --seed 1
python Tools/BalanceOpt/run_fit.py --runs 800 --seed 1 --fast
python Tools/BalanceOpt/run_fit.py --runs 2000 --seed 1 --out Tools/BalanceOpt/best_params.json
```

## Outputs

Running `run_fit.py` writes:

- `Tools/BalanceOpt/best_params.json` (or `--out` path): fitted coefficients.
- `Tools/BalanceOpt/report.md`: report with target-vs-achieved table, full parameters, and sensitivity notes.

## Dependencies

- Python 3 standard library only.
- No external package is required.
