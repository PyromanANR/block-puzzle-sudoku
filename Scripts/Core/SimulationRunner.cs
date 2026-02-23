using Godot;
using Godot.Collections;

public class SimulationRunner
{
    public static Dictionary RunBatch(BalanceConfig config, int games, int seed = 1)
    {
        var rng = new RandomNumberGenerator();
        rng.Seed = (ulong)seed;

        int totalMoves = 0;
        int totalClears = 0;
        int totalNoMoveLosses = 0;

        for (int g = 0; g < games; g++)
        {
            var board = new BoardModel();
            board.Reset();

            var director = new DifficultyDirector();
            var metrics = new GameMetrics();
            var generator = new PieceGenerator(rng, config);

            int moves = 0;
            int clears = 0;

            while (moves < config.SimulationMaxMoves)
            {
                var idealChance = director.GetIdealPieceChance(config);
                var piece = generator.Pop(board, idealChance);

                if (!TryBestPlacement(board, piece, out int ax, out int ay))
                {
                    totalNoMoveLosses++;
                    break;
                }

                var result = board.PlaceAndClear(piece, ax, ay);
                int clearedCount = (int)result["cleared_count"];

                moves++;
                clears += clearedCount;

                var fill = ComputeFillRatio(board);
                metrics.RegisterMove(1.8f, clearedCount, fill);
                director.Update(metrics.Snapshot(), config);
            }

            totalMoves += moves;
            totalClears += clears;
        }

        var avgMoves = games > 0 ? (float)totalMoves / games : 0f;
        var avgClears = games > 0 ? (float)totalClears / games : 0f;
        var noMoveRate = games > 0 ? (float)totalNoMoveLosses / games : 0f;

        return new Dictionary
        {
            { "games", games },
            { "avg_moves", avgMoves },
            { "avg_clears", avgClears },
            { "no_move_loss_rate", noMoveRate },
            { "total_no_move_losses", totalNoMoveLosses }
        };
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
