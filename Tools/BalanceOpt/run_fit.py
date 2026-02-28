"""CLI entrypoint for fitting full-game balance model coefficients."""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
from copy import deepcopy
from datetime import datetime, timezone
from typing import Any, Dict, List, Tuple

if __package__ in (None, ""):
    THIS_DIR = os.path.dirname(os.path.abspath(__file__))
    if THIS_DIR not in sys.path:
        sys.path.insert(0, THIS_DIR)
    from default_targets import BUCKETS, DIFFICULTIES, build_default_targets  # type: ignore
    from model import default_params, objective, save_json  # type: ignore
    from optimizer import fit  # type: ignore
else:
    from .default_targets import BUCKETS, DIFFICULTIES, build_default_targets
    from .model import default_params, objective, save_json
    from .optimizer import fit


def _tabulate_metrics(targets: Dict[str, Any], achieved: Dict[str, Any]) -> str:
    lines = []
    lines.append("| Bucket | Difficulty | Median Target (s) | Median Achieved (s) | P1 T/A | P2 T/A | P3 T/A |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for bucket in BUCKETS:
        for diff in DIFFICULTIES:
            tmed = targets["median_seconds"][bucket][diff]
            amed = achieved[bucket][diff]["median_seconds"]
            tpeaks = targets["peak_reach"][bucket][diff]
            apeaks = achieved[bucket][diff]["peak_reach"]
            lines.append(
                "| {b} | {d} | {tm:.1f} | {am:.1f} | {tp1:.2f}/{ap1:.2f} | {tp2:.2f}/{ap2:.2f} | {tp3:.2f}/{ap3:.2f} |".format(
                    b=bucket,
                    d=diff,
                    tm=tmed,
                    am=amed,
                    tp1=tpeaks[0],
                    ap1=apeaks[0],
                    tp2=tpeaks[1],
                    ap2=apeaks[1],
                    tp3=tpeaks[2],
                    ap3=apeaks[2],
                )
            )
    return "\n".join(lines)


def _sensitivity_notes(params: Dict[str, Any], runs: int, seed: int, fast: bool) -> List[str]:
    probes: List[Tuple[Tuple[str, ...], str]] = [
        (("global", "tau"), "Global tail time constant"),
        (("global", "kdd"), "Dual-drop load multiplier"),
        (("difficulty", "easy", "Atail"), "Easy tail amplitude"),
        (("difficulty", "nm", "A1"), "NM first peak amplitude"),
    ]

    base_score, _ = objective(params, runs=runs, seed=seed, fast=fast)
    notes: List[str] = []
    for path, label in probes:
        trial = deepcopy(params)
        ref = trial
        for key in path[:-1]:
            ref = ref[key]
        k = path[-1]
        ref[k] = float(ref[k]) * 1.05
        hi_score, _ = objective(trial, runs=max(60, runs // 3), seed=seed + 111, fast=True)

        trial2 = deepcopy(params)
        ref2 = trial2
        for key in path[:-1]:
            ref2 = ref2[key]
        ref2[k] = float(ref2[k]) * 0.95
        lo_score, _ = objective(trial2, runs=max(60, runs // 3), seed=seed + 222, fast=True)

        notes.append(
            f"- {label}: baseline={base_score:.4f}, +5% => {hi_score:.4f}, -5% => {lo_score:.4f}."
        )
    return notes


def main() -> None:
    parser = argparse.ArgumentParser(description="Fit puzzle-run balance coefficients with stochastic simulation.")
    parser.add_argument("--runs", type=int, default=500, help="Simulation runs per (difficulty, bucket) pair")
    parser.add_argument("--seed", type=int, default=1, help="Base random seed")
    parser.add_argument("--fast", action="store_true", help="Use faster but coarser simulation")
    parser.add_argument(
        "--out",
        type=str,
        default="Tools/BalanceOpt/best_params.json",
        help="Output JSON path for best parameters",
    )
    args = parser.parse_args()

    if args.fast:
        rand_samples, es_iters, pop = 18, 20, 8
    else:
        rand_samples, es_iters, pop = 36, 42, 12

    base = default_params()
    best, opt_info = fit(
        initial_params=base,
        runs=args.runs,
        seed=args.seed,
        fast=args.fast,
        random_samples=rand_samples,
        es_iters=es_iters,
        pop_size=pop,
    )

    out_path = args.out
    if not os.path.isabs(out_path):
        out_path = os.path.join(os.getcwd(), out_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    save_json(out_path, best)

    final_score, eval_info = objective(best, runs=args.runs, seed=args.seed + 999, fast=args.fast)
    targets = eval_info["targets"]
    achieved = eval_info["metrics"]

    report_path = os.path.join(os.getcwd(), "Tools/BalanceOpt/report.md")
    notes = _sensitivity_notes(best, runs=min(220, args.runs), seed=args.seed + 333, fast=True)

    report = []
    report.append("# Balance Optimization Report")
    report.append("")
    report.append(f"Generated: {datetime.now(timezone.utc).isoformat()}Z")
    report.append(f"Final objective score: {final_score:.6f}")
    report.append(f"Optimizer internal best score: {opt_info['score']:.6f}")
    report.append("")
    report.append("## Targets vs Achieved")
    report.append("")
    report.append(_tabulate_metrics(targets, achieved))
    report.append("")
    report.append("## Final Parameters")
    report.append("")
    report.append("```json")
    report.append(json.dumps(best, indent=2, sort_keys=True))
    report.append("```")
    report.append("")
    report.append("## Sensitivity Notes")
    report.extend(notes)
    report.append("")
    report.append("## Notes")
    report.append("- Progression buckets use day mapping A:0-2, B:3-4, C:5-6, R1:7-13, R2:14-20, R3:21+.")
    report.append("- Skill unlock schedule and rank unlock days are encoded exactly as requested.")

    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(report) + "\n")

    print(f"Saved best params to: {out_path}")
    print(f"Saved report to: {report_path}")
    print(f"Final objective score: {final_score:.6f}")


if __name__ == "__main__":
    main()
