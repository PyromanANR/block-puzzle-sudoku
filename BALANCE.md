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
- Current defaults are strongly assistance-heavy (no-move loss ~0 in 120 runs).
- For harder mid/late game, lower `IdealPieceChanceLate` and/or raise `LevelSpeedGrowth`.
