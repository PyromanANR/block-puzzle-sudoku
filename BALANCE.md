# Balance Specification & Tuning Guide

This document is the **authoritative gameplay-balance reference** for the current codebase. Every value/formula below is taken from code/config; if something is not directly implemented, it is labeled **inference**.

---

## 1) Overview: what “balance” controls

Balance in this project controls these systems:

- **Pacing / falling speed** (piece drop speed curve over runtime, smoothing, hard cap).
- **Global time-scale effects** (No Mercy slow, well-drag slow, auto-slow panic, micro-freeze, first-well-entry slow, time-slow from well placement, freeze skill, invalid-drop fail slow).
- **Generator fairness** (ideal-pick chance, pity triggers, top-band randomization, anti-streak rules, bag usage, piece-pool toggles, force-well logic).
- **Well pressure** (pile size/cap, top-selectable slots, overflow -> game over, danger UI ratios).
- **Dual-drop** (chance ramp + speed-based stagger + minimum spawn gap and fallback).
- **DDA signal updates** (difficulty01 from move time, board fill, cancel rate; affects ideal piece chance).
- **Skills and assist windows** (Freeze, Clear Board, Safe Well, Time Slow, first-entry slow, invalid-drop grace).
- **Scoring/leveling** (score sources in `main.gd`; run-level from `PointsPerLevel`; meta player level from unique played days in save).

---

## 2) Canonical Definitions

- `t_runtime_sec`: real runtime in seconds from `CoreBridge._startMs` (via `Time.GetTicksMsec()`).
- `minutes`: `t_runtime_sec / 60` used by speed and dual-drop ramps.
- `level_run`: run level shown in HUD; computed from score as `1 + floor(max(score,0)/PointsPerLevel)`.
- `difficulty`: Save difficulty string (`Easy`/`Medium`/`Hard`) and `no_mercy` flag.
- `board_fill_ratio`: occupied board cells / 81 (`_board_fill_ratio()`).
- `well_fill_ratio`: `pile.size / pile_max`, clamped `[0,1]` (`_well_fill_ratio()`).
- `danger threshold`:
  - DDA fill threshold: `FillDangerThreshold` (0.72 by default).
  - Auto-slow thresholds: `AutoSlowThresholdBoard`, `AutoSlowThresholdWell` (both 0.85 default).
  - Well danger line ratios for rendering: `DangerLineStartRatio`, `DangerLineEndRatio`.
- `time_scale`: final `Engine.time_scale`, selected as **minimum** of active slow scales, then clamped `[0.05,1.0]`.

---

## 3) Authoritative Difficulty Math

### 3.1 Base speed & ramp

### Runtime falling speed actually used in gameplay

`GetFallSpeed(level)` currently ignores the `level` argument in formula and uses runtime minutes + difficulty-based peak multipliers:

```text
peak1 = max(0.1, SpeedPeak1Minutes)
peak2 = max(peak1 + 0.1, SpeedPeak2Minutes)
peak3 = max(peak2 + 0.1, SpeedPeak3Minutes)

mult1 = {Easy:7, Medium:8, Hard:9}
mult2 = {Easy:10, Medium:12, Hard:14}
mult3 = {Easy:15, Medium:18, Hard:20}

if m <= peak1:
  p = clamp(m/peak1,0,1)
  e = pow(p, max(0.01, SpeedEaseExponent1))
  speedMul = lerp(1, mult1, e)
elif m <= peak2:
  p = clamp((m-peak1)/(peak2-peak1),0,1)
  e = pow(p, max(0.01, SpeedEaseExponent2))
  speedMul = lerp(mult1, mult2, e)
elif m <= peak3:
  p = clamp((m-peak2)/(peak3-peak2),0,1)
  e = pow(p, max(0.01, SpeedEaseExponent2))
  speedMul = lerp(mult2, mult3, e)
else:
  tail = 1 + SpeedTailStrength * log(1 + (m-peak3))
  speedMul = mult3 * tail

target = BaseFallSpeed * speedMul
```

Then speed is smoothed and capped:

```text
dt = max(0.001, (now-lastSpeedCalcMs)/1000)
maxDelta = MaxFallSpeedDeltaPerSec * dt
smoothed = MoveToward(smoothed, target, maxDelta)
smoothed = min(smoothed, MaxFallSpeedCap)
return smoothed
```

**Important implementation fact:** `LevelSpeedGrowth`, `TimeSpeedRampPerMinute`, and DDA fall multiplier (`DdaMinFallMultiplier..DdaMaxFallMultiplier`) are not part of this runtime `GetFallSpeed` formula; they are used in simulator or exposed helpers only. (No inference.)

### 3.2 Final time scale composition (min-of-scales)

`_update_time_scale_runtime()` computes:

```text
final_scale = 1.0
reason = Normal
for each active effect in fixed order:
  if effectScale < final_scale:
    final_scale = effectScale
    reason = effectReason
_set_time_scale(reason, final_scale)   # clamp 0.05..1.0
```

Order (exact):

1. No Mercy extra slow (`GetNoMercyExtraTimeScale(well_fill_ratio)`), only if hard+no_mercy.
2. Well drag slow (`GetWellDragTimeScale(well_fill_ratio)`), only while dragging a piece from well.
3. Auto slow (`GetAutoSlowScale`) while `auto_slow_until_ms` active.
4. Micro freeze fixed scale `0.15` while `micro_freeze_until_ms` active.
5. First well entry slow (`GetWellFirstEntrySlowTimeScale`) while active.
6. Time slow (`GetTimeSlowEffectTimeScale`) while active.
7. Freeze skill (`freeze_effect_multiplier`) while active.
8. Invalid-drop fail slow (`GetInvalidDropFailTimeScale`) while active.

### 3.3 DDA / Auto-slow / Panic

## DDA state update (`DifficultyDirector.Update`)

Per successful move or cancelled drag update:

```text
movePressure   = clamp((AvgMoveTimeSec - TargetMoveTimeSec)/TargetMoveTimeSec, -1, 1)
fillPressure   = clamp((AvgBoardFill - FillDangerThreshold)/0.25, -1, 1)
cancelPressure = clamp(CancelRate, 0, 1)

desired = 0.5 - movePressure*0.25 - fillPressure*0.30 - cancelPressure*0.20
desired = clamp(desired, 0.1, 0.95)

difficulty01 = MoveToward(difficulty01, desired, DdaRatePerMove)
```

`GetIdealPieceChance` uses `difficulty01` via lerp(early->late). `GetFallMultiplier` exists but is not consumed by runtime fall speed.

## What counts as a move

A “move” for DDA/GameMetrics is registered only on successful placement in `_try_place_piece()` with:

- `move_time_sec = max(0.05, (now - drag_start_ms)/1000)`
- `core.RegisterSuccessfulPlacement(cleared_count, move_time_sec, _board_fill_ratio())`

Cancelled drags call `core.RegisterCancelledDrag()`.

## Auto-slow trigger

`ShouldTriggerAutoSlow(boardFill, wellFill)` returns true iff:

- cooldown elapsed (`now - lastAutoSlowMs >= AutoSlowCooldownSec*1000`), and
- at least one threshold crossed (`boardFill >= AutoSlowThresholdBoard` OR `wellFill >= AutoSlowThresholdWell`).

Then main sets `auto_slow_until_ms = now + AutoSlowDurationSec`.

## Panic

Runtime panic SFX pulse is currently hardcoded in `main.gd`: if `well_fill_ratio >= 0.82` and cooldown passed, play panic every 1800 ms. Config panic fields exist and getters exist, but they are not consumed in this check.

### 3.4 Dual-drop (multi-active pieces)

- At spawn scheduling time, `dual_drop_cycle_pending = ConsumeDualDropTrigger()`.
- Trigger chance at runtime minute `m`:

```text
cap = by difficulty: Easy DualDropChanceCapEasy, Medium ...CapMedium, Hard ...CapHard
t = clamp(m / max(0.1, DualDropChanceCapMinutes), 0, 1)
chance = lerp(DualDropChanceStart, cap, t)
```

- If triggered, second piece spawn is delayed by speed-dependent stagger:

```text
speedMul = displayedFallSpeed / BaseFallSpeed
start = max(0.01, DualDropStaggerSpeedStartMul)
end   = max(start+0.01, DualDropStaggerSpeedEndMul)
t = clamp((speedMul-start)/(end-start),0,1)
smooth = t*t*(3-2*t)   # smoothstep
stagger = DualDropStaggerBaseSec + DualDropStaggerExtraSec*smooth
stagger = clamp(stagger, DualDropStaggerBaseSec, DualDropStaggerMaxSec)
```

- Gap protection before second spawn:
  - needs `fall_y >= dual_drop_anchor_y + DualDropMinGapCells*cell_size`, OR
  - fallback timeout 2000 ms reached.

No explicit geometric overlap solver exists besides this vertical-gap + timeout gate.

### 3.5 No Mercy

- Active only if `Save.get_current_difficulty() == "Hard"` and `Save.get_no_mercy() == true`.
- Scale formula:

```text
t = clamp(well_fill_ratio, 0, 1)
noMercyScale = lerp(NoMercyExtraSlowMin, NoMercyExtraSlowMax, t)
```

- It enters the same min-of-scales stack as other slows (section 3.2), so whichever active scale is smallest wins.

---

## 4) Piece Generator & Fairness Spec

Generator selection (`PieceGenerator.PickKind`) for a board-aware request:

1. Evaluate all enabled piece kinds by best achievable placement score (`EvaluateKinds` + `EvaluatePlacement`).
2. Sort descending by score.
3. Compute flags:
   - `pity = (_noProgressMoves >= NoProgressMovesForPity) OR (_spawnSincePity >= PityEveryNSpawns)`.
   - `forceWell = secondsSinceLastWell >= ForceWellAfterSeconds OR piecesSinceWell >= ForceWellEveryNPieces`.
   - `dynamicWellChance = lerp(WellSpawnChanceEarly, WellSpawnChanceLate, clamp(secondsSinceLastWell/60,0,1))`.
   - `requestWell = forceWell OR rand <= dynamicWellChance`.
4. If `requestWell` and any well-kind exists in evaluated list, choose first well-kind candidate.
5. Else normal branch:
   - `useIdeal = pity OR rand <= idealChance`.
   - if `useIdeal`: choose best evaluated[0], reset `_spawnSincePity`; increment pity counter if pity path used.
   - else choose random from top `min(CandidateTopBand, evaluated.Count)`.
6. Run anti-streak guard `EnforceMaxStreak` (`GeneratorMaxSameInRow`, history window `GeneratorHistoryLen`).

### Fairness controls present

- **Ideal chance**:
  - From DDA: `lerp(IdealPieceChanceEarly, IdealPieceChanceLate, difficulty01)`.
  - Then runtime decay in CoreBridge: `- IdealChanceDecayPerMinute * elapsedMinutes`, clamped by `IdealChanceFloor`.
- **Pity**: `NoProgressMovesForPity`, `PityEveryNSpawns`; reset on ideal/pity consume branch.
- **History / anti-streak**: `GeneratorMaxSameInRow`, `GeneratorHistoryLen`.
- **Force-well**: `ForceWellAfterSeconds`, `ForceWellEveryNPieces`, plus probabilistic well request with `WellSpawnChanceEarly/Late`.
- **Pool filters**: `PiecePoolEnableDomino`, `PiecePoolEnableTromino`, `PiecePoolEnablePentominoLite`, `GeneratorUseBag`.
- **Heuristic scoring constants** (hardcoded): line/block bonuses and `Plus5` penalty factor 0.80.

---

## 5) Well / Pile mechanics

- Well settings come from `core.GetWellSettings()`: `pile_max`, `top_selectable`, `pile_visible`, danger ratios.
- At runtime, `ApplyDifficultyFromSave()` overrides some config values:
  - Easy: `PileMax=8`, `TopSelectable=3`.
  - Medium: `PileMax=7`, `TopSelectable=2`.
  - Hard: `PileMax=6`, `TopSelectable=1`; if no-mercy then `TopSelectable=0`.
  - Also sets `WellSize = PileMax`.
- Falling piece commit to well on touching fall bottom.
- Overflow condition: if `pile.size() > pile_max` after commit -> game over.
- Safe Well active: committed falling pieces are discarded (not appended to pile).
- First-well-entry slow triggers once per non-empty cycle; resets when pile becomes empty after a board placement from well.
- Well pressure influences:
  - No Mercy slow scale.
  - Well-drag slow scale.
  - Auto-slow trigger (well threshold).
  - Panic SFX/visual pulse gate.

---

## 6) Skills / Abilities catalog

### Freeze (`try_use_freeze`)

- Unlock: `freeze_unlocked` (player level >=5 from Save recompute rules).
- Runtime constants: `FREEZE_DURATION_MS=5000`, `FREEZE_MULTIPLIER=0.10`, cooldown `FREEZE_CD_MS=30000`, charges `freeze_charges_max=3`.
- Effect: sets `freeze_effect_multiplier` (clamped `[0.05,1.0]`) until timeout.
- Time-scale integration: included as `FreezeSkill` in min-stack.
- Note: `used_freeze_this_round` exists but is not enforced in `try_use_freeze`.

### Clear Board (`try_use_clear_board`)

- Unlock: `clear_board_unlocked` (level >=10).
- Cooldown `CLEAR_CD_MS=45000`, charges `clear_charges_max=2`.
- Effect: board reset + score gain `filled_cells * CLEAR_BOARD_POINTS_PER_CELL`.

### Safe Well (`try_use_safe_well`)

- Unlock: `safe_well_unlocked` (level >=20).
- Cooldown `SAFE_WELL_CD_MS=60000`, charges `safe_well_charges_max=1`, duration `SAFE_WELL_DURATION_MS=7000`.
- Effect: clear pile immediately and discard incoming committed falling pieces while active.

### Time Slow (well-placement mechanic, not button-cast)

- Trigger: successful placement of piece taken from well.
- Cooldown `TimeSlowCooldownSec`, effect duration `TimeSlowEffectDurationSec`, scale `TimeSlowEffectTimeScale`.
- Also drives short overlay (`TimeSlowReadyOverlayDurationSec`) and SFX path (`TimeSlowReadySfxPath`).

### First Well Entry Slow

- Trigger: first falling-piece commit into non-empty cycle.
- Duration `WellFirstEntrySlowDurationSec`, scale `WellFirstEntrySlowTimeScale`.

### Invalid Drop Grace / Fail Slow

- On failed release: spawn temporary grace pickup window (`InvalidDropGraceSec`).
- If grace expires without re-grab and piece still valid grace target: apply fail slow for `InvalidDropFailSlowSec` with scale `InvalidDropFailTimeScale`.

### Micro Freeze (commit feedback)

- Trigger: on commit to well.
- Duration `MicroFreezeSec`, fixed time-scale in stack = `0.15` (hardcoded).

---

## 7) Anti-exploit & penalties

Implemented anti-exploit/assist behaviors:

- **Auto-snap protection**:
  - Only for non-well source drags, within radius (`AUTO_SNAP_RADIUS`), trajectory gate (`AUTO_SNAP_MIN_DOT`, min drag distance), and cooldown (`AUTO_SNAP_COOLDOWN_MS`).
- **Cancelled-drag tracking**: invalid drop path calls `RegisterCancelledDrag()` (feeds DDA cancel pressure).
- **Invalid-drop grace**: temporary reclaim window to avoid accidental fails; after timeout applies fail slow.
- **Grace re-grab blocking**: piece metadata (`grace_blocked`) prevents race-condition re-grab of committed piece.
- **Reroll prevention fields**: `MaxRerollsPerRound` in config and `reroll_uses_left` var exist, but no active reroll flow is implemented in current runtime path.
- **Penalty score/XP**: no direct score deduction or XP penalty logic found in current runtime. (`CancelDragPenalty` exists in config but not applied in gameplay code.)

---

## 8) XP / Leveling / Rewards

Two distinct progression tracks exist:

1. **Run level (in-round HUD):**
   - `level_run = 1 + floor(max(score,0)/PointsPerLevel)`.
   - score sources in `main.gd`:
     - +piece cell count on placement,
     - +`cleared_count * 2`,
     - +rescue bonus (`RescueScoreBonus`) when conditions met,
     - +clear-board bonus (`filled_cells * CLEAR_BOARD_POINTS_PER_CELL`).

2. **Meta player level (save/profile):**
   - `player_level = unique_days_played.size()`.
   - unlocks recomputed from player_level thresholds (Freeze 5, Clear 10, Safe Well 20, etc.).

`ProgressManager.get_xp()` reads `player_xp`, but no gameplay XP accumulation formula is implemented in examined runtime files (inference: legacy/placeholder accessor).

---

## 9) Parameter Index (complete)

Legend:
- Units: `mul` multiplier, `chance` in `[0..1]`, `sec`, `min`, `count`, `cells`, `points`.
- Safe tuning range: `unknown` unless bounded by clamps/logic.
- Where used: function-level location.

### 9.1 Speed & ramp

- `BaseFallSpeed` | mul(base speed) | 18.0 | unknown | `CoreBridge.GetFallSpeed`, `GetBaseFallSpeed`.
- `MaxFallSpeedCap` | speed cap | 500.0 | >= BaseFallSpeed | `CoreBridge.GetFallSpeed`.
- `MaxFallSpeedDeltaPerSec` | speed/sec | 26.0 | >0 | `CoreBridge.GetFallSpeed` smoothing.
- `SpeedPeak1Minutes` | min | 3.0 | >0 (clamped to >=0.1) | `CoreBridge.GetFallSpeed`.
- `SpeedPeak2Minutes` | min | 6.0 | >peak1 (code enforces +0.1) | `CoreBridge.GetFallSpeed`.
- `SpeedPeak3Minutes` | min | 10.0 | >peak2 (code enforces +0.1) | `CoreBridge.GetFallSpeed`.
- `SpeedEaseExponent1` | exponent | 2.0 | >0 (clamped >=0.01) | `CoreBridge.GetFallSpeed`.
- `SpeedEaseExponent2` | exponent | 2.0 | >0 (clamped >=0.01) | `CoreBridge.GetFallSpeed`.
- `SpeedTailStrength` | mul | 0.08 | unknown | `CoreBridge.GetFallSpeed`, `GetSpeedTailMultiplier`.
- `KneeMultEasy` | mul | 8.0 | unknown | **Declared only** in config/class; runtime uses hardcoded peak multipliers.
- `KneeMultMedium` | mul | 9.0 | unknown | declared only.
- `KneeMultHard` | mul | 10.0 | unknown | declared only.
- `LevelSpeedGrowth` | mul per level | 1.16 | unknown | used in `SimulationRunner`, exposed by getter; not in runtime fall-speed path.
- `TimeSpeedRampPerMinute` | mul/min | 0.16 | unknown | declared only (not consumed in current runtime/sim).
- `DdaMinFallMultiplier` | mul | 0.9 | [0..] | used by `DifficultyDirector.GetFallMultiplier` (not applied to runtime fall speed).
- `DdaMaxFallMultiplier` | mul | 1.28 | [>=min] | same as above.

### 9.2 Time scale reasons / slows

- `NoMercyExtraSlowMin` | mul | 0.7 | [0..1] | `CoreBridge.GetNoMercyExtraTimeScale`.
- `NoMercyExtraSlowMax` | mul | 0.4 | [0..1] | same.
- `WellDragSlowMin` | mul | 0.8 | [0..1] | `CoreBridge.GetWellDragTimeScale`.
- `WellDragSlowMax` | mul | 0.4 | [0..1] | same.
- `AutoSlowScale` | mul | 0.75 | [0..1] | `CoreBridge.GetAutoSlowScale`; consumed in stack.
- `AutoSlowDurationSec` | sec | 1.0 | >0 | `main._trigger_auto_slow_if_needed`.
- `MicroFreezeSec` | sec | 0.1 | >0 | `main._trigger_micro_freeze`.
- `WellFirstEntrySlowDurationSec` | sec | 1.5 | >0 | `main._try_trigger_first_well_entry_slow`.
- `WellFirstEntrySlowTimeScale` | mul | 0.5 | [0..1] | time-scale stack.
- `TimeSlowCooldownSec` | sec | 60.0 | >0 | `_try_trigger_time_slow_from_well_placement`.
- `TimeSlowReadyOverlayDurationSec` | sec | 0.8 | >0 | overlay timing + shader fill calc.
- `TimeSlowReadySfxPath` | path | `res://Assets/Audio/time_slow.wav` | unknown | `_audio_setup`.
- `TimeSlowEffectDurationSec` | sec | 5.0 | >0 | time-slow activation window.
- `TimeSlowEffectTimeScale` | mul | 0.55 | [0..1] | time-scale stack.
- `InvalidDropFailSlowSec` | sec | 0.4 | >0 | pending-invalid timeout branch.
- `InvalidDropFailTimeScale` | mul | 0.85 | [0..1] | time-scale stack.
- `InvalidDropGraceSec` | sec | 1.2 | >0 | pending-invalid grace timer.
- hardcoded `micro_scale` | mul | 0.15 | unknown | `main._update_time_scale_runtime`.

### 9.3 DDA / panic / rescue

- `TargetMoveTimeSec` | sec | 2.1 | >0 | `DifficultyDirector.Update`.
- `FillDangerThreshold` | ratio | 0.72 | [0..1] | `DifficultyDirector.Update`.
- `DdaRatePerMove` | per-move step | 0.1 | [0..1] | `DifficultyDirector.Update`.
- `AutoSlowThresholdBoard` | ratio | 0.85 | [0..1] | `CoreBridge.ShouldTriggerAutoSlow`.
- `AutoSlowThresholdWell` | ratio | 0.85 | [0..1] | same.
- `AutoSlowCooldownSec` | sec | 10.0 | >0 | same.
- `RescueWindowSec` | sec | 3.0 | >0 | set when drag starts from well.
- `RescueScoreBonus` | points | 80 | >=0 | awarded on successful rescue placement.
- `RescueStabilityDurationSec` | sec | 5.0 | >0 | `CoreBridge.TriggerRescueStability` only (no downstream runtime effect found).
- `RescueStabilityGrowthMul` | mul | 0.5 | unknown | declared only.
- `PanicPulseSpeed` | hz-ish | 2.0 | unknown | getter exists, not used in panic gate.
- `PanicBlinkSpeed` | hz-ish | 7.0 | unknown | getter exists, not used in panic gate.
- `PanicBlinkThreshold` | ratio | 0.85 | unknown | getter exists, not used in panic gate.

### 9.4 Dual-drop

- `DualDropChanceStart` | chance | 0.05 | [0..1] | `CoreBridge.GetDualDropChanceCurrent`.
- `DualDropChanceCapMinutes` | min | 8.0 | >0 (clamped >=0.1) | same.
- `DualDropChanceCapEasy` | chance | 0.1 | [0..1] | same.
- `DualDropChanceCapMedium` | chance | 0.15 | [0..1] | same.
- `DualDropChanceCapHard` | chance | 0.2 | [0..1] | same.
- `DualDropMinGapCells` | cells | 2.0 | >=0 | `main._dual_drop_can_spawn`.
- `DualDropStaggerBaseSec` | sec | 1.0 | >0 | `CoreBridge.GetDualDropStaggerSecForSpeedMul`.
- `DualDropStaggerExtraSec` | sec | 0.6 | >=0 | same.
- `DualDropStaggerSpeedStartMul` | mul | 7.0 | >0 | same.
- `DualDropStaggerSpeedEndMul` | mul | 14.0 | >start | same.
- `DualDropStaggerMaxSec` | sec | 1.8 | >=base | same.
- `DualDropStaggerSec` | sec | 1.0 | unknown | declared but not used by runtime stagger function.

### 9.5 Generator / fairness / piece pool

- `IdealPieceChanceEarly` | chance | 0.46 | [0..1] | `DifficultyDirector.GetIdealPieceChance`.
- `IdealPieceChanceLate` | chance | 0.12 | [0..1] | same.
- `IdealChanceDecayPerMinute` | chance/min | 0.16 | unknown | `CoreBridge.ComputeIdealChance`.
- `IdealChanceFloor` | chance | 0.06 | [0..1] | same.
- `PityEveryNSpawns` | count | 9999 | >=1 | `PieceGenerator.PickKind`.
- `NoProgressMovesForPity` | count | 5 | >=0 | same.
- `CandidateTopBand` | count | 8 | >=1 | same.
- `WellSpawnChanceEarly` | chance | 0.16 | [0..1] | same.
- `WellSpawnChanceLate` | chance | 0.26 | [0..1] | same.
- `ForceWellAfterSeconds` | sec | 30 | >=0 | same.
- `ForceWellEveryNPieces` | count | 6 | >=0 | same.
- `GeneratorMaxSameInRow` | count | 2 | >=1 (code max(1,..)) | streak guard.
- `GeneratorHistoryLen` | count | 6 | >=1 (code max(1,..)) | recent history trim.
- `GeneratorUseBag` | bool | true | n/a | queue refill behavior.
- `PiecePoolEnableDomino` | bool | true | n/a | enabled kinds.
- `PiecePoolEnableTromino` | bool | true | n/a | enabled kinds.
- `PiecePoolEnablePentominoLite` | bool | true | n/a | enabled kinds.

### 9.6 Well / pile / visuals

- `WellSize` | count | 6 | unknown | exported via `GetWellSettings`; overwritten by difficulty in `ApplyDifficultyFromSave`.
- `PileMax` | count | 6 | >=1 | same + overflow game-over behavior.
- `TopSelectable` | count | 3 | >=0 | same + well pickability logic.
- `PileVisible` | count | 8 | >=0 | exported in settings.
- `DangerLineStartRatio` | ratio | 0.64 | [0..1] | applied from settings to main UI state.
- `DangerLineEndRatio` | ratio | 0.84 | [0..1] | same.
- `WellNeonPulseSpeed` | speed | 2.5 | >0 | well slot neon animation phase.
- `WellNeonMinAlpha` | alpha | 0.4 | [0..1] | same.
- `WellNeonMaxAlpha` | alpha | 1.0 | [0..1] | same.

### 9.7 Skills / scoring / leveling / anti-exploit

- `PointsPerLevel` | points | 360 | >=1 (guarded) | `CoreBridge.GetLevelForScore`.
- `SimulationMaxMoves` | count | 320 | >=1 | `SimulationRunner.RunBatch`.
- `MaxRerollsPerRound` | count | 0 | unknown | declared, no runtime use found.
- `CancelDragPenalty` | value | 0.02 | unknown | declared, no runtime use found.

### 9.8 JSON keys present but not deserialized by `BalanceConfig`

These keys are in `balance_config.json` but have no matching field in `BalanceConfig` (therefore ignored at load time):

- `SpeedKneeMinutes`
- `FastNextChanceStart`
- `FastNextChanceAtKneeEasy`
- `FastNextChanceAtKneeMedium`
- `FastNextChanceAtKneeHard`
- `FastNextChanceCapEasy`
- `FastNextChanceCapMedium`
- `FastNextChanceCapHard`
- `FastNextCapMinutes`
- `PostKneeTailStrength`
- `SpeedEaseExponent`
- `FastNextDelayMul`

---

## 10) Tuning Guide (cookbook)

### A) Make early game calmer

Adjust:
- `BaseFallSpeed` down.
- `SpeedPeak1Minutes` up (longer first segment).
- `SpeedEaseExponent1` up (slower start in segment A).
- `DualDropChanceStart` down.
- `WellSpawnChanceEarly` down (if well pressure feels too fast).

Why: these directly reduce early velocity and multi-active pressure.

### B) Make mid-game peak sharper

Adjust:
- `SpeedPeak1Minutes` and `SpeedPeak2Minutes` closer together.
- `SpeedEaseExponent2` down (steeper interpolation through B/C).
- hardcoded peak multipliers are in code (`GetPeak*TargetMultiplier`), so changing only JSON cannot raise those targets beyond current code.

Why: slope between peak milestones determines perceived acceleration.

### C) Reduce repeated pieces

Adjust:
- `GeneratorMaxSameInRow` lower (typically 1 or 2).
- `GeneratorHistoryLen` higher.
- keep `GeneratorUseBag=true`.

Why: these are direct anti-streak controls.

### D) Make No Mercy less punishing

Adjust:
- Raise `NoMercyExtraSlowMin` and/or `NoMercyExtraSlowMax` toward 1.0.
- Optionally raise `TopSelectable` for Hard mode in `ApplyDifficultyFromSave` (requires code change; inference).

Why: No Mercy enters min-stack and can dominate time scale at high well fill.

### E) Increase well attractiveness

Adjust:
- Raise `WellSpawnChanceEarly/Late`.
- Lower `ForceWellAfterSeconds` and/or `ForceWellEveryNPieces`.
- Increase `RescueScoreBonus` / `RescueWindowSec` if you want stronger reward loop.

Why: these directly increase well-piece supply and reward successful well rescues.

---

## Coverage checklist

- [x] Speed/pacing (base speed, curve, smoothing, cap)
- [x] Time-scale composition and priority order
- [x] DDA / auto-slow / panic behavior
- [x] Dual-drop chance + stagger + gap protection
- [x] No Mercy rules and combination with drag slow
- [x] Piece generator fairness, pity, anti-streak, force-well, pool toggles
- [x] Well/pile mechanics and overflow pressure
- [x] Skills/abilities including Freeze/Clear/SafeWell/TimeSlow/first-entry/invalid-drop
- [x] Anti-exploit & penalties (implemented and declared-but-unused)
- [x] Scoring/run-level and meta leveling
- [x] Full `balance_config.json` parameter coverage, including ignored keys
