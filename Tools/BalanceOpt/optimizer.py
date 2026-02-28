"""Random search + local evolution strategy optimizer."""

from __future__ import annotations

import random
from copy import deepcopy
from typing import Any, Dict, List, Tuple

try:
    from .default_targets import DIFFICULTIES, parameter_bounds
    from .model import deep_copy_params, objective
except ImportError:
    from default_targets import DIFFICULTIES, parameter_bounds
    from model import deep_copy_params, objective


Slot = Tuple[Tuple[str, ...], float, float]


def _get_ref(obj: Dict[str, Any], path: Tuple[str, ...]) -> Any:
    cur = obj
    for key in path:
        cur = cur[key]
    return cur


def _set_ref(obj: Dict[str, Any], path: Tuple[str, ...], value: Any) -> None:
    cur = obj
    for key in path[:-1]:
        cur = cur[key]
    cur[path[-1]] = value


def _slots(params: Dict[str, Any]) -> List[Slot]:
    bounds = parameter_bounds()
    slots: List[Slot] = []

    for key, (lo, hi) in bounds["global"].items():
        slots.append((("global", key), lo, hi))

    for diff in DIFFICULTIES:
        for key, (lo, hi) in bounds[diff].items():
            slots.append((("difficulty", diff, key), lo, hi))

    return slots


def randomize_params(base: Dict[str, Any], rng: random.Random, scale: float = 1.0) -> Dict[str, Any]:
    cand = deep_copy_params(base)
    for path, lo, hi in _slots(cand):
        cur = float(_get_ref(cand, path))
        span = (hi - lo) * scale
        if scale >= 1.0:
            val = rng.uniform(lo, hi)
        else:
            val = cur + rng.gauss(0.0, 0.33 * span)
            val = min(hi, max(lo, val))
        _set_ref(cand, path, val)

    _enforce_structure(cand)
    return cand


def _enforce_structure(params: Dict[str, Any]) -> None:
    """Monotonic sanity constraints."""
    for diff in DIFFICULTIES:
        d = params["difficulty"][diff]
        peaks = sorted([d["T1"], d["T2"], d["T3"]])
        d["T1"], d["T2"], d["T3"] = peaks
        d["pcap"] = max(d["pcap"], d["p0"] + 0.02)


def fit(
    initial_params: Dict[str, Any],
    runs: int,
    seed: int,
    fast: bool = False,
    random_samples: int = 36,
    es_iters: int = 42,
    pop_size: int = 12,
) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """Optimize parameters with broad random search then local ES."""
    rng = random.Random(seed)
    best = deep_copy_params(initial_params)
    best_score, best_info = objective(best, runs=runs, seed=seed, fast=fast)

    for i in range(random_samples):
        cand = randomize_params(initial_params, rng, scale=1.0)
        score, info = objective(cand, runs=runs, seed=seed + i + 17, fast=fast)
        if score < best_score:
            best, best_score, best_info = cand, score, info

    center = deep_copy_params(best)
    slots = _slots(center)

    for it in range(es_iters):
        sigma = 0.45 * (0.96 ** it)
        generation: List[Tuple[float, Dict[str, Any], Dict[str, Any]]] = []
        for pi in range(pop_size):
            cand = deepcopy(center)
            for path, lo, hi in slots:
                cur = float(_get_ref(cand, path))
                step = rng.gauss(0.0, sigma * (hi - lo))
                _set_ref(cand, path, max(lo, min(hi, cur + step)))
            _enforce_structure(cand)
            score, info = objective(cand, runs=runs, seed=seed + 4000 + it * 41 + pi, fast=fast)
            generation.append((score, cand, info))

        generation.sort(key=lambda x: x[0])
        elite = generation[: max(2, pop_size // 4)]
        if elite[0][0] < best_score:
            best_score, best, best_info = elite[0]
        center = deepcopy(elite[0][1])
        for path, lo, hi in slots:
            vals = [float(_get_ref(e[1], path)) for e in elite]
            avg = sum(vals) / len(vals)
            _set_ref(center, path, max(lo, min(hi, avg)))
        _enforce_structure(center)

    return best, {"score": best_score, "details": best_info}
