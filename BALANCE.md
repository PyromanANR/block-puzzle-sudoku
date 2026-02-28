# BALANCE

## Current Build Snapshot (Single Source of Truth)

- Snapshot date: **2026-02-28**
- Gameplay scene/controller truth:
  - Scene: `res://Scenes/Main.tscn`
  - GDScript controller: `res://Scripts/main.gd`
- Core config truth: `Scripts/Core/balance_config.json`
- Core bridge truth: `Scripts/Core/CoreBridge.cs`
- Balance-relevant `core.call("...")` currently used in `main.gd`:
  - Well/timings: `GetWellSettings`, `GetFallSpeed`, `GetBaseFallSpeed`
  - Time Slow: `GetTimeSlowCooldownSec`, `GetTimeSlowEffectDurationSec`, `GetTimeSlowEffectTimeScale`, `GetTimeSlowReadyOverlayDurationSec`, `GetTimeSlowReadySfxPath`
  - Time-scale stack: `GetNoMercyExtraTimeScale`, `GetWellDragTimeScale`, `GetAutoSlowScale`, `GetWellFirstEntrySlowTimeScale`, `GetInvalidDropFailTimeScale`
  - Related runtime triggers: `ShouldTriggerAutoSlow`, `GetAutoSlowDurationSec`, `GetMicroFreezeSec`, `GetInvalidDropGraceSec`, `GetInvalidDropFailSlowSec`

## Constants & Tunables (Exact Values + Where)

### Skills / cooldowns / charges (GDScript)

| Key | Value | Where |
|---|---:|---|
| `FREEZE_DURATION_MS` | `5000` | `Scripts/main.gd` |
| `FREEZE_MULTIPLIER` | `0.10` | `Scripts/main.gd` |
| `SAFE_WELL_DURATION_MS` | `7000` | `Scripts/main.gd` |
| `FREEZE_CD_MS` | `30000` | `Scripts/main.gd` |
| `CLEAR_CD_MS` | `45000` | `Scripts/main.gd` |
| `SAFE_WELL_CD_MS` | `60000` | `Scripts/main.gd` |
| `freeze_charges_max` | `3` | `Scripts/main.gd` |
| `clear_charges_max` | `2` | `Scripts/main.gd` |
| `safe_well_charges_max` | `1` | `Scripts/main.gd` |
| Runtime counters | `freeze_charges_current`, `clear_charges_current`, `safe_well_charges_current` | `Scripts/main.gd` |
| Clear-board score factor | `CLEAR_BOARD_POINTS_PER_CELL = 1` | `Scripts/main.gd` |

> Note: code truth in current build: `freeze_charges_max := 3`, `clear_charges_max := 2`, `safe_well_charges_max := 1`.

### Unlock levels (GDScript + Save)

- Freeze unlock: level **5** (`freeze_unlocked`)
- Clear Board unlock: level **10** (`clear_board_unlocked`)
- Safe Well unlock: level **20** (`safe_well_unlocked`)

### Audio (GDScript)

- `MUSIC_ATTENUATION_LINEAR = 0.2` (effective music = UI slider × 0.2).
- SFX keys used by gameplay/skills include:
  - `skill_ready`, `freeze_cast`, `safe_well_cast`, `panic`, `game_over`
  - Also present in current setup: `skill_freeze`, `skill_safe_well`, `safe_well_doors_open`, `safe_well_doors_close`, `safe_well_lock_clink`, `time_slow`, `clear`, `pick`, `place`, `invalid`, `well_enter`, `ui_click`, `ui_hover`.

### Well / timings (GDScript + Core config)

- `NORMAL_RESPAWN_DELAY_MS = 260` (`Scripts/main.gd`).
- Well settings are read via `core.call("GetWellSettings")` in `_apply_balance_well_settings()`.
- CoreBridge mapping (`GetWellSettings`) exposes these keys:
  - `pile_max` ← `PileMax`
  - `top_selectable` ← `TopSelectable`
  - `danger_start_ratio` ← `DangerLineStartRatio`
  - `danger_end_ratio` ← `DangerLineEndRatio`
- Current config values in `balance_config.json`:
  - `PileMax = 6`
  - `TopSelectable = 3`
  - `DangerLineStartRatio = 0.64`
  - `DangerLineEndRatio = 0.84`

## Skills (Design + Runtime Rules)

- Total skills: **3** (Freeze, Clear Board, Safe Well)

### Freeze

- Unlock: **Lv 5**
- Charges per round: `freeze_charges_max` (**3** in current code)
- Cooldown: `FREEZE_CD_MS` (**30000 ms / 30s**)
- Effect duration: `FREEZE_DURATION_MS` (**5000 ms / 5s**)
- Effect strength: `FREEZE_MULTIPLIER = 0.10`
  - Runtime clamp in `apply_freeze`: `clamp(multiplier, 0.05, 1.0)`.
- Restrictions:
  - `used_freeze_this_round` flag exists and is used by UI-ready logic.
  - In current `try_use_freeze()` there is **no early return check** for `used_freeze_this_round`; practical limiting is by charges (`freeze_charges_current`) + cooldown.
- UI:
  - State labels: `Ready / CD / Active / Used / Locked`
  - Radial cooldown wedge via `CooldownRadial`.

### Clear Board

- Unlock: **Lv 10**
- Charges: `clear_charges_max` (**2**)
- Cooldown: `CLEAR_CD_MS` (**45000 ms / 45s**)
- Effect: board reset (`board.call("Reset")`) + scoring by `CLEAR_BOARD_POINTS_PER_CELL = 1`.
- Restrictions: hard one-per-round check via `used_clear_board_this_round` in `try_use_clear_board()`.

### Safe Well

- Unlock: **Lv 20**
- Charges: `safe_well_charges_max` (**1**)
- Cooldown: `SAFE_WELL_CD_MS` (**60000 ms / 60s**)
- Duration: `SAFE_WELL_DURATION_MS` (**7000 ms / 7s**)
- Effect:
  - Immediately clears well (`pile.clear()`).
  - While active, falling pieces committed to well are discarded safely (no pile append).
- Restrictions: hard one-per-round check via `used_safe_well_this_round`.

### Time Slow (Well-triggered mechanic)

- Trigger source: `_try_trigger_time_slow_from_well_placement()`.
- Trigger condition: successful placement that came from WELL (`placed_from_well`).
- Cooldown sec: `core.call("GetTimeSlowCooldownSec")` → config key `TimeSlowCooldownSec = 60.0`.
- Effect duration sec: `core.call("GetTimeSlowEffectDurationSec")` → `TimeSlowEffectDurationSec = 5.0`.
- Effect scale: `core.call("GetTimeSlowEffectTimeScale")` → `TimeSlowEffectTimeScale = 0.55`.
- Overlay duration sec: `core.call("GetTimeSlowReadyOverlayDurationSec")` → `TimeSlowReadyOverlayDurationSec = 0.8`.
- UI expand rule: `_is_time_slow_column_expanded()`:
  - expanded if effect is active, or overlay visible, or cooldown ever started (`time_slow_cooldown_until_ms > 0`).

## Time Scale Priority (Order of Overrides)

Exact order in `_update_time_scale_runtime()` (minimum scale wins; final clamp in `_set_time_scale` is `0.05..1.0`):

1. No Mercy extra scale: `core.call("GetNoMercyExtraTimeScale", well_fill_ratio)`
2. WellDrag while dragging: `core.call("GetWellDragTimeScale", well_fill_ratio)`
3. AutoSlow while `auto_slow_until_ms` active: `core.call("GetAutoSlowScale")`
4. MicroFreeze fixed scale `0.15` while `micro_freeze_until_ms` active
5. WellFirstEntry while `well_first_entry_slow_until_ms` active: `core.call("GetWellFirstEntrySlowTimeScale")`
6. TimeSlow while `time_slow_effect_until_ms` active: `core.call("GetTimeSlowEffectTimeScale")`
7. FreezeSkill while `is_freeze_active()`: `freeze_effect_multiplier`
8. InvalidDropFail while `invalid_drop_slow_until_ms` active: `core.call("GetInvalidDropFailTimeScale")`
9. Final apply: `_set_time_scale(reason, scale)` with clamp `0.05..1.0`

## UI Overlay Texts (Exact strings + sizes + placement)

- Charges label:
  - Exact format: `"%d×"`
  - Placement: **top-right** (`Control.PRESET_TOP_RIGHT`, right-aligned)
  - Font size: `24`
- State label strings (exact code truth):
  - `Locked`, `CD`, `Active`, `Used`, `Ready`
  - Placement: **bottom-center** (`Control.PRESET_BOTTOM_WIDE`, centered)
  - Font size: `24`

## Known Issues / TODO (Only facts)

- `used_freeze_this_round` exists but is not set to `true` in `try_use_freeze()`; unlike Clear Board / Safe Well, Freeze is not hard-blocked by this flag in runtime use path.
- Previous docs that state `freeze_charges_max = 1` are stale for current build; code truth is `2`.
- If design requires strict “1 use per round” for Freeze, this needs code change (not applied here).

## Snapshot checklist

- Freeze: Ready → Active (5s) → CD (30s) → Ready (SFX only on transition, not on run start).
- Clear Board: clears board + applies score using `CLEAR_BOARD_POINTS_PER_CELL`.
- Safe Well: clears well + safe-discard for falling pieces while active.
- Time Slow: triggers only from placement from well; UI column expands after first trigger.
