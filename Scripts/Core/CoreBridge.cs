using Godot;
using Godot.Collections;

public partial class CoreBridge : Node
{
    private readonly RandomNumberGenerator _rng = new();

    private BalanceConfig _config;
    private PieceGenerator _generator;
    private readonly GameMetrics _metrics = new();
    private readonly DifficultyDirector _director = new();

    public override void _Ready()
    {
        _rng.Randomize();
        _config = BalanceConfig.LoadOrDefault("res://Scripts/Core/balance_config.json");
        _generator = new PieceGenerator(_rng, _config);
    }

    public BoardModel CreateBoard()
    {
        var b = new BoardModel();
        b.Reset();
        return b;
    }

    public PieceData PeekNextPiece() => _generator.Peek(CreateBoard(), _director.GetIdealPieceChance(_config));

    public PieceData PopNextPiece() => _generator.Pop(CreateBoard(), _director.GetIdealPieceChance(_config));

    public PieceData PeekNextPieceForBoard(BoardModel board)
    {
        return _generator.Peek(board, _director.GetIdealPieceChance(_config));
    }

    public PieceData PopNextPieceForBoard(BoardModel board)
    {
        return _generator.Pop(board, _director.GetIdealPieceChance(_config));
    }

    // Hold/Reserve is kept simple and based on piece kind string.
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
            return PopNextPiece();
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
        _director.Update(_metrics.Snapshot(), _config);
        _holdUsed = false;
    }

    public void RegisterCancelledDrag()
    {
        _metrics.RegisterCancelledDrag();
        _director.Update(_metrics.Snapshot(), _config);
    }

    public float GetFallSpeed(float level)
    {
        var baseGrowth = Mathf.Pow(_config.LevelSpeedGrowth, Mathf.Max(0f, level - 1f));
        return _config.BaseFallSpeed * baseGrowth * _director.GetFallMultiplier(_config);
    }

    public Dictionary GetDifficultySnapshot()
    {
        var m = _metrics.Snapshot();
        return new Dictionary
        {
            { "difficulty01", _director.Difficulty01 },
            { "ideal_chance", _director.GetIdealPieceChance(_config) },
            { "avg_move_time", m.AvgMoveTimeSec },
            { "avg_fill", m.AvgBoardFill },
            { "cancel_rate", m.CancelRate }
        };
    }

    public Dictionary RunSimulationBatch(int games, int seed = 1)
    {
        return SimulationRunner.RunBatch(_config, games, seed);
    }
}
