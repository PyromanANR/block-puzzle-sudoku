using Godot;
using Godot.Collections;

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

    public override void _Ready()
    {
        _rng.Randomize();
        _config = BalanceConfig.LoadOrDefault("res://Scripts/Core/balance_config.json");
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

        float maxSpeedMultiplier = 9.0f;
        int pileMax = 7;
        int topSelectable = 2;

        if (_difficulty == "Easy")
        {
            maxSpeedMultiplier = 8.0f;
            pileMax = 8;
            topSelectable = 3;
        }
        else if (_difficulty == "Hard")
        {
            maxSpeedMultiplier = 10.0f;
            pileMax = 6;
            topSelectable = _noMercy ? 0 : 1;
        }

        _config.PileMax = pileMax;
        _config.WellSize = pileMax;
        _config.TopSelectable = topSelectable;
        _config.MaxFallSpeedCap = _config.BaseFallSpeed * maxSpeedMultiplier;
    }

    public BoardModel CreateBoard()
    {
        var b = new BoardModel();
        b.Reset();
        _activeBoard = b;
        return b;
    }

    // Compatibility API for callers without explicit board argument.
    public PieceData PeekNextPiece() => _generator.Peek(_activeBoard, ComputeIdealChance());

    // Compatibility API for callers without explicit board argument.
    public PieceData PopNextPiece() => _generator.Pop(_activeBoard, ComputeIdealChance());

    public PieceData PeekNextPieceForBoard(BoardModel board)
    {
        return _generator.Peek(board, ComputeIdealChance());
    }

    public PieceData PopNextPieceForBoard(BoardModel board)
    {
        return _generator.Pop(board, ComputeIdealChance());
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
            _holdPiece = PieceGenerator.MakePiece(current.Kind);
            return _generator.Pop(_activeBoard, ComputeIdealChance());
        }

        var outPiece = _holdPiece;
        _holdPiece = PieceGenerator.MakePiece(current.Kind);
        return outPiece;
    }

    public void ResetHoldUsage() => _holdUsed = false;

    public PieceData GetHoldPiece() => _holdPiece == null ? null : PieceGenerator.MakePiece(_holdPiece.Kind);

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

    public void RegisterCancelledDrag()
    {
        _metrics.RegisterCancelledDrag();
        _director.Update(_metrics.Snapshot(), _config);
    }

    public float GetFallSpeed(float level)
    {
        var levelGrowth = Mathf.Pow(_config.LevelSpeedGrowth, Mathf.Max(0f, level - 1f));
        var elapsedMinutes = GetElapsedMinutes();

        var kneeMinutes = Mathf.Max(0.1f, _config.SpeedKneeMinutes);
        var fastRampT = Mathf.Clamp(elapsedMinutes / kneeMinutes, 0f, 1f);
        var fastRamp = 1.0f + _config.TimeSpeedRampPerMinute * kneeMinutes * fastRampT;

        var tailMinutes = Mathf.Max(0f, elapsedMinutes - kneeMinutes);
        var tailRamp = 1.0f + _config.PostKneeSpeedTailStrength * Mathf.Log(1.0f + tailMinutes);

        var growthMul = 1.0f;
        if (Time.GetTicksMsec() < _rescueStabilityUntilMs)
            growthMul = _config.RescueStabilityGrowthMul;

        var target = _config.BaseFallSpeed * levelGrowth * fastRamp * tailRamp * growthMul * _director.GetFallMultiplier(_config);
        _lastTargetSpeed = target;

        var now = Time.GetTicksMsec();
        var dt = Mathf.Max(0.001f, (now - _lastSpeedCalcMs) / 1000.0f);
        _lastSpeedCalcMs = now;
        var maxDelta = _config.MaxFallSpeedDeltaPerSec * dt;
        _smoothedFallSpeed = Mathf.MoveToward(_smoothedFallSpeed, target, maxDelta);

#if DEBUG
        if (now - _lastDebugSpeedLogMs >= 1000)
        {
            _lastDebugSpeedLogMs = now;
            GD.Print($"[SPEED] target={target:0.00}, smoothed={_smoothedFallSpeed:0.00}, level={level:0.0}, elapsedMin={elapsedMinutes:0.00}");
        }
#endif

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


    public float GetWellDragTimeScale(float wellFillRatio)
    {
        var t = Mathf.Clamp(wellFillRatio, 0f, 1f);
        return Mathf.Lerp(_config.WellDragSlowMin, _config.WellDragSlowMax, t);
    }

    public bool ConsumeFastNextBoost()
    {
        var elapsed = GetElapsedMinutes();
        var knee = Mathf.Max(0.1f, _config.SpeedKneeMinutes);

        var atKnee = _config.FastNextChanceAtKneeMedium;
        var cap = _config.FastNextChanceCapMedium;
        if (_difficulty == "Easy")
        {
            atKnee = _config.FastNextChanceAtKneeEasy;
            cap = _config.FastNextChanceCapEasy;
        }
        else if (_difficulty == "Hard")
        {
            atKnee = _config.FastNextChanceAtKneeHard;
            cap = _config.FastNextChanceCapHard;
        }

        var chance = _config.FastNextChanceStart;
        if (elapsed <= knee)
        {
            var t = Mathf.Clamp(elapsed / knee, 0f, 1f);
            chance = Mathf.Lerp(_config.FastNextChanceStart, atKnee, t);
        }
        else
        {
            var capMinutes = Mathf.Max(knee + 0.1f, _config.FastNextCapMinutes);
            var t = Mathf.Clamp((elapsed - knee) / (capMinutes - knee), 0f, 1f);
            chance = Mathf.Lerp(atKnee, cap, t);
        }

        return _rng.Randf() < chance;
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
    public float GetAutoSlowDurationSec() => _config.AutoSlowDuration;

    public float GetRescueWindowSec() => _config.RescueWindowSec;
    public int GetRescueScoreBonus() => _config.RescueScoreBonus;

    public void TriggerRescueStability()
    {
        _rescueStabilityUntilMs = Time.GetTicksMsec() + (ulong)(_config.RescueStabilityDuration * 1000.0f);
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
}
