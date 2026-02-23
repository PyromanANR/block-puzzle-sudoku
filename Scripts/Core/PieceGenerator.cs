using Godot;
using System;
using System.Collections.Generic;

public class PieceGenerator
{
    private readonly RandomNumberGenerator _rng;
    private readonly BalanceConfig _config;

    private readonly List<string> _bag = new();
    private readonly Queue<string> _queue = new();

    private int _trainingLeft = 24;
    private int _spawnSincePity = 0;
    private int _noProgressMoves = 0;
    private int _pityTriggers = 0;

    private int _piecesSinceWell = 0;
    private ulong _lastWellMs;

    private static readonly HashSet<string> WellKinds = new()
    {
        "Dot", "DominoH", "DominoV", "TriLineH", "TriLineV", "TriL", "Square2"
    };

    public static readonly string[] AllKinds = new[]
    {
        // Tetrominoes
        "I","O","T","S","Z","J","L",
        // Sudoku-like
        "Dot","DominoH","DominoV","TriLineH","TriLineV","TriL","Square2","Plus5"
    };

    private static readonly Dictionary<string, Vector2I[]> Lib = new()
    {
        { "I", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(2,0), new Vector2I(3,0) } },
        { "O", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1) } },
        { "T", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(2,0), new Vector2I(1,1) } },
        { "S", new [] { new Vector2I(1,0), new Vector2I(2,0), new Vector2I(0,1), new Vector2I(1,1) } },
        { "Z", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(1,1), new Vector2I(2,1) } },
        { "J", new [] { new Vector2I(0,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1) } },
        { "L", new [] { new Vector2I(2,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1) } },

        { "Dot", new [] { new Vector2I(0,0) } },
        { "DominoH", new [] { new Vector2I(0,0), new Vector2I(1,0) } },
        { "DominoV", new [] { new Vector2I(0,0), new Vector2I(0,1) } },
        { "TriLineH", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(2,0) } },
        { "TriLineV", new [] { new Vector2I(0,0), new Vector2I(0,1), new Vector2I(0,2) } },
        { "TriL", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(0,1) } },
        { "Square2", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1) } },
        { "Plus5", new [] { new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1), new Vector2I(1,2) } },
    };

    public PieceGenerator(RandomNumberGenerator rng, BalanceConfig config)
    {
        _rng = rng;
        _config = config;
        _lastWellMs = Time.GetTicksMsec();
        EnsureQueue(2);
    }

    public PieceData Peek(BoardModel board, float idealChance)
    {
        return MakePiece(PickKind(board, idealChance, consume: false));
    }

    public PieceData Pop(BoardModel board, float idealChance)
    {
        var kind = PickKind(board, idealChance, consume: true);
        _spawnSincePity++;
        _piecesSinceWell++;

        if (IsWellKind(kind))
        {
            _piecesSinceWell = 0;
            _lastWellMs = Time.GetTicksMsec();
        }

        return MakePiece(kind);
    }

    private string PickKind(BoardModel board, float idealChance, bool consume)
    {
        if (board == null)
        {
            EnsureQueue(1);
            var queued = _queue.Peek();
            if (consume)
                _queue.Dequeue();
            return queued;
        }

        var evaluated = EvaluateKinds(board);
        if (evaluated.Count == 0)
        {
            EnsureQueue(1);
            var fallback = _queue.Peek();
            if (consume) _queue.Dequeue();
            return fallback;
        }

        evaluated.Sort((a, b) => b.score.CompareTo(a.score));

        bool pity = _noProgressMoves >= _config.NoProgressMovesForPity
            || _spawnSincePity >= _config.PityEveryNSpawns;

        bool forceWell = GetSecondsSinceLastWell() >= _config.ForceWellAfterSeconds
            || _piecesSinceWell >= _config.ForceWellEveryNPieces;

        var dynamicWellChance = Mathf.Lerp(
            _config.WellSpawnChanceEarly,
            _config.WellSpawnChanceLate,
            Mathf.Clamp(GetSecondsSinceLastWell() / 60.0f, 0f, 1f));

        bool requestWell = forceWell || _rng.Randf() <= dynamicWellChance;

        string selected;
        if (requestWell && TryPickWellCandidate(evaluated, out var wellKind))
        {
            selected = wellKind;
        }
        else
        {
            bool useIdeal = pity || _rng.Randf() <= idealChance;
            if (useIdeal)
            {
                selected = evaluated[0].kind;
                if (pity) _pityTriggers++;
                _spawnSincePity = 0;
            }
            else
            {
                var band = Math.Min(_config.CandidateTopBand, evaluated.Count);
                selected = evaluated[_rng.RandiRange(0, band - 1)].kind;
            }
        }

        if (consume)
            BurnQueueToken();

        return selected;
    }

    private bool TryPickWellCandidate(List<(string kind, float score)> evaluated, out string kind)
    {
        for (int i = 0; i < evaluated.Count; i++)
        {
            if (IsWellKind(evaluated[i].kind))
            {
                kind = evaluated[i].kind;
                return true;
            }
        }

        kind = string.Empty;
        return false;
    }

    private static bool IsWellKind(string kind) => WellKinds.Contains(kind);

    private float GetSecondsSinceLastWell()
    {
        return Mathf.Max(0f, (Time.GetTicksMsec() - _lastWellMs) / 1000.0f);
    }

    private List<(string kind, float score)> EvaluateKinds(BoardModel board)
    {
        var list = new List<(string kind, float score)>();
        foreach (var kind in AllKinds)
        {
            var piece = MakePiece(kind);
            float best = float.NegativeInfinity;
            for (int y = 0; y < board.Size; y++)
            for (int x = 0; x < board.Size; x++)
            {
                if (!board.CanPlace(piece, x, y))
                    continue;
                var score = EvaluatePlacement(board, piece, x, y);
                if (score > best) best = score;
            }
            if (!float.IsNegativeInfinity(best))
                list.Add((kind, best));
        }
        return list;
    }

    private static float EvaluatePlacement(BoardModel board, PieceData piece, int ax, int ay)
    {
        var size = board.Size;
        var occupied = new bool[size, size];
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
            occupied[x, y] = board.GetCell(x, y) != 0;

        foreach (var c in piece.Cells)
            occupied[ax + c.X, ay + c.Y] = true;

        float score = piece.Cells.Count * 1.2f;

        for (int y = 0; y < size; y++)
        {
            int filled = 0;
            for (int x = 0; x < size; x++) if (occupied[x, y]) filled++;
            score += LineScore(filled, size);
        }
        for (int x = 0; x < size; x++)
        {
            int filled = 0;
            for (int y = 0; y < size; y++) if (occupied[x, y]) filled++;
            score += LineScore(filled, size);
        }

        for (int by = 0; by < size; by += 3)
        for (int bx = 0; bx < size; bx += 3)
        {
            int filled = 0;
            for (int dy = 0; dy < 3; dy++)
            for (int dx = 0; dx < 3; dx++) if (occupied[bx + dx, by + dy]) filled++;
            score += BlockScore(filled);
        }

        // Prevent "always-perfect" heavy shapes from dominating after early game.
        if (piece.Kind == "Plus5")
            score *= 0.80f;

        return score;
    }

    private static float LineScore(int filled, int size)
    {
        if (filled == size) return 130f;
        if (filled == size - 1) return 24f;
        if (filled == size - 2) return 8f;
        if (filled >= size - 4) return 2.5f;
        return filled * 0.15f;
    }

    private static float BlockScore(int filled)
    {
        if (filled == 9) return 90f;
        if (filled == 8) return 18f;
        if (filled == 7) return 6f;
        if (filled >= 5) return 2f;
        return filled * 0.1f;
    }

    private void BurnQueueToken()
    {
        EnsureQueue(1);
        _queue.Dequeue();
    }

    private void EnsureQueue(int count)
    {
        while (_queue.Count < count)
        {
            string kind;
            if (_trainingLeft > 0)
            {
                kind = WeightedTrainingPick();
                _trainingLeft--;
            }
            else
            {
                if (_bag.Count == 0) RefillBag();
                var idx = _rng.RandiRange(0, _bag.Count - 1);
                kind = _bag[idx];
                _bag.RemoveAt(idx);
            }
            _queue.Enqueue(kind);
        }
    }

    private void RefillBag()
    {
        _bag.Clear();
        foreach (var kind in AllKinds)
            _bag.Add(kind);
    }

    private string WeightedTrainingPick()
    {
        var roll = _rng.RandiRange(1, 100);
        if (roll <= 12) return "O";
        if (roll <= 22) return "I";
        if (roll <= 32) return "T";
        if (roll <= 46) return "Dot";
        if (roll <= 58) return "DominoH";
        if (roll <= 68) return "DominoV";
        if (roll <= 78) return "Square2";
        if (roll <= 86) return "TriL";
        if (roll <= 93) return "TriLineH";
        return "Plus5";
    }

    public void RegisterMoveOutcome(int clearedCount)
    {
        if (clearedCount > 0)
            _noProgressMoves = 0;
        else
            _noProgressMoves++;
    }

    public int ConsumePityTriggerCount()
    {
        var value = _pityTriggers;
        _pityTriggers = 0;
        return value;
    }

    public Dictionary<string, float> GetDebugSnapshot(float currentIdealChance)
    {
        return new Dictionary<string, float>
        {
            { "lastWellSecondsAgo", GetSecondsSinceLastWell() },
            { "piecesSinceWell", _piecesSinceWell },
            { "currentIdealChance", currentIdealChance },
            { "pityTriggers", _pityTriggers }
        };
    }

    public static PieceData MakePiece(string kind)
    {
        var p = new PieceData { Kind = kind };
        foreach (var c in Lib[kind])
            p.Cells.Add(c);
        return p;
    }
}
