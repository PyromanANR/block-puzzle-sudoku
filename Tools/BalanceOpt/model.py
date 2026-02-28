"""Stochastic run simulator and objective for balance fitting."""

from __future__ import annotations

import json
import math
import random
from copy import deepcopy
from statistics import median
from typing import Any, Dict, List, Tuple

try:
    from .default_targets import (
        BUCKETS,
        DIFFICULTIES,
        INITIAL_AMPLITUDES,
        INITIAL_PEAKS,
        INITIAL_WIDTH,
        SKILL_RANK_DAYS,
        SKILL_UNLOCK_DAY,
        build_default_targets,
        bucket_to_representative_day,
        day_to_bucket,
    )
except ImportError:
    from default_targets import (
        BUCKETS,
        DIFFICULTIES,
        INITIAL_AMPLITUDES,
        INITIAL_PEAKS,
        INITIAL_WIDTH,
        SKILL_RANK_DAYS,
        SKILL_UNLOCK_DAY,
        build_default_targets,
        bucket_to_representative_day,
        day_to_bucket,
    )


def clip(value: float, low: float, high: float) -> float:
    return low if value < low else high if value > high else value


def sig(x: float) -> float:
    if x >= 0:
        e = math.exp(-x)
        return 1.0 / (1.0 + e)
    e = math.exp(x)
    return e / (1.0 + e)


def difficulty_baseline(diff: str) -> Dict[str, float]:
    """Baseline coefficients and hazard constants."""
    presets = {
        "easy": dict(vbase=0.85, vcap=2.8, dvmax=0.015, lam0=0.00055, alpha=0.32, betab=1.5, betaw=1.8),
        "medium": dict(vbase=1.0, vcap=3.3, dvmax=0.018, lam0=0.0007, alpha=0.40, betab=1.8, betaw=2.2),
        "hard": dict(vbase=1.12, vcap=3.9, dvmax=0.022, lam0=0.00095, alpha=0.48, betab=2.0, betaw=2.7),
        "nm": dict(vbase=1.28, vcap=4.5, dvmax=0.027, lam0=0.00125, alpha=0.56, betab=2.4, betaw=3.0),
    }
    return presets[diff]


def _skill_rank(day: int, skill: str) -> int:
    if day < SKILL_UNLOCK_DAY[skill]:
        return -1
    rank = 0
    for unlock_day in SKILL_RANK_DAYS[skill]:
        if day >= unlock_day:
            rank += 1
    return min(rank, 3)


def default_params() -> Dict[str, Any]:
    """Build default parameter object used as optimization seed."""
    params: Dict[str, Any] = {
        "global": {
            "tau": 720.0,
            "m0": 0.06,
            "m1": 0.22,
            "mmax": 0.55,
            "kb": 0.85,
            "kw": 0.95,
            "kq": 0.35,
            "pity_gain": 0.025,
            "pity_thr": 0.65,
            "q_decay": 0.008,
            "q_noise": 0.015,
            "noise_b": 0.008,
            "noise_w": 0.007,
            "a_b": {"easy": 0.042, "medium": 0.052, "hard": 0.060, "nm": 0.070},
            "b_b": {"easy": 0.062, "medium": 0.055, "hard": 0.050, "nm": 0.045},
            "a_w": {"easy": 0.032, "medium": 0.040, "hard": 0.048, "nm": 0.056},
            "b_w": {"easy": 0.060, "medium": 0.054, "hard": 0.049, "nm": 0.044},
            "mu0": 0.090,
            "nu0": 0.090,
            "c_mu": 0.45,
            "c_nu": 0.55,
            "dda_kb": 0.33,
            "dda_kw": 0.38,
            "drag_k": 0.26,
            "micro_amp": 0.05,
            "micro_period": 90.0,
            "L0": {"easy": 2.5, "medium": 2.8, "hard": 3.0, "nm": 3.3},
            "xb0": {"easy": 0.65, "medium": 0.60, "hard": 0.58, "nm": 0.55},
            "xw0": {"easy": 0.72, "medium": 0.68, "hard": 0.65, "nm": 0.62},
            "kdd": 0.33,
            "dd_duration": 10.0,
            "dd_min_gap": 18.0,
            "x0_b": 0.20,
            "x0_w": 0.15,
            "q0": 0.80,
        },
        "difficulty": {},
        "skills": {
            "freeze": {
                "ranks": [
                    {"m_f": 0.55, "duration": 8.0, "cooldown": 75.0, "charges": 1},
                    {"m_f": 0.52, "duration": 9.0, "cooldown": 70.0, "charges": 1},
                    {"m_f": 0.50, "duration": 10.0, "cooldown": 65.0, "charges": 2},
                    {"m_f": 0.47, "duration": 11.0, "cooldown": 60.0, "charges": 2},
                ]
            },
            "clear": {
                "ranks": [
                    {"x_after": 0.40, "cooldown": 130.0, "post_mult": 0.85, "post_dur": 10.0, "charges": 1},
                    {"x_after": 0.36, "cooldown": 122.0, "post_mult": 0.82, "post_dur": 11.0, "charges": 1},
                    {"x_after": 0.30, "cooldown": 114.0, "post_mult": 0.78, "post_dur": 12.0, "charges": 2},
                    {"x_after": 0.24, "cooldown": 108.0, "post_mult": 0.74, "post_dur": 13.0, "charges": 2},
                ]
            },
            "ultimate": {
                "ranks": [
                    {"immunity": 7.0, "cooldown": 210.0, "xw_after": 0.40},
                    {"immunity": 8.0, "cooldown": 195.0, "xw_after": 0.34},
                    {"immunity": 9.0, "cooldown": 185.0, "xw_after": 0.30},
                    {"immunity": 10.0, "cooldown": 175.0, "xw_after": 0.26},
                ]
            },
        },
    }
    for diff in DIFFICULTIES:
        params["difficulty"][diff] = {
            "T1": INITIAL_PEAKS[diff][0],
            "T2": INITIAL_PEAKS[diff][1],
            "T3": INITIAL_PEAKS[diff][2],
            "W1": INITIAL_WIDTH[diff],
            "W2": INITIAL_WIDTH[diff],
            "W3": INITIAL_WIDTH[diff],
            "A1": INITIAL_AMPLITUDES[diff]["A1"],
            "A2": INITIAL_AMPLITUDES[diff]["A2"],
            "A3": INITIAL_AMPLITUDES[diff]["A3"],
            "Atail": INITIAL_AMPLITUDES[diff]["Atail"],
            "p0": 0.03 if diff != "nm" else 0.05,
            "pramp": 0.06 if diff != "nm" else 0.08,
            "pcap": 0.20 if diff != "nm" else 0.26,
            "tdd": 120.0,
            "wdd": 80.0,
        }
    return params


def _compose_speed(t: float, dcfg: Dict[str, float], gcfg: Dict[str, Any]) -> float:
    r = 1.0
    r += dcfg["A1"] * sig((t - dcfg["T1"]) / max(dcfg["W1"], 1.0))
    r += dcfg["A2"] * sig((t - dcfg["T2"]) / max(dcfg["W2"], 1.0))
    r += dcfg["A3"] * sig((t - dcfg["T3"]) / max(dcfg["W3"], 1.0))
    r += dcfg["Atail"] * math.log(1.0 + t / max(gcfg["tau"], 1.0))
    return r


def simulate_run(params: Dict[str, Any], diff: str, day: int, rng: random.Random, dt: float = 1.0, tmax: float = 2400.0) -> Dict[str, Any]:
    """Simulate one run and return duration and per-peak survival flags."""
    g = params["global"]
    dcfg = params["difficulty"][diff]
    base = difficulty_baseline(diff)

    x_b = g["x0_b"]
    x_w = g["x0_w"]
    q = g["q0"]
    t = 0.0
    v = base["vbase"]

    freeze_rank = _skill_rank(day, "freeze")
    clear_rank = _skill_rank(day, "clear")
    ult_rank = _skill_rank(day, "ultimate")

    freeze = params["skills"]["freeze"]["ranks"][max(0, freeze_rank)] if freeze_rank >= 0 else None
    clear = params["skills"]["clear"]["ranks"][max(0, clear_rank)] if clear_rank >= 0 else None
    ult = params["skills"]["ultimate"]["ranks"][max(0, ult_rank)] if ult_rank >= 0 else None

    freeze_cd = 0.0
    clear_cd = 0.0
    ult_cd = 0.0

    freeze_left = 0.0
    clear_post_left = 0.0
    immun_left = 0.0

    freeze_charges = int(freeze["charges"]) if freeze else 0
    clear_charges = int(clear["charges"]) if clear else 0
    if clear_rank >= 2 and diff in ("easy", "medium"):
        clear_charges = max(clear_charges, 2)
    ult_charges = 1 if ult else 0

    dd_left = 0.0
    dd_gap = 0.0

    peaks = [dcfg["T1"], dcfg["T2"], dcfg["T3"]]

    while t < tmax:
        r = _compose_speed(t, dcfg, g)
        desired_v = min(base["vcap"], base["vbase"] * r)
        dv = desired_v - v
        step_dv = clip(dv, -base["dvmax"] * dt, base["dvmax"] * dt)
        v += step_dv

        s_no_mercy = 1.0 - clip(g["m0"] + g["m1"] * x_w, 0.0, g["mmax"])
        s_drag = 1.0 - g["drag_k"] * x_w
        s_dda = 1.0 - clip(g["dda_kb"] * x_b + g["dda_kw"] * x_w, 0.0, 0.8)
        phase = (t % g["micro_period"]) / max(g["micro_period"], 1.0)
        s_micro = 1.0 - g["micro_amp"] * (0.5 + 0.5 * math.sin(phase * math.pi * 2.0))

        s_skill = 1.0
        # Skill policy: trigger on thresholds.
        if freeze and freeze_charges > 0 and freeze_left <= 0 and freeze_cd <= 0 and x_w > 0.60:
            freeze_left = freeze["duration"]
            freeze_cd = freeze["cooldown"]
            freeze_charges -= 1
        if clear and clear_charges > 0 and clear_cd <= 0 and x_b > 0.75:
            x_b = min(x_b, clear["x_after"])
            clear_post_left = clear["post_dur"]
            clear_cd = clear["cooldown"]
            clear_charges -= 1
        if ult and ult_charges > 0 and ult_cd <= 0 and x_w > 0.80:
            x_w = min(x_w, ult["xw_after"])
            immun_left = ult["immunity"]
            ult_cd = ult["cooldown"]
            ult_charges -= 1

        if freeze_left > 0:
            s_skill = min(s_skill, freeze["m_f"])
        if clear_post_left > 0:
            s_skill = min(s_skill, clear["post_mult"])

        s = max(0.20, min(1.0, s_no_mercy, s_drag, s_dda, s_micro, s_skill))
        L = (v / s) * (1.0 + g["kb"] * x_b + g["kw"] * x_w) * (1.0 + g["kq"] * (1.0 - q))

        p_dd = clip(dcfg["p0"] + dcfg["pramp"] * sig((t - dcfg["tdd"]) / max(dcfg["wdd"], 1.0)), 0.0, dcfg["pcap"])
        if dd_left <= 0 and dd_gap <= 0 and rng.random() < p_dd * dt:
            dd_left = g["dd_duration"]
            dd_gap = g["dd_min_gap"]
        if dd_left > 0:
            L *= 1.0 + g["kdd"]

        mu = g["mu0"] * math.exp(-g["c_mu"] * L)
        nu = g["nu0"] * math.exp(-g["c_nu"] * L)

        q += g["pity_gain"] * (1.0 if x_b > g["pity_thr"] else 0.0) * dt
        q -= g["q_decay"] * dt
        q += rng.gauss(0.0, g["q_noise"] * math.sqrt(dt))
        q = clip(q, 0.0, 1.0)

        x_b += g["a_b"][diff] * L * dt - g["b_b"][diff] * mu * dt + rng.gauss(0.0, g["noise_b"] * math.sqrt(dt))
        x_w += g["a_w"][diff] * L * dt - g["b_w"][diff] * nu * dt + rng.gauss(0.0, g["noise_w"] * math.sqrt(dt))
        x_b = clip(x_b, 0.0, 1.0)
        x_w = clip(x_w, 0.0, 1.0)

        lambda_h = 0.0
        if immun_left <= 0:
            lambda_h = base["lam0"] * math.exp(
                base["alpha"] * max(0.0, L - g["L0"][diff])
                + base["betab"] * max(0.0, x_b - g["xb0"][diff])
                + base["betaw"] * max(0.0, x_w - g["xw0"][diff])
            )
        p_die = 1.0 - math.exp(-lambda_h * dt)
        if rng.random() < p_die:
            break

        t += dt
        freeze_cd = max(0.0, freeze_cd - dt)
        clear_cd = max(0.0, clear_cd - dt)
        ult_cd = max(0.0, ult_cd - dt)
        freeze_left = max(0.0, freeze_left - dt)
        clear_post_left = max(0.0, clear_post_left - dt)
        immun_left = max(0.0, immun_left - dt)
        dd_left = max(0.0, dd_left - dt)
        dd_gap = max(0.0, dd_gap - dt)

    return {
        "duration": t,
        "reached": [1 if t >= p else 0 for p in peaks],
    }


def simulate_metrics(
    params: Dict[str, Any],
    runs: int = 500,
    seed: int = 1,
    fast: bool = False,
) -> Dict[str, Dict[str, Dict[str, Any]]]:
    """Simulate all (bucket, difficulty) pairs and aggregate metrics."""
    rng = random.Random(seed)
    result: Dict[str, Dict[str, Dict[str, Any]]] = {bucket: {} for bucket in BUCKETS}
    dt = 2.0 if fast else 1.0
    tmax = 1800.0 if fast else 2400.0

    for bucket in BUCKETS:
        day = bucket_to_representative_day(bucket)
        for diff in DIFFICULTIES:
            durations: List[float] = []
            peak_counts = [0, 0, 0]
            for _ in range(runs):
                out = simulate_run(params, diff, day, rng=rng, dt=dt, tmax=tmax)
                durations.append(out["duration"])
                for i in range(3):
                    peak_counts[i] += out["reached"][i]
            result[bucket][diff] = {
                "median_seconds": float(median(durations)),
                "peak_reach": [c / float(runs) for c in peak_counts],
                "mean_seconds": sum(durations) / float(len(durations)),
            }
    return result


def objective(
    params: Dict[str, Any],
    targets: Dict[str, Any] | None = None,
    runs: int = 500,
    seed: int = 1,
    fast: bool = False,
) -> Tuple[float, Dict[str, Any]]:
    """Compute objective value and return detailed metrics."""
    targets = targets or build_default_targets()
    metrics = simulate_metrics(params, runs=runs, seed=seed, fast=fast)

    med_weight = 1.0 / (120.0 * 120.0)
    peak_weight = 4.0
    bucket_soft_weight = 2.0

    total = 0.0

    for bucket in BUCKETS:
        for diff in DIFFICULTIES:
            em = metrics[bucket][diff]["median_seconds"] - targets["median_seconds"][bucket][diff]
            total += med_weight * em * em
            for i in range(3):
                ep = metrics[bucket][diff]["peak_reach"][i] - targets["peak_reach"][bucket][diff][i]
                total += peak_weight * ep * ep

    # Soft monotonic progression on peak reaches.
    for diff in DIFFICULTIES:
        for i in range(3):
            prev = -1.0
            for bucket in BUCKETS:
                cur = metrics[bucket][diff]["peak_reach"][i]
                if prev >= 0 and cur + 0.01 < prev:
                    total += bucket_soft_weight * (prev - cur) ** 2
                prev = cur

    # Regularization for extremes.
    reg = 0.0
    g = params["global"]
    reg += 0.5 * max(0.0, g["kdd"] - 0.55) ** 2
    reg += 0.6 * max(0.0, g["mmax"] - 0.75) ** 2
    for diff in DIFFICULTIES:
        d = params["difficulty"][diff]
        reg += 1.2 * max(0.0, d["Atail"] - 0.18) ** 2
    for skill in ("freeze", "clear", "ultimate"):
        for rank in params["skills"][skill]["ranks"]:
            if skill == "freeze":
                reg += 0.2 * max(0.0, 0.50 - rank["m_f"]) ** 2
            if skill == "clear":
                reg += 0.3 * max(0.0, 0.20 - rank["x_after"]) ** 2
            if skill == "ultimate":
                reg += 0.3 * max(0.0, rank["immunity"] - 12.0) ** 2
    total += reg

    return total, {"metrics": metrics, "targets": targets, "regularization": reg}


def save_json(path: str, data: Dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)


def deep_copy_params(params: Dict[str, Any]) -> Dict[str, Any]:
    return deepcopy(params)
