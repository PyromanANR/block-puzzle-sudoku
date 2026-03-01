using Godot;
using Godot.Collections;
using System;
using System.Collections.Generic;

public class SimulationRunner
{
    public static Dictionary RunBatch(BalanceConfig config, int games, int seed = 1)
    {
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong)seed;

        int totalMoves = 0;
        int totalClears = 0;
        int totalNoMoveLosses = 0;
        int totalWellOverflows = 0;
        int totalPityTriggers = 0;

        float totalTimeSec = 0f;
        var lengths = new List<float>();

        for (int g = 0; g < games; g++)
        {
            var board = new BoardModel();
            board.Reset();

            var director = new DifficultyDirector();
            var metrics = new GameMetrics();
            var generator = new PieceGenerator(rng, config);

            int moves = 0;
            int clears = 0;
            float timeSec = 0f;

            // Approximate "well" pressure: falling pieces arrive continuously.
            float wellLoad = 0f;

            while (moves < config.SimulationMaxMoves)
            {
                int level = 1 + moves / Math.Max(1, config.PointsPerLevel / 10);
                float levelGrowth = Mathf.Pow(config.LevelSpeedGrowth, Mathf.Max(0f, level - 1f));
                float fallSpeed = Mathf.Min(config.BaseFallSpeed * levelGrowth, config.MaxFallSpeedCap);
                float moveTimeSec = Mathf.Clamp(2.6f - 0.02f * moves, 0.65f, 2.6f);

                // piece inflow rises with speed. outflow is 1 selected piece each move.
                float inflow = moveTimeSec * (fallSpeed / 30.0f);
                wellLoad = Mathf.Max(0f, wellLoad + inflow - 1.0f);
                if (wellLoad > config.PileMax)
                {
                    totalWellOverflows++;
                    break;
                }

                var idealChance = director.GetIdealPieceChance(config);
                idealChance = Mathf.Clamp(idealChance - config.IdealChanceDecayPerMinute * (timeSec / 60f), config.IdealChanceFloor, 1f);
                var piece = generator.Pop(board, idealChance);

                if (!TryBestPlacement(board, piece, out int ax, out int ay))
                {
                    totalNoMoveLosses++;
                    break;
                }

                var result = board.PlaceAndClear(piece, ax, ay, config.StickyDelayMoves, 0);
                int clearedCount = (int)result["cleared_count"];

                moves++;
                clears += clearedCount;
                timeSec += moveTimeSec;

                var fill = ComputeFillRatio(board);
                metrics.RegisterMove(moveTimeSec, clearedCount, fill);
                generator.RegisterMoveOutcome(clearedCount);
                director.Update(metrics.Snapshot(), config);
            }

            totalPityTriggers += generator.ConsumePityTriggerCount();
            totalMoves += moves;
            totalClears += clears;
            totalTimeSec += timeSec;
            lengths.Add(timeSec);
        }

        lengths.Sort();
        float p50 = Percentile(lengths, 0.50f);
        float p90 = Percentile(lengths, 0.90f);
        float avgMoves = games > 0 ? (float)totalMoves / games : 0f;
        float avgClears = games > 0 ? (float)totalClears / games : 0f;
        float avgTimeSec = games > 0 ? totalTimeSec / games : 0f;
        float noMoveRate = games > 0 ? (float)totalNoMoveLosses / games : 0f;
        float overflowRate = games > 0 ? (float)totalWellOverflows / games : 0f;
        float pityPerGame = games > 0 ? (float)totalPityTriggers / games : 0f;
        float clearsPerMin = avgTimeSec > 0 ? avgClears / (avgTimeSec / 60f) : 0f;

        return new Dictionary
        {
            { "games", games },
            { "avg_moves", avgMoves },
            { "avg_time_sec", avgTimeSec },
            { "p50_time_sec", p50 },
            { "p90_time_sec", p90 },
            { "avg_clears", avgClears },
            { "clears_per_min", clearsPerMin },
            { "no_move_loss_rate", noMoveRate },
            { "well_overflow_rate", overflowRate },
            { "pity_triggers_per_game", pityPerGame }
        };
    }

    private static float Percentile(List<float> values, float p)
    {
        if (values.Count == 0) return 0f;
        int idx = Mathf.Clamp((int)Mathf.Floor((values.Count - 1) * p), 0, values.Count - 1);
        return values[idx];
    }

    private static bool TryBestPlacement(BoardModel board, PieceData piece, out int bestX, out int bestY)
    {
        bestX = -1;
        bestY = -1;
        float bestScore = float.NegativeInfinity;

        for (int y = 0; y < board.Size; y++)
        for (int x = 0; x < board.Size; x++)
        {
            if (!board.CanPlace(piece, x, y))
                continue;

            var centerBias = 1f - (Mathf.Abs(4 - x) + Mathf.Abs(4 - y)) * 0.05f;
            var score = centerBias;
            if (score > bestScore)
            {
                bestScore = score;
                bestX = x;
                bestY = y;
            }
        }

        return bestX >= 0;
    }

    private static float ComputeFillRatio(BoardModel board)
    {
        int occ = 0;
        int size = board.Size;
        for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++)
            occ += board.GetCell(x, y) == 0 ? 0 : 1;

        return (float)occ / (size * size);
    }
}
