using Godot;
using System;
using System.Collections.Generic;

public class PieceGenerator
{
    private readonly RandomNumberGenerator _rng;
    private readonly BalanceConfig _config;

    private readonly List<string> _bag = new();
    private readonly Queue<string> _queue = new();
    private readonly List<string> _recentKinds = new();

    private int _trainingLeft = 24;
    private int _spawnSincePity = 0;
    private int _noProgressMoves = 0;
    private int _pityTriggers = 0;

    private int _piecesSinceWell = 0;
    private ulong _lastWellMs;
    private bool _hasPeekedKind = false;
    private string _peekedKind = string.Empty;

    private static readonly HashSet<string> WellKinds = new()
    {
        "Dot", "DominoH", "DominoV", "TwoDotsA", "TwoDotsB", "TriLineH", "TriLineV", "TriL", "CornerBridge", "Square2"
    };

    private static readonly string[] BaseKinds = new[]
    {
        // Tetrominoes
        "I","O","T","S","Z","J","L",
        // Sudoku-like
        "Dot","Square2"
    };

    private static readonly string[] DominoKinds = new[] { "DominoH", "DominoV", "TwoDotsA", "TwoDotsB" };
    private static readonly string[] TrominoKinds = new[] { "TriLineH", "TriLineV", "TriL", "CornerBridge" };
    private static readonly string[] PentominoLiteKinds = new[] { "Plus5", "PentaL" };

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
        { "CornerBridge", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(1,1) } },
        { "Square2", new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1) } },
        { "Plus5", new [] { new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1), new Vector2I(1,2) } },
        { "PentaL", new [] { new Vector2I(0,0), new Vector2I(0,1), new Vector2I(0,2), new Vector2I(1,2), new Vector2I(2,2) } },
        { "TwoDotsA", new [] { new Vector2I(0,0), new Vector2I(1,1) } },
        { "TwoDotsB", new [] { new Vector2I(0,1), new Vector2I(1,0) } },
    };

    public PieceGenerator(RandomNumberGenerator rng, BalanceConfig config)
    {
        _rng = rng;
        _config = config;
        _lastWellMs = Time.GetTicksMsec();
        EnsureQueue(2);
    }

    public PieceData Peek(BoardModel board, float idealChance, string difficulty = "Medium", float elapsedSeconds = 0f)
    {
        _peekedKind = PickKind(board, idealChance, consume: false, difficulty, elapsedSeconds);
        _hasPeekedKind = true;
        return MakePiece(_peekedKind);
    }

    public PieceData Pop(BoardModel board, float idealChance, string difficulty = "Medium", float elapsedSeconds = 0f)
    {
        var kind = _hasPeekedKind
            ? _peekedKind
            : PickKind(board, idealChance, consume: true, difficulty, elapsedSeconds);

        _hasPeekedKind = false;
        _peekedKind = string.Empty;
        BurnQueueToken();
        RegisterGeneratedKind(kind);
        _spawnSincePity++;
        _piecesSinceWell++;

        if (IsWellKind(kind))
        {
            _piecesSinceWell = 0;
            _lastWellMs = Time.GetTicksMsec();
        }

        return MakePiece(kind);
    }

    private string PickKind(BoardModel board, float idealChance, bool consume, string difficulty, float elapsedSeconds)
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

        var forcedChance = GetForcedFitChance(difficulty, elapsedSeconds);
        bool forcedTriggered = _rng.Randf() < forcedChance;
        string forcedSelected = string.Empty;

        if (forcedTriggered)
        {
            var forcedCandidates = new List<(string kind, float score)>();
            for (int i = 0; i < evaluated.Count; i++)
            {
                var placementCount = CountValidPlacements(board, MakePiece(evaluated[i].kind), maxCount: 2);
                if (placementCount == 1)
                    forcedCandidates.Add(evaluated[i]);
            }

            if (forcedCandidates.Count > 0)
            {
                forcedCandidates.Sort((a, b) => b.score.CompareTo(a.score));
                int topBand = Math.Min(_config.CandidateTopBand, forcedCandidates.Count);
                forcedSelected = forcedCandidates[_rng.RandiRange(0, topBand - 1)].kind;
            }
        }

        string selected;
        if (!string.IsNullOrEmpty(forcedSelected))
        {
            selected = forcedSelected;
        }
        else
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

        selected = EnforceMaxStreak(selected, evaluated);

#if DEBUG
        if (consume)
        {
            var chosenPlacementCount = CountValidPlacements(board, MakePiece(selected));
            GD.Print($"[FORCED_FIT] elapsed_seconds={elapsedSeconds:0.0}, difficulty={difficulty}, p_forced={forcedChance:0.000}, triggered={forcedTriggered && !string.IsNullOrEmpty(forcedSelected)}, placement_count={chosenPlacementCount}");
        }
#endif

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
        foreach (var kind in GetEnabledKinds())
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

    private int CountValidPlacements(BoardModel board, PieceData piece, int maxCount = int.MaxValue)
    {
        if (board == null || piece == null)
            return 0;

        int count = 0;
        for (int y = 0; y < board.Size; y++)
        for (int x = 0; x < board.Size; x++)
        {
            if (!board.CanPlace(piece, x, y))
                continue;

            count++;
            if (count >= maxCount)
                return count;
        }

        return count;
    }

    public static float GetForcedFitChance(string difficulty, float elapsedSeconds)
    {
        float[,] points;
        switch (difficulty)
        {
            case "Easy":
                points = new float[,] { { 90f, 0.00f }, { 180f, 0.08f }, { 360f, 0.12f }, { 600f, 0.15f } };
                break;
            case "Hard":
                points = new float[,] { { 90f, 0.05f }, { 180f, 0.12f }, { 360f, 0.18f }, { 600f, 0.25f } };
                break;
            default:
                points = new float[,] { { 90f, 0.03f }, { 180f, 0.10f }, { 360f, 0.15f }, { 600f, 0.20f } };
                break;
        }

        var t = Mathf.Clamp(elapsedSeconds, points[0, 0], points[3, 0]);
        for (int i = 0; i < 3; i++)
        {
            var t0 = points[i, 0];
            var t1 = points[i + 1, 0];
            if (t <= t1)
            {
                var p = Mathf.Clamp((t - t0) / Mathf.Max(0.001f, t1 - t0), 0f, 1f);
                var v0 = points[i, 1];
                var v1 = points[i + 1, 1];
                return Mathf.Lerp(v0, v1, p);
            }
        }

        return points[3, 1];
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
                if (!GetEnabledKinds().Contains(kind))
                {
                    var enabled = GetEnabledKinds();
                    kind = enabled[_rng.RandiRange(0, enabled.Count - 1)];
                }
                _trainingLeft--;
            }
            else
            {
                if (_config.GeneratorUseBag)
                {
                    if (_bag.Count == 0) RefillBag();
                    kind = PickBagKindWithStreakGuard();
                }
                else
                {
                    var kinds = GetEnabledKinds();
                    kind = kinds[_rng.RandiRange(0, kinds.Count - 1)];
                    kind = EnforceMaxStreak(kind, null);
                }
            }
            _queue.Enqueue(kind);
        }
    }

    private void RefillBag()
    {
        _bag.Clear();
        foreach (var kind in GetEnabledKinds())
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
        if (roll <= 73) return "TwoDotsA";
        if (roll <= 78) return "TwoDotsB";
        if (roll <= 83) return "Square2";
        if (roll <= 90) return "TriL";
        if (roll <= 97) return "TriLineH";
        return "Plus5";
    }


    private List<string> GetEnabledKinds()
    {
        var kinds = new List<string>(BaseKinds);
        if (_config.PiecePoolEnableDomino)
            kinds.AddRange(DominoKinds);
        if (_config.PiecePoolEnableTromino)
            kinds.AddRange(TrominoKinds);
        if (_config.PiecePoolEnablePentominoLite)
            kinds.AddRange(PentominoLiteKinds);
        return kinds;
    }

    private bool WouldExceedStreak(string kind)
    {
        var maxSame = Math.Max(1, _config.GeneratorMaxSameInRow);
        int streak = 0;
        for (int i = _recentKinds.Count - 1; i >= 0; i--)
        {
            if (_recentKinds[i] != kind)
                break;
            streak++;
        }
        return streak >= maxSame;
    }

    private string EnforceMaxStreak(string selected, List<(string kind, float score)> evaluated)
    {
        if (!WouldExceedStreak(selected))
            return selected;

        if (evaluated != null)
        {
            foreach (var item in evaluated)
            {
                if (!WouldExceedStreak(item.kind))
                    return item.kind;
            }
            return selected;
        }

        var enabled = GetEnabledKinds();
        for (int i = 0; i < enabled.Count; i++)
        {
            if (!WouldExceedStreak(enabled[i]))
                return enabled[i];
        }

        return selected;
    }

    private string PickBagKindWithStreakGuard()
    {
        if (_bag.Count == 0)
            return WeightedTrainingPick();

        int idx = _rng.RandiRange(0, _bag.Count - 1);
        var candidate = _bag[idx];
        if (WouldExceedStreak(candidate))
        {
            for (int i = 0; i < _bag.Count; i++)
            {
                if (!WouldExceedStreak(_bag[i]))
                {
                    idx = i;
                    candidate = _bag[i];
                    break;
                }
            }
        }
        _bag.RemoveAt(idx);
        return candidate;
    }

    private void RegisterGeneratedKind(string kind)
    {
        _recentKinds.Add(kind);
        var maxHistory = Math.Max(1, _config.GeneratorHistoryLen);
        while (_recentKinds.Count > maxHistory)
            _recentKinds.RemoveAt(0);
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
        if (kind == "TwoDots")
            kind = "TwoDotsA";

        var p = new PieceData { Kind = kind };
        foreach (var c in Lib[kind])
            p.Cells.Add(c);
        return p;
    }
}
