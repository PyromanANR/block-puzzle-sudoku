"""Default targets, bounds, and progression helpers for the balance optimizer."""

from __future__ import annotations

from typing import Dict, List

DIFFICULTIES = ["easy", "medium", "hard", "nm"]
BUCKETS = ["A", "B", "C", "R1", "R2", "R3"]

DAY_BUCKETS = {
    "A": (0, 2),
    "B": (3, 4),
    "C": (5, 6),
    "R1": (7, 13),
    "R2": (14, 20),
    "R3": (21, 9999),
}

SKILL_UNLOCK_DAY = {"freeze": 0, "clear": 3, "ultimate": 5}
SKILL_RANK_DAYS = {
    "freeze": [7, 14, 21],
    "clear": [10, 17, 24],
    "ultimate": [12, 19, 26],
}

INITIAL_PEAKS = {
    "easy": [180.0, 360.0, 600.0],
    "medium": [150.0, 300.0, 480.0],
    "hard": [120.0, 240.0, 360.0],
    "nm": [90.0, 180.0, 285.0],
}

INITIAL_WIDTH = {"easy": 90.0, "medium": 75.0, "hard": 60.0, "nm": 45.0}

INITIAL_AMPLITUDES = {
    "easy": {"A1": 0.25, "A2": 0.16, "A3": 0.12, "Atail": 0.06},
    "medium": {"A1": 0.32, "A2": 0.20, "A3": 0.16, "Atail": 0.08},
    "hard": {"A1": 0.40, "A2": 0.26, "A3": 0.22, "Atail": 0.10},
    "nm": {"A1": 0.50, "A2": 0.32, "A3": 0.28, "Atail": 0.12},
}

BASE_MEDIAN_SECONDS = {
    "easy": 9.0 * 60.0,
    "medium": 6.0 * 60.0,
    "hard": 7.5 * 60.0,
    "nm": 5.0 * 60.0,
}

BUCKET_PROGRESS_FACTOR = {
    "A": 1.00,
    "B": 1.10,
    "C": 1.20,
    "R1": 1.20 * 1.12,
    "R2": 1.20 * 1.12 * 1.10,
    "R3": 1.20 * 1.12 * 1.10 * 1.08,
}

BASE_PEAK_REACH = {
    "easy": [0.80, 0.45, 0.20],
    "medium": [0.80, 0.40, 0.12],
    "hard": [0.80, 0.35, 0.10],
    "nm": [0.75, 0.30, 0.08],
}

# Progression soft-growth for peak survival targets.
BUCKET_PEAK_BONUS = {"A": 0.0, "B": 0.02, "C": 0.04, "R1": 0.06, "R2": 0.08, "R3": 0.10}


def day_to_bucket(day: int) -> str:
    """Map day index to progression bucket."""
    for bucket, (low, high) in DAY_BUCKETS.items():
        if low <= day <= high:
            return bucket
    return "R3"


def bucket_to_representative_day(bucket: str) -> int:
    """Use lower bound day as representative for simulation."""
    return DAY_BUCKETS[bucket][0]


def build_default_targets() -> Dict[str, Dict[str, Dict[str, List[float]]]]:
    """Return target medians and peak survival probabilities by bucket+difficulty."""
    targets = {"median_seconds": {}, "peak_reach": {}}
    for bucket in BUCKETS:
        medians = {}
        peak = {}
        for diff in DIFFICULTIES:
            medians[diff] = BASE_MEDIAN_SECONDS[diff] * BUCKET_PROGRESS_FACTOR[bucket]
            pvals = []
            for p in BASE_PEAK_REACH[diff]:
                pvals.append(min(0.99, p + BUCKET_PEAK_BONUS[bucket]))
            peak[diff] = pvals
        targets["median_seconds"][bucket] = medians
        targets["peak_reach"][bucket] = peak
    return targets


def parameter_bounds() -> Dict[str, Dict[str, tuple]]:
    """Bounds for optimized coefficients."""
    bounds = {
        "global": {
            "tau": (120.0, 1800.0),
            "m0": (0.0, 0.40),
            "m1": (0.0, 0.60),
            "mmax": (0.1, 0.90),
            "pity_gain": (0.0, 0.08),
            "q_decay": (0.0, 0.03),
            "kdd": (0.05, 0.75),
        }
    }
    for diff in DIFFICULTIES:
        bounds[diff] = {
            "T1": (INITIAL_PEAKS[diff][0] * 0.75, INITIAL_PEAKS[diff][0] * 1.25),
            "T2": (INITIAL_PEAKS[diff][1] * 0.75, INITIAL_PEAKS[diff][1] * 1.25),
            "T3": (INITIAL_PEAKS[diff][2] * 0.75, INITIAL_PEAKS[diff][2] * 1.25),
            "W1": (30.0, 120.0),
            "W2": (30.0, 120.0),
            "W3": (30.0, 120.0),
            "A1": (0.05, 0.90),
            "A2": (0.05, 0.80),
            "A3": (0.04, 0.70),
            "Atail": (0.01, 0.30),
            "p0": (0.0, 0.20),
            "pramp": (0.0, 0.35),
            "pcap": (0.05, 0.55),
            "tdd": (30.0, 360.0),
            "wdd": (20.0, 160.0),
        }
    return bounds
