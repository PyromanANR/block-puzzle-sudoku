using Godot;
using Godot.Collections;
using System.Collections.Generic;

public partial class CoreBridge : Node
{
    private readonly RandomNumberGenerator _rng = new();

    private BalanceConfig _config;
    private PieceGenerator _generator;
    private readonly GameMetrics _metrics = new();
    private readonly DifficultyDirector _director = new();
    private ulong _startMs;

    private BoardModel _activeBoard;
    private float _smoothedFallSpeed;
    private float _lastTargetSpeed;
    private ulong _lastSpeedCalcMs;
    private ulong _lastDebugSpeedLogMs;

    private string _difficulty = "Medium";
    private bool _noMercy = false;

    private ulong _lastAutoSlowMs;
    private ulong _rescueStabilityUntilMs;

    public override void _Ready()
    {
        _rng.Randomize();
        _config = BalanceConfig.LoadOrDefault("res://Scripts/Core/balance_config.json");
        GD.Print($"BalanceConfig loaded: BaseFallSpeed={_config.BaseFallSpeed}, MaxFallSpeedCap={_config.MaxFallSpeedCap}");
        if (_config.MaxFallSpeedCap / Mathf.Max(0.001f, _config.BaseFallSpeed) < 10f)
            GD.PushWarning("BalanceConfig sanity: MaxFallSpeedCap seems low; speed may clamp early.");
        _generator = new PieceGenerator(_rng, _config);

        _startMs = Time.GetTicksMsec();
        _lastSpeedCalcMs = _startMs;
        _lastDebugSpeedLogMs = _startMs;
        ApplyDifficultyFromSave();
        _smoothedFallSpeed = _config.BaseFallSpeed;
        _lastTargetSpeed = _smoothedFallSpeed;
    }


    public void ApplyDifficultyFromSave()
    {
        var save = GetNodeOrNull<Node>("/root/Save");
        if (save == null)
            return;

        _difficulty = save.Call("get_current_difficulty").AsString();
        _noMercy = save.Call("get_no_mercy").AsBool();

        int pileMax = 7;
        int topSelectable = 2;

        if (_difficulty == "Easy")
        {
            pileMax = 8;
            topSelectable = 3;
        }
        else if (_difficulty == "Hard")
        {
            pileMax = 6;
            topSelectable = _noMercy ? 0 : 1;
        }

        _config.PileMax = pileMax;
        _config.WellSize = pileMax;
        _config.TopSelectable = topSelectable;
    }

    public BoardModel CreateBoard()
    {
        var b = new BoardModel();
        b.Reset();
        _activeBoard = b;
        return b;
    }

    // Compatibility API for callers without explicit board argument.
    public PieceData PeekNextPiece() => _generator.Peek(_activeBoard, ComputeIdealChance(), _difficulty, GetElapsedSeconds());

    // Compatibility API for callers without explicit board argument.
    public PieceData PopNextPiece() => _generator.Pop(_activeBoard, ComputeIdealChance(), _difficulty, GetElapsedSeconds());

    public PieceData PeekNextPieceForBoard(BoardModel board)
    {
        return _generator.Peek(board, ComputeIdealChance(), _difficulty, GetElapsedSeconds());
    }

    public PieceData PopNextPieceForBoard(BoardModel board)
    {
        return _generator.Pop(board, ComputeIdealChance(), _difficulty, GetElapsedSeconds());
    }

    private PieceData _holdPiece = null;
    private bool _holdUsed = false;

    public PieceData HoldSwap(PieceData current)
    {
        if (current == null)
            return null;

        if (_holdUsed)
            return current;

        _holdUsed = true;

        if (_holdPiece == null)
        {
            _holdPiece = ClonePiece(current);
            return _generator.Pop(_activeBoard, ComputeIdealChance(), _difficulty, GetElapsedSeconds());
        }

        var outPiece = _holdPiece;
        _holdPiece = ClonePiece(current);
        return outPiece;
    }

    public void ResetHoldUsage() => _holdUsed = false;

    private static PieceData ClonePiece(PieceData source)
    {
        if (source == null)
            return null;

        var copy = PieceGenerator.MakePiece(source.Kind);
        copy.IsSticky = source.IsSticky;
        return copy;
    }


    public PieceData GetHoldPiece() => _holdPiece == null ? null : ClonePiece(_holdPiece);

    public void RegisterSuccessfulPlacement(int clearedCount, float moveTimeSec, float boardFillRatio)
    {
        _metrics.RegisterMove(moveTimeSec, clearedCount, boardFillRatio);
        _generator.RegisterMoveOutcome(clearedCount);
        _director.Update(_metrics.Snapshot(), _config);
        _holdUsed = false;

#if DEBUG
        var dbg = _generator.GetDebugSnapshot(ComputeIdealChance());
        GD.Print($"[BALANCE] secSinceWell={dbg["lastWellSecondsAgo"]:0.0}, piecesSinceWell={dbg["piecesSinceWell"]}, ideal={dbg["currentIdealChance"]:0.00}, pity={dbg["pityTriggers"]}, targetSpeed={_lastTargetSpeed:0.00}, displayedSpeed={_smoothedFallSpeed:0.00}");
#endif
    }


    public void RegisterDeadZoneDelta(int delta)
    {
        int threshold;
        int duration;
        float idealMul;
        float forcedBonus;

        if (_difficulty == "Easy")
        {
            threshold = _config.DeadZoneThresholdEasy;
            duration = _config.DeadZoneDebuffSpawnsEasy;
            idealMul = _config.DeadZoneIdealMulEasy;
            forcedBonus = _config.DeadZoneForcedBonusEasy;
        }
        else if (_difficulty == "Hard")
        {
            threshold = _config.DeadZoneThresholdHard;
            duration = _config.DeadZoneDebuffSpawnsHard;
            idealMul = _config.DeadZoneIdealMulHard;
            forcedBonus = _config.DeadZoneForcedBonusHard;
        }
        else
        {
            threshold = _config.DeadZoneThresholdMedium;
            duration = _config.DeadZoneDebuffSpawnsMedium;
            idealMul = _config.DeadZoneIdealMulMedium;
            forcedBonus = _config.DeadZoneForcedBonusMedium;
        }

        bool applied = delta > 0 && delta >= threshold;
        if (applied)
            _generator.ApplyDeadZonePenalty(duration, idealMul, forcedBonus);

#if DEBUG
        var debuff = _generator.GetDeadZoneDebuffSnapshot();
        var remainingSpawns = debuff["remainingSpawns"];
        var idealMulNow = debuff["idealMul"];
        var forcedBonusNow = debuff["forcedBonus"];
        GD.Print($"[DEAD_ZONE] delta={delta}, threshold={threshold}, applied={applied}, remaining_spawns={remainingSpawns}, ideal_mul={idealMulNow:0.000}, forced_bonus={forcedBonusNow:0.000}");
#endif
    }

    public void RegisterCancelledDrag()
    {
        _metrics.RegisterCancelledDrag();
        _director.Update(_metrics.Snapshot(), _config);
    }

    public float GetFallSpeed(float level)
    {
        var elapsedMinutes = GetElapsedMinutes();

        var peak1Minutes = Mathf.Max(0.1f, _config.SpeedPeak1Minutes);
        var peak2Minutes = Mathf.Max(peak1Minutes + 0.1f, _config.SpeedPeak2Minutes);
        var peak3Minutes = Mathf.Max(peak2Minutes + 0.1f, _config.SpeedPeak3Minutes);
        var mult1 = GetPeak1TargetMultiplier();
        var mult2 = GetPeak2TargetMultiplier();
        var mult3 = GetPeak3TargetMultiplier();

        float speedMultiplier;
        if (elapsedMinutes <= peak1Minutes)
        {
            var p = Mathf.Clamp(elapsedMinutes / peak1Minutes, 0f, 1f);
            var e = Mathf.Pow(p, Mathf.Max(0.01f, _config.SpeedEaseExponent1));
            speedMultiplier = Mathf.Lerp(1.0f, mult1, e);
        }
        else if (elapsedMinutes <= peak2Minutes)
        {
            var p = Mathf.Clamp((elapsedMinutes - peak1Minutes) / Mathf.Max(0.001f, peak2Minutes - peak1Minutes), 0f, 1f);
            var e = Mathf.Pow(p, Mathf.Max(0.01f, _config.SpeedEaseExponent2));
            speedMultiplier = Mathf.Lerp(mult1, mult2, e);
        }
        else if (elapsedMinutes <= peak3Minutes)
        {
            var p = Mathf.Clamp((elapsedMinutes - peak2Minutes) / Mathf.Max(0.001f, peak3Minutes - peak2Minutes), 0f, 1f);
            var e = Mathf.Pow(p, Mathf.Max(0.01f, _config.SpeedEaseExponent2));
            speedMultiplier = Mathf.Lerp(mult2, mult3, e);
        }
        else
        {
            var afterPeak3 = Mathf.Max(0f, elapsedMinutes - peak3Minutes);
            var tail = 1.0f + _config.SpeedTailStrength * Mathf.Log(1.0f + afterPeak3);
            speedMultiplier = mult3 * tail;
        }

        var target = _config.BaseFallSpeed * speedMultiplier;
        var now = Time.GetTicksMsec();
        var dt = Mathf.Max(0.001f, (now - _lastSpeedCalcMs) / 1000.0f);
        _lastSpeedCalcMs = now;

        var maxDelta = _config.MaxFallSpeedDeltaPerSec * dt;
        _smoothedFallSpeed = Mathf.MoveToward(_smoothedFallSpeed, target, maxDelta);
        _smoothedFallSpeed = Mathf.Min(_smoothedFallSpeed, _config.MaxFallSpeedCap);
        _lastTargetSpeed = target;

        return _smoothedFallSpeed;
    }

    public int GetLevelForScore(int score)
    {
        return 1 + Mathf.Max(0, score) / Mathf.Max(1, _config.PointsPerLevel);
    }

    public Dictionary GetWellSettings()
    {
        return new Dictionary
        {
            { "well_size", _config.WellSize },
            { "pile_max", _config.PileMax },
            { "top_selectable", _config.TopSelectable },
            { "pile_visible", _config.PileVisible },
            { "danger_start_ratio", _config.DangerLineStartRatio },
            { "danger_end_ratio", _config.DangerLineEndRatio }
        };
    }

    public Dictionary GetDifficultySnapshot()
    {
        var m = _metrics.Snapshot();
        var dbg = _generator.GetDebugSnapshot(ComputeIdealChance());
        return new Dictionary
        {
            { "difficulty01", _director.Difficulty01 },
            { "ideal_chance", dbg["currentIdealChance"] },
            { "avg_move_time", m.AvgMoveTimeSec },
            { "avg_fill", m.AvgBoardFill },
            { "cancel_rate", m.CancelRate },
            { "last_well_seconds", dbg["lastWellSecondsAgo"] },
            { "pieces_since_well", dbg["piecesSinceWell"] },
            { "pity_triggers", dbg["pityTriggers"] },
            { "target_speed", _lastTargetSpeed },
            { "displayed_speed", _smoothedFallSpeed }
        };
    }


    public float GetElapsedMinutesForDebug() => GetElapsedMinutes();

    public float GetPeak1TargetMultiplier()
    {
        if (_difficulty == "Easy")
            return 7.0f;
        if (_difficulty == "Hard")
            return 9.0f;
        return 8.0f;
    }

    public float GetPeak2TargetMultiplier()
    {
        if (_difficulty == "Easy")
            return 10.0f;
        if (_difficulty == "Hard")
            return 14.0f;
        return 12.0f;
    }

    public float GetPeak3TargetMultiplier()
    {
        if (_difficulty == "Easy")
            return 15.0f;
        if (_difficulty == "Hard")
            return 20.0f;
        return 18.0f;
    }

    public float GetSpeedTailMultiplier()
    {
        var elapsedMinutes = GetElapsedMinutes();
        var peak3Minutes = Mathf.Max(0.1f, _config.SpeedPeak3Minutes);
        var tailMinutes = Mathf.Max(0f, elapsedMinutes - peak3Minutes);
        return 1.0f + _config.SpeedTailStrength * Mathf.Log(1.0f + tailMinutes);
    }

    public string GetSpeedSegmentForDebug()
    {
        var elapsed = GetElapsedMinutes();
        if (elapsed <= _config.SpeedPeak1Minutes)
            return "A";
        if (elapsed <= _config.SpeedPeak2Minutes)
            return "B";
        if (elapsed <= _config.SpeedPeak3Minutes)
            return "C";
        return "D";
    }

    public float GetDualDropChanceCurrent()
    {
        var elapsed = GetElapsedMinutes();
        var cap = _config.DualDropChanceCapMedium;
        if (_difficulty == "Easy")
            cap = _config.DualDropChanceCapEasy;
        else if (_difficulty == "Hard")
            cap = _config.DualDropChanceCapHard;

        var capMinutes = Mathf.Max(0.1f, _config.DualDropChanceCapMinutes);
        var t = Mathf.Clamp(elapsed / capMinutes, 0f, 1f);
        return Mathf.Lerp(_config.DualDropChanceStart, cap, t);
    }

    public float GetWellDragTimeScale(float wellFillRatio)
    {
        var t = Mathf.Clamp(wellFillRatio, 0f, 1f);
        return Mathf.Lerp(_config.WellDragSlowMin, _config.WellDragSlowMax, t);
    }

    public bool ConsumeDualDropTrigger()
    {
        var chance = GetDualDropChanceCurrent();
        return _rng.Randf() < chance;
    }

    public float GetDualDropMinGapCells() => _config.DualDropMinGapCells;

    public float GetDualDropStaggerSecForSpeedMul(float speedMul)
    {
        var start = Mathf.Max(0.01f, _config.DualDropStaggerSpeedStartMul);
        var end = Mathf.Max(start + 0.01f, _config.DualDropStaggerSpeedEndMul);
        var t = Mathf.Clamp((speedMul - start) / (end - start), 0f, 1f);
        var smooth = t * t * (3.0f - 2.0f * t);
        var stagger = _config.DualDropStaggerBaseSec + _config.DualDropStaggerExtraSec * smooth;
        return Mathf.Clamp(stagger, _config.DualDropStaggerBaseSec, _config.DualDropStaggerMaxSec);
    }

    public float GetNoMercyExtraTimeScale(float wellFillRatio)
    {
        var t = Mathf.Clamp(wellFillRatio, 0f, 1f);
        return Mathf.Lerp(_config.NoMercyExtraSlowMin, _config.NoMercyExtraSlowMax, t);
    }

    public bool ShouldTriggerAutoSlow(float boardFillRatio, float wellFillRatio)
    {
        var now = Time.GetTicksMsec();
        if (now - _lastAutoSlowMs < (ulong)(_config.AutoSlowCooldownSec * 1000.0f))
            return false;

        if (boardFillRatio < _config.AutoSlowThresholdBoard && wellFillRatio < _config.AutoSlowThresholdWell)
            return false;

        _lastAutoSlowMs = now;
        return true;
    }

    public float GetAutoSlowScale() => _config.AutoSlowScale;
    public float GetAutoSlowDurationSec() => _config.AutoSlowDurationSec;
    public float GetMicroFreezeSec() => _config.MicroFreezeSec;

    public float GetBaseFallSpeed() => _config.BaseFallSpeed;
    public float GetLevelSpeedGrowth() => _config.LevelSpeedGrowth;
    public float GetDisplayedFallSpeed() => _smoothedFallSpeed;

    public float GetRescueWindowSec() => _config.RescueWindowSec;
    public int GetRescueScoreBonus() => _config.RescueScoreBonus;
    public float GetTimeSlowCooldownSec() => _config.TimeSlowCooldownSec;
    public float GetTimeSlowReadyOverlayDurationSec() => _config.TimeSlowReadyOverlayDurationSec;
    public string GetTimeSlowReadySfxPath() => _config.TimeSlowReadySfxPath;
    public float GetWellNeonPulseSpeed() => _config.WellNeonPulseSpeed;
    public float GetWellNeonMinAlpha() => _config.WellNeonMinAlpha;
    public float GetWellNeonMaxAlpha() => _config.WellNeonMaxAlpha;
    public float GetTimeSlowEffectDurationSec() => _config.TimeSlowEffectDurationSec;
    public float GetTimeSlowEffectTimeScale() => _config.TimeSlowEffectTimeScale;
    public float GetWellFirstEntrySlowDurationSec() => _config.WellFirstEntrySlowDurationSec;
    public float GetWellFirstEntrySlowTimeScale() => _config.WellFirstEntrySlowTimeScale;
    public float GetPanicPulseSpeed() => _config.PanicPulseSpeed;
    public float GetPanicBlinkSpeed() => _config.PanicBlinkSpeed;

    public int GetDeadZoneWeightHole1x1() => _config.DeadZoneWeightHole1x1;
    public int GetDeadZoneWeightPocket1x2() => _config.DeadZoneWeightPocket1x2;
    public int GetDeadZoneWeightOverhang() => _config.DeadZoneWeightOverhang;
    public int GetDeadZoneMargin() => _config.DeadZoneMargin;
    public int GetStickyDelayMoves() => _config.StickyDelayMoves;
    public int GetStickyStonesForPieceSize(int footprintSize)
    {
        if (_difficulty == "Easy")
            return _config.StickyStonesEasy;
        if (_difficulty == "Hard")
            return _config.StickyStonesHard;

        var result = _config.StickyStonesMedium;
        if (footprintSize >= 5 && _rng.Randf() < 0.5f)
            result = 2;
        return result;
    }

    public float GetPanicBlinkThreshold() => _config.PanicBlinkThreshold;
    public float GetInvalidDropGraceSec() => _config.InvalidDropGraceSec;
    public float GetInvalidDropFailSlowSec() => _config.InvalidDropFailSlowSec;
    public float GetInvalidDropFailTimeScale() => _config.InvalidDropFailTimeScale;
    public float GetSpeedPeak1Minutes() => _config.SpeedPeak1Minutes;

    public void ResetRuntimeClock()
    {
        _startMs = Time.GetTicksMsec();
        _lastSpeedCalcMs = _startMs;
        _smoothedFallSpeed = _config.BaseFallSpeed;
        _lastTargetSpeed = _smoothedFallSpeed;
    }

    public void TriggerRescueStability()
    {
        _rescueStabilityUntilMs = Time.GetTicksMsec() + (ulong)(_config.RescueStabilityDurationSec * 1000.0f);
    }

    public Dictionary RunSimulationBatch(int games, int seed = 1)
    {
        return SimulationRunner.RunBatch(_config, games, seed);
    }

    private float ComputeIdealChance()
    {
        var fromDda = _director.GetIdealPieceChance(_config);
        var elapsedMinutes = GetElapsedMinutes();
        var decayed = fromDda - _config.IdealChanceDecayPerMinute * elapsedMinutes;
        return Mathf.Clamp(decayed, _config.IdealChanceFloor, 1.0f);
    }

    private float GetElapsedMinutes()
    {
        return Mathf.Max(0f, (Time.GetTicksMsec() - _startMs) / 60000.0f);
    }

    private float GetElapsedSeconds()
    {
        return Mathf.Max(0f, (Time.GetTicksMsec() - _startMs) / 1000.0f);
    }
}
