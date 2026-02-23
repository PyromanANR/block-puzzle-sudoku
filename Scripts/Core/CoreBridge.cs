using Godot;
using System;
using System.Collections.Generic;

public partial class CoreBridge : Node
{
    // Unified shape pool: classic tetrominoes + sudoku-style helper pieces.
    private enum Kind
    {
        // Tetrominoes
        I, O, T, S, Z, J, L,
        // Sudoku-like utility shapes
        Dot,
        DominoH, DominoV,
        TriLineH, TriLineV,
        TriL,
        Square2,
        Plus5
    }

    // Training bias (early game helper)
    private int _trainingLeft = 24;

    private readonly RandomNumberGenerator _rng = new();

    // Library: Kind -> base cells
    private Dictionary<Kind, Vector2I[]> _lib;

    // Unified bag/queue (contains both tetris + sudoku-like kinds)
    private readonly List<Kind> _bag = new();
    private readonly Queue<Kind> _queue = new();

    // Hold / Reserve
    private Kind? _hold = null;
    private bool _holdUsed = false;

    public override void _Ready()
    {
        _rng.Randomize();
        _lib = BuildLibrary();
        EnsureQueue(2);
    }

    // --- Board factory (used by GDScript) ---
    public BoardModel CreateBoard()
    {
        var b = new BoardModel();
        b.Reset();
        return b;
    }

    // --- Next / Peek ---
    public PieceData PeekNextPiece()
    {
        EnsureQueue(1);
        return MakePiece(_queue.Peek());
    }

    // Board-aware preview used by UI. Picks a fitting/progressive piece whenever possible.
    public PieceData PeekNextPieceForBoard(BoardModel board)
    {
        var kind = PickSmartKind(board, allowFallbackQueue: true);
        return MakePiece(kind);
    }

    public PieceData PopNextPiece()
    {
        EnsureQueue(1);
        var k = _queue.Dequeue();
        EnsureQueue(1);
        return MakePiece(k);
    }

    // Board-aware generation for active gameplay.
    public PieceData PopNextPieceForBoard(BoardModel board)
    {
        var kind = PickSmartKind(board, allowFallbackQueue: true);
        return MakePiece(kind);
    }

    // --- Hold/Reserve (Swap) ---
    public PieceData HoldSwap(PieceData current)
    {
        if (current == null) return null;

        if (_holdUsed)
            return current;

        _holdUsed = true;

        var curKind = ParseKind(current.Kind);

        if (_hold == null)
        {
            _hold = curKind;
            return PopNextPiece();
        }

        var outKind = _hold.Value;
        _hold = curKind;
        return MakePiece(outKind);
    }

    public void ResetHoldUsage() => _holdUsed = false;

    public PieceData GetHoldPiece() => _hold == null ? null : MakePiece(_hold.Value);

    private Kind WeightedTrainingPick()
    {
        // Early phase favors forgiving pieces and small sudoku helpers.
        int roll = _rng.RandiRange(1, 100);
        if (roll <= 16) return Kind.O;
        if (roll <= 28) return Kind.I;
        if (roll <= 40) return Kind.T;
        if (roll <= 55) return Kind.Dot;
        if (roll <= 68) return Kind.DominoH;
        if (roll <= 78) return Kind.DominoV;
        if (roll <= 86) return Kind.Square2;
        if (roll <= 92) return Kind.TriL;
        if (roll <= 96) return Kind.TriLineH;
        return Kind.TriLineV;
    }

    private void EnsureQueue(int count)
    {
        while (_queue.Count < count)
        {
            Kind k;

            if (_trainingLeft > 0)
            {
                k = WeightedTrainingPick();
                _trainingLeft--;
            }
            else
            {
                if (_bag.Count == 0) RefillBag();
                var idx = _rng.RandiRange(0, _bag.Count - 1);
                k = _bag[idx];
                _bag.RemoveAt(idx);
            }

            _queue.Enqueue(k);
        }
    }

    private void RefillBag()
    {
        _bag.Clear();
        foreach (Kind kind in Enum.GetValues(typeof(Kind)))
            _bag.Add(kind);
    }

    private PieceData MakePiece(Kind k)
    {
        var p = new PieceData { Kind = k.ToString() };

        foreach (var c in _lib[k])
            p.Cells.Add(c);

        return p;
    }

    private static Kind ParseKind(string s)
    {
        if (Enum.TryParse<Kind>(s, out var k))
            return k;
        return Kind.T;
    }

    private static Dictionary<Kind, Vector2I[]> BuildLibrary()
    {
        // One catalog for all game shapes (tetris + sudoku-like helpers).
        return new Dictionary<Kind, Vector2I[]>
        {
            // Tetrominoes
            { Kind.I, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(2,0), new Vector2I(3,0) } },
            { Kind.O, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1) } },
            { Kind.T, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(2,0), new Vector2I(1,1) } },
            { Kind.S, new [] { new Vector2I(1,0), new Vector2I(2,0), new Vector2I(0,1), new Vector2I(1,1) } },
            { Kind.Z, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(1,1), new Vector2I(2,1) } },
            { Kind.J, new [] { new Vector2I(0,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1) } },
            { Kind.L, new [] { new Vector2I(2,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1) } },

            // Sudoku-like helper shapes
            { Kind.Dot, new [] { new Vector2I(0,0) } },
            { Kind.DominoH, new [] { new Vector2I(0,0), new Vector2I(1,0) } },
            { Kind.DominoV, new [] { new Vector2I(0,0), new Vector2I(0,1) } },
            { Kind.TriLineH, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(2,0) } },
            { Kind.TriLineV, new [] { new Vector2I(0,0), new Vector2I(0,1), new Vector2I(0,2) } },
            { Kind.TriL, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(0,1) } },
            { Kind.Square2, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1) } },
            { Kind.Plus5, new [] { new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1), new Vector2I(1,2) } },
        };
    }

    private Kind PickSmartKind(BoardModel board, bool allowFallbackQueue)
    {
        if (board == null)
            return PullFromClassicQueue(allowFallbackQueue);

        var candidates = new List<(Kind kind, float score)>();

        foreach (Kind kind in Enum.GetValues(typeof(Kind)))
        {
            var piece = MakePiece(kind);
            var best = float.NegativeInfinity;

            for (int y = 0; y < board.Size; y++)
            {
                for (int x = 0; x < board.Size; x++)
                {
                    if (!board.CanPlace(piece, x, y))
                        continue;

                    var score = EvaluatePlacement(board, piece, x, y);
                    if (score > best)
                        best = score;
                }
            }

            if (!float.IsNegativeInfinity(best))
                candidates.Add((kind, best));
        }

        if (candidates.Count == 0)
            return PullFromClassicQueue(allowFallbackQueue);

        candidates.Sort((a, b) => b.score.CompareTo(a.score));

        var topScore = candidates[0].score;
        var top = new List<Kind>();
        foreach (var c in candidates)
        {
            if (c.score >= topScore - 0.75f)
                top.Add(c.kind);
            else
                break;
        }

        return top[_rng.RandiRange(0, top.Count - 1)];
    }

    private float EvaluatePlacement(BoardModel board, PieceData piece, int ax, int ay)
    {
        var size = board.Size;
        var occupied = new bool[size, size];

        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
            occupied[x, y] = board.GetCell(x, y) != 0;

        foreach (var c in piece.Cells)
            occupied[ax + c.X, ay + c.Y] = true;

        float score = piece.Cells.Count * 1.5f;

        for (int y = 0; y < size; y++)
        {
            var filled = 0;
            for (int x = 0; x < size; x++)
                if (occupied[x, y]) filled++;
            score += LineProgressScore(filled, size);
        }

        for (int x = 0; x < size; x++)
        {
            var filled = 0;
            for (int y = 0; y < size; y++)
                if (occupied[x, y]) filled++;
            score += LineProgressScore(filled, size);
        }

        for (int by = 0; by < size; by += 3)
        for (int bx = 0; bx < size; bx += 3)
        {
            var filled = 0;
            for (int dy = 0; dy < 3; dy++)
            for (int dx = 0; dx < 3; dx++)
                if (occupied[bx + dx, by + dy]) filled++;
            score += BlockProgressScore(filled);
        }

        return score;
    }

    private static float LineProgressScore(int filled, int size)
    {
        if (filled == size) return 120f;
        if (filled == size - 1) return 22f;
        if (filled == size - 2) return 9f;
        if (filled >= size - 4) return 3.5f;
        return filled * 0.2f;
    }

    private static float BlockProgressScore(int filled)
    {
        if (filled == 9) return 80f;
        if (filled == 8) return 16f;
        if (filled == 7) return 7f;
        if (filled >= 5) return 2.5f;
        return filled * 0.2f;
    }

    private Kind PullFromClassicQueue(bool allowFallbackQueue)
    {
        if (!allowFallbackQueue)
            return Kind.T;

        EnsureQueue(1);
        return _queue.Dequeue();
    }
}
