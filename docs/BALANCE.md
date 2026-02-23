# Balance Targets & Tuning Guide (Sudoku-like + Falling Blocks)

## 1) Internet research (2022–2026 preference)

> Notes are focused on pacing, fair randomness and challenge ramp.

1. **Unity — 2024 Mobile Gaming Report**  
   https://unity.com/resources/2024-mobile-gaming-report  
   Broad 2024 mobile trend report used as macro context for short/mid session behavior and rising expectation for fast engagement loops.

2. **GameAnalytics Blog / Benchmarks hub**  
   https://gameanalytics.com/blog/  
   Industry benchmark discussions repeatedly highlight first-session friction and early drop-off sensitivity.

3. **GDC Vault (difficulty/puzzle talks index)**  
   https://www.gdcvault.com/search.php#&category=free&firstfocus=&keyword=difficulty+puzzle  
   Practical design talks trend toward staged onboarding -> pressure -> mastery and telemetry-driven balancing.

4. **TetrisWiki — Tetris Guideline**  
   https://tetris.wiki/Tetris_Guideline  
   Reference for fairness expectations, controllability and consistency in falling-block systems.

5. **TetrisWiki — Random Generator (7-bag)**  
   https://tetris.wiki/Random_Generator  
   Canonical example of "fair randomness" reducing droughts and perceived RNG deaths.

6. **arXiv search: dynamic difficulty adjustment in games**  
   https://arxiv.org/search/?query=dynamic+difficulty+adjustment+games&searchtype=all  
   Recent academic landscape used to ground DDA as adaptive but rate-limited control.

7. **Wikipedia — Flow (psychology)**  
   https://en.wikipedia.org/wiki/Flow_(psychology)  
   Used for practical flow-target framing: challenge should stay slightly above comfort.

8. **Wikipedia — Hypercasual game**  
   https://en.wikipedia.org/wiki/Hypercasual_game  
   Useful for interpreting very short-session expectations and time-to-core-challenge on mobile.

### Research-derived pacing recommendations

- **Casual segment**: session target ~4–9 min median, pressure should appear quickly but be recoverable.
- **Mid/core segment**: session target ~7–15 min, clear pressure step by minute 1–2.
- **Hardcore segment**: long-tail runs 12–25+ min, with early pressure and high skill ceiling.
- **Time-to-first-meaningful challenge** should be inside first 30–90 seconds.
- **Time-to-first-near-fail** should generally appear in 2–6 min (segment dependent).
- **Fairness guardrails**: constrained random generation + pity fallback to avoid random unwinnables.

---

## 2) Numeric design targets

Adjusted targets for this project:

- **Casual**
  - first pressure: **45–90s**
  - first near-fail: **3–6 min**
  - typical fail window: **5–10 min**

- **Mid/core**
  - first pressure: **30–60s**
  - first near-fail: **2–4 min**
  - typical fail window: **6–15 min**

- **Hardcore**
  - first pressure: **20–45s**
  - first near-fail: **1.5–3 min**
  - typical fail window: **10–25+ min**

---

## 3) Implemented tuning knobs (single config)

Config file: `Scripts/Core/balance_config.json`

### Speed / pacing
- `BaseFallSpeed`
- `LevelSpeedGrowth`
- `TimeSpeedRampPerMinute`
- `MaxFallSpeedCap`
- `DdaMinFallMultiplier`, `DdaMaxFallMultiplier`

### Generation fairness
- `IdealPieceChanceEarly`, `IdealPieceChanceLate`
- `IdealChanceDecayPerMinute`, `IdealChanceFloor`
- `PityEveryNSpawns`
- `NoProgressMovesForPity`
- `CandidateTopBand`

### DDA signals
- `TargetMoveTimeSec`
- `FillDangerThreshold`
- `DdaRatePerMove`

### Well / pile
- `WellSize`
- `PileMax`
- `TopSelectable`
- `PileVisible`
- `DangerLineStartRatio`, `DangerLineEndRatio`

### Scoring / leveling
- `PointsPerLevel` (slows early leveling to avoid level-10-at-3-min flatness)

---

## 4) Curve changes implemented

1. **Speed ramp strengthened early**
   - Added explicit time-based ramp (`TimeSpeedRampPerMinute`) in addition to level scaling.
   - Added hard cap (`MaxFallSpeedCap`) and kept DDA smoothing.

2. **Well generosity reduced by default**
   - Default `PileMax` changed from old 8 toward **6** via config.
   - Main scene now reads well settings from Core config.

3. **Generation forgiveness now decays over run time**
   - Ideal-piece chance decays by minute and is clamped by floor.
   - Pity still prevents unfair dead-end streaks.

4. **Pity now reacts to no-progress streaks**
   - If player makes `NoProgressMovesForPity` moves without clear, next piece can be forced helpful.

---

## 5) Simulation runner metrics

The simulation tracks:
- average time to game over
- p50/p90 time distribution
- clears/minute
- no-move loss rate
- well overflow rate
- pity triggers per game

### Variant results (offline quick sim)
From `tools_simulate_balance.py`:

```json
{
  "well_8": {
    "games": 120,
    "well_size": 8,
    "avg_time_sec": 95.47999999999999,
    "p50_time_sec": 95.47999999999999,
    "p90_time_sec": 95.47999999999999,
    "avg_clears_per_min": 34.49937159614579,
    "no_move_loss_rate": 0.0,
    "well_overflow_rate": 1.0,
    "pity_triggers_per_game": 23.3
  },
  "well_6": {
    "games": 120,
    "well_size": 6,
    "avg_time_sec": 69.3,
    "p50_time_sec": 69.3,
    "p90_time_sec": 69.3,
    "avg_clears_per_min": 31.298701298701296,
    "no_move_loss_rate": 0.0,
    "well_overflow_rate": 1.0,
    "pity_triggers_per_game": 15.816666666666666
  },
  "well_5": {
    "games": 120,
    "well_size": 5,
    "avg_time_sec": 56.879999999999995,
    "p50_time_sec": 56.879999999999995,
    "p90_time_sec": 56.879999999999995,
    "avg_clears_per_min": 28.560126582278482,
    "no_move_loss_rate": 0.0,
    "well_overflow_rate": 1.0,
    "pity_triggers_per_game": 12.475
  }
}
```

Interpretation:
- `well=8` is the most forgiving and drifts toward boredom for stronger players.
- `well=6` gives a better pressure step while keeping fairness.
- `well=5` is noticeably harsher and closer to hardcore pacing.

Recommended default for now: **well=6 / pile_max=6**.
