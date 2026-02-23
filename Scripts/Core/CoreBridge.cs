using Godot;
using System;
using System.Collections.Generic;

public partial class CoreBridge : Node
{
    private enum Kind { I, O, T, S, Z, J, L }
    // Training bias (early game helper)
    private int _trainingLeft = 24; // first ~24 spawns are easier

    private readonly RandomNumberGenerator _rng = new();

    // Library: Kind -> base cells
    private Dictionary<Kind, Vector2I[]> _lib;

    // 7-bag queue
    private readonly List<Kind> _bag = new();
    private readonly Queue<Kind> _queue = new();

    // Hold / Reserve
    private Kind? _hold = null;
    private bool _holdUsed = false;

    public override void _Ready()
    {
        _rng.Randomize();
        _lib = BuildLibrary();

        // Prime queue with at least 2 pieces
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

    public PieceData PopNextPiece()
    {
        EnsureQueue(1);
        var k = _queue.Dequeue();
        EnsureQueue(1);
        return MakePiece(k);
    }

    // --- Hold/Reserve (Swap) ---
    // Call when player presses Swap button for currently selected piece.
    // Returns the new piece to use (may be the same if swap not allowed).
    public PieceData HoldSwap(PieceData current)
    {
        if (current == null) return null;

        // Only once per "turn" (until placement happens)
        if (_holdUsed)
            return current;

        _holdUsed = true;

        var curKind = ParseKind(current.Kind);

        if (_hold == null)
        {
            _hold = curKind;
            // If hold was empty, take next from queue
            return PopNextPiece();
        }
        else
        {
            var outKind = _hold.Value;
            _hold = curKind;
            return MakePiece(outKind);
        }
    }

    // Call after a successful placement on board
    public void ResetHoldUsage()
    {
        _holdUsed = false;
    }

    public PieceData GetHoldPiece()
    {
        return _hold == null ? null : MakePiece(_hold.Value);
    }

    private Kind WeightedTrainingPick()
    {
        // More O/I/T early, fewer S/Z early
        // weights sum = 100
        int roll = _rng.RandiRange(1, 100);
        if (roll <= 28) return Kind.O;        // 28%
        if (roll <= 50) return Kind.I;        // 22%
        if (roll <= 66) return Kind.T;        // 16%
        if (roll <= 78) return Kind.L;        // 12%
        if (roll <= 90) return Kind.J;        // 12%
        if (roll <= 95) return Kind.S;        // 5%
        return Kind.Z;                         // 5%
    }

    // --- Helpers ---
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
        _bag.AddRange(new[] { Kind.I, Kind.O, Kind.T, Kind.S, Kind.Z, Kind.J, Kind.L });
        // Shuffle-ish by RNG removal in EnsureQueue (good enough)
    }

    private PieceData MakePiece(Kind k)
    {
        var p = new PieceData();
        p.Kind = k.ToString(); // "I".."L"

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
        // Using a simple orientation for each tetromino
        // Coordinates are relative to (0,0).
        return new Dictionary<Kind, Vector2I[]>
        {
            // I: ####
            { Kind.I, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(2,0), new Vector2I(3,0) } },

            // O: ##
            //    ##
            { Kind.O, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(0,1), new Vector2I(1,1) } },

            // T: ###
            //     #
            { Kind.T, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(2,0), new Vector2I(1,1) } },

            // S:  ##
            //    ##
            { Kind.S, new [] { new Vector2I(1,0), new Vector2I(2,0), new Vector2I(0,1), new Vector2I(1,1) } },

            // Z: ##
            //     ##
            { Kind.Z, new [] { new Vector2I(0,0), new Vector2I(1,0), new Vector2I(1,1), new Vector2I(2,1) } },

            // J: #
            //    ###
            { Kind.J, new [] { new Vector2I(0,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1) } },

            // L:   #
            //    ###
            { Kind.L, new [] { new Vector2I(2,0), new Vector2I(0,1), new Vector2I(1,1), new Vector2I(2,1) } },
        };
    }
}