"""Stochastic baseline run simulator and objective for balance fitting."""

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
        build_default_targets,
        bucket_to_representative_day,
    )
except ImportError:
    from default_targets import (
        BUCKETS,
        DIFFICULTIES,
        INITIAL_AMPLITUDES,
        INITIAL_PEAKS,
        INITIAL_WIDTH,
        build_default_targets,
        bucket_to_representative_day,
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
        "easy": dict(vbase=0.50, vcap=2.0, dvmax=0.008, lam0=0.00014, alpha=0.22, betab=1.0, betaw=1.2),
        "medium": dict(vbase=0.62, vcap=2.4, dvmax=0.009, lam0=0.00018, alpha=0.28, betab=1.2, betaw=1.45),
        "hard": dict(vbase=0.74, vcap=2.8, dvmax=0.010, lam0=0.00024, alpha=0.34, betab=1.45, betaw=1.8),
        "nm": dict(vbase=0.86, vcap=3.2, dvmax=0.011, lam0=0.00032, alpha=0.42, betab=1.8, betaw=2.1),
    }
    return presets[diff]


def default_params() -> Dict[str, Any]:
    """Build default parameter object used as optimization seed."""
    params: Dict[str, Any] = {
        "global": {
            "tau": 900.0,
            "m0": 0.03,
            "m1": 0.12,
            "mmax": 0.45,
            "kb": 0.35,
            "kw": 0.45,
            "kq": 0.18,
            "pity_gain": 0.018,
            "pity_thr": 0.70,
            "q_decay": 0.004,
            "q_noise": 0.010,
            "noise_b": 0.005,
            "noise_w": 0.005,
            "a_b": {"easy": 0.014, "medium": 0.018, "hard": 0.022, "nm": 0.028},
            "b_b": {"easy": 0.090, "medium": 0.085, "hard": 0.078, "nm": 0.070},
            "a_w": {"easy": 0.012, "medium": 0.016, "hard": 0.020, "nm": 0.026},
            "b_w": {"easy": 0.094, "medium": 0.088, "hard": 0.080, "nm": 0.072},
            "mu0": 0.22,
            "nu0": 0.24,
            "c_mu": 0.25,
            "c_nu": 0.30,
            "dda_kb": 0.15,
            "dda_kw": 0.18,
            "drag_k": 0.10,
            "micro_amp": 0.03,
            "micro_period": 90.0,
            "L0": {"easy": 1.6, "medium": 1.8, "hard": 2.0, "nm": 2.2},
            "xb0": {"easy": 0.72, "medium": 0.70, "hard": 0.68, "nm": 0.66},
            "xw0": {"easy": 0.76, "medium": 0.74, "hard": 0.72, "nm": 0.70},
            "kdd": 0.20,
            "dd_duration": 8.0,
            "dd_min_gap": 24.0,
            "x0_b": 0.12,
            "x0_w": 0.10,
            "q0": 0.88,
        },
        "difficulty": {},
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
            "p0": 0.010 if diff != "nm" else 0.018,
            "pramp": 0.035 if diff != "nm" else 0.055,
            "pcap": 0.11 if diff != "nm" else 0.15,
            "tdd": 120.0,
            "wdd": 85.0,
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
    _ = day
    g = params["global"]
    dcfg = params["difficulty"][diff]
    base = difficulty_baseline(diff)

    x_b = g["x0_b"]
    x_w = g["x0_w"]
    q = g["q0"]
    t = 0.0
    v = base["vbase"]

    dd_left = 0.0
    dd_gap = 0.0
    peaks = [dcfg["T1"], dcfg["T2"], dcfg["T3"]]

    while t < tmax:
        r = _compose_speed(t, dcfg, g)
        desired_v = min(base["vcap"], base["vbase"] * r)
        dv = desired_v - v
        v += clip(dv, -base["dvmax"] * dt, base["dvmax"] * dt)

        s_no_mercy = 1.0 - clip(g["m0"] + g["m1"] * x_w, 0.0, g["mmax"])
        s_drag = 1.0 - g["drag_k"] * x_w
        s_dda = 1.0 - clip(g["dda_kb"] * x_b + g["dda_kw"] * x_w, 0.0, 0.8)
        phase = (t % g["micro_period"]) / max(g["micro_period"], 1.0)
        s_micro = 1.0 - g["micro_amp"] * (0.5 + 0.5 * math.sin(phase * math.pi * 2.0))

        s = max(0.20, min(1.0, s_no_mercy, s_drag, s_dda, s_micro))
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

        lambda_h = base["lam0"] * math.exp(
            base["alpha"] * max(0.0, L - g["L0"][diff])
            + base["betab"] * max(0.0, x_b - g["xb0"][diff])
            + base["betaw"] * max(0.0, x_w - g["xw0"][diff])
        )
        p_die = 1.0 - math.exp(-lambda_h * dt)
        if rng.random() < p_die:
            break

        t += dt
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
    total = 0.0

    for bucket in BUCKETS:
        for diff in DIFFICULTIES:
            em = metrics[bucket][diff]["median_seconds"] - targets["median_seconds"][bucket][diff]
            total += med_weight * em * em
            for i in range(3):
                ep = metrics[bucket][diff]["peak_reach"][i] - targets["peak_reach"][bucket][diff][i]
                total += peak_weight * ep * ep

    reg = 0.0
    g = params["global"]
    reg += 0.5 * max(0.0, g["kdd"] - 0.55) ** 2
    reg += 0.6 * max(0.0, g["mmax"] - 0.75) ** 2
    for diff in DIFFICULTIES:
        d = params["difficulty"][diff]
        reg += 1.2 * max(0.0, d["Atail"] - 0.18) ** 2
    total += reg

    return total, {"metrics": metrics, "targets": targets, "regularization": reg}


def save_json(path: str, data: Dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)


def deep_copy_params(params: Dict[str, Any]) -> Dict[str, Any]:
    return deepcopy(params)
