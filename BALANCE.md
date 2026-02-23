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
=======
# Balance Design (Sudoku-like + Falling Blocks Hybrid)

## A) Research notes (short)

### Sources
1. Tetris Wiki — Random Generator (7-bag): https://tetris.wiki/Random_Generator
2. Tetris Wiki — Tetris Guideline: https://tetris.wiki/Tetris_Guideline
3. Hard Drop Wiki — Random Generator: https://harddrop.com/wiki/Random_Generator
4. Hunicke (AIIDE) — The Case for Dynamic Difficulty Adjustment in Games: https://www.researchgate.net/publication/220876993_The_case_for_dynamic_difficulty_adjustment_in_games
5. Csikszentmihalyi — Flow theory overview: https://en.wikipedia.org/wiki/Flow_(psychology)
6. GDC math systems/balance talks index: https://www.gdcvault.com/browse/gdc-24/?media=v
7. Puzzle design analyses (Deconstructor of Fun): https://www.deconstructoroffun.com/blog
8. Board game randomness & mitigation theory (choice architectures): https://boardgamegeek.com/wiki/page/Mechanics

### Practical conclusions used in this project
- Fair randomness is usually **constrained randomness**, not pure RNG.
- “7-bag-like feeling” lowers extreme droughts and improves perceived fairness.
- In hybrid puzzle games, fairness comes from **candidate filtering** over current board state.
- A robust “no random death” policy needs **pity** (guaranteed helpful outcome every N spawns).
- Good early game should bias toward low-friction pieces (small/simple geometry).
- Difficulty should move slowly (rate-limited DDA), never swing hard every move.
- Useful DDA signals for this genre: average move time, board fill pressure, cancel/failed action rate.
- Player-error and generator-error must be separated in telemetry.
- “Almost complete line/block” opportunities are a strong predictor of engagement.
- A soft assistance channel (ideal piece chance) is less intrusive than hard cheating.
- Anti-exploit rules are part of balance: no free reroll by tap/release.
- Mid/late challenge should rise by pace + planning pressure, not impossible piece rolls.

## B) Design target

- **Novice (2–3 min):** game is readable and forgiving; generator strongly prefers useful shapes.
- **Intermediate (5–10 min):** stable progression with pressure from speed and queue management.
- **Skilled:** fast but fair; risk-management depth from choosing placement quality under time.

### Core loop
1. Falling piece arrives from well.
2. Player chooses fast placement on board.
3. Board clears rows/columns/3x3.
4. Metrics update -> DDA adjusts fall pace + ideal-piece probability.
5. Repeat until overflow/no valid continuation.

### Error taxonomy
- **Player mistake:** valid alternatives existed, but placement increased long-term board pressure.
- **Generator mistake:** no practical progress options for multiple turns despite legal placements.
- **Prevention:** constrained generation + pity system + rate-limited DDA assistance.

## C) Tuning knobs (all centralized)

Config file: `Scripts/Core/balance_config.json`

- `BaseFallSpeed`, `LevelSpeedGrowth`
- `DdaMinFallMultiplier`, `DdaMaxFallMultiplier`
- `IdealPieceChanceEarly`, `IdealPieceChanceLate`
- `PityEveryNSpawns`
- `CandidateTopBand`
- `TargetMoveTimeSec`, `FillDangerThreshold`, `DdaRatePerMove`
- `CancelDragPenalty`, `MaxRerollsPerRound`
- `SimulationMaxMoves`

## D) Simulation mode

- Added `SimulationRunner` with batch method callable from `CoreBridge.RunSimulationBatch`.
- A quick debug trigger is wired into Settings button in current scene script.
- Output metrics include average moves, average clears, no-move loss rate.

## E) Architecture

- `PieceGenerator` — constrained fair-random generation + pity.
- `DifficultyDirector` — soft DDA with clamp/rate-limit.
- `GameMetrics` — rolling metrics for adaptation.
- `SimulationRunner` — repeated bot runs for balancing.
- `BalanceConfig` (+ JSON) — all tuneable knobs in one place.


## F) Default simulation snapshot

From `tools_simulate_balance.py` with current default config:

```json
{
  "games": 120,
  "avg_moves": 250.0,
  "avg_clears": 357.28333333333336,
  "no_move_loss_rate": 0.0,
  "total_no_move_losses": 0
}
```

Interpretation:
- `well=8` is the most forgiving and drifts toward boredom for stronger players.
- `well=6` gives a better pressure step while keeping fairness.
- `well=5` is noticeably harsher and closer to hardcore pacing.

Recommended default for now: **well=6 / pile_max=6**.
- Current defaults are strongly assistance-heavy (no-move loss ~0 in 120 runs).
- For harder mid/late game, lower `IdealPieceChanceLate` and/or raise `LevelSpeedGrowth`.
