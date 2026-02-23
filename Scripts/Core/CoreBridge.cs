using Godot;
using Godot.Collections;

public partial class CoreBridge : Node
{
    private readonly RandomNumberGenerator _rng = new();

    private BalanceConfig _config;
    private PieceGenerator _generator;
    private readonly GameMetrics _metrics = new();
    private readonly DifficultyDirector _director = new();
    private int _startMs;

    private BoardModel _activeBoard;
    private float _smoothedFallSpeed;
    private float _lastTargetSpeed;
    private int _lastSpeedCalcMs;
    private int _lastDebugSpeedLogMs;

    public override void _Ready()
    {
        _rng.Randomize();
        _config = BalanceConfig.LoadOrDefault("res://Scripts/Core/balance_config.json");
        _generator = new PieceGenerator(_rng, _config);

        _startMs = Time.GetTicksMsec();
        _lastSpeedCalcMs = _startMs;
        _lastDebugSpeedLogMs = _startMs;
        _smoothedFallSpeed = _config.BaseFallSpeed;
        _lastTargetSpeed = _smoothedFallSpeed;
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
        var timeGrowth = 1.0f + _config.TimeSpeedRampPerMinute * elapsedMinutes;

        var target = _config.BaseFallSpeed * levelGrowth * timeGrowth * _director.GetFallMultiplier(_config);
        target = Mathf.Min(target, _config.MaxFallSpeedCap);
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
            var capReached = target >= _config.MaxFallSpeedCap - 0.001f;
            GD.Print($"[SPEED] target={target:0.00}, smoothed={_smoothedFallSpeed:0.00}, level={level:0.0}, elapsedMin={elapsedMinutes:0.00}, capReached={capReached}");
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
