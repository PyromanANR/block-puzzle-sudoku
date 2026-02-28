"""Random search + local evolution strategy optimizer."""

from __future__ import annotations

import math
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


SKILL_BOUNDS = {
    "freeze": {
        "m_f": (0.35, 0.80),
        "duration": (4.0, 20.0),
        "cooldown": (30.0, 180.0),
        "charges": (1.0, 3.0),
    },
    "clear": {
        "x_after": (0.15, 0.65),
        "cooldown": (60.0, 220.0),
        "post_mult": (0.60, 1.0),
        "post_dur": (4.0, 25.0),
        "charges": (1.0, 3.0),
    },
    "ultimate": {
        "immunity": (4.0, 16.0),
        "cooldown": (100.0, 320.0),
        "xw_after": (0.15, 0.70),
    },
}


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

    for skill, sb in SKILL_BOUNDS.items():
        ranks = params["skills"][skill]["ranks"]
        for ri in range(len(ranks)):
            for key, (lo, hi) in sb.items():
                slots.append((("skills", skill, "ranks", ri, key), lo, hi))

    return slots


def _round_skill_params(params: Dict[str, Any]) -> None:
    for skill in ("freeze", "clear"):
        for rank in params["skills"][skill]["ranks"]:
            rank["charges"] = int(round(rank["charges"]))
            rank["charges"] = max(1, min(3, rank["charges"]))



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
    _round_skill_params(cand)
    return cand


def _enforce_structure(params: Dict[str, Any]) -> None:
    """Monotonic sanity constraints."""
    for diff in DIFFICULTIES:
        d = params["difficulty"][diff]
        peaks = sorted([d["T1"], d["T2"], d["T3"]])
        d["T1"], d["T2"], d["T3"] = peaks
        d["pcap"] = max(d["pcap"], d["p0"] + 0.02)

    for skill in ("freeze", "clear", "ultimate"):
        ranks = params["skills"][skill]["ranks"]
        for r in range(1, len(ranks)):
            prev = ranks[r - 1]
            cur = ranks[r]
            if skill == "freeze":
                cur["m_f"] = min(cur["m_f"], prev["m_f"])
                cur["duration"] = max(cur["duration"], prev["duration"])
            elif skill == "clear":
                cur["x_after"] = min(cur["x_after"], prev["x_after"])
                cur["post_mult"] = min(cur["post_mult"], prev["post_mult"])
                cur["post_dur"] = max(cur["post_dur"], prev["post_dur"])
            else:
                cur["immunity"] = max(cur["immunity"], prev["immunity"])
                cur["xw_after"] = min(cur["xw_after"], prev["xw_after"])


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

    # Global random exploration.
    for i in range(random_samples):
        cand = randomize_params(initial_params, rng, scale=1.0)
        score, info = objective(cand, runs=runs, seed=seed + i + 17, fast=fast)
        if score < best_score:
            best, best_score, best_info = cand, score, info

    # Local refinement (simple ES with decayed sigma).
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
            _round_skill_params(cand)
            score, info = objective(cand, runs=runs, seed=seed + 4000 + it * 41 + pi, fast=fast)
            generation.append((score, cand, info))

        generation.sort(key=lambda x: x[0])
        elite = generation[: max(2, pop_size // 4)]
        if elite[0][0] < best_score:
            best_score, best, best_info = elite[0]
        # Re-center to average elite.
        center = deepcopy(elite[0][1])
        for path, lo, hi in slots:
            vals = [float(_get_ref(e[1], path)) for e in elite]
            avg = sum(vals) / len(vals)
            _set_ref(center, path, max(lo, min(hi, avg)))
        _enforce_structure(center)
        _round_skill_params(center)

    return best, {"score": best_score, "details": best_info}
