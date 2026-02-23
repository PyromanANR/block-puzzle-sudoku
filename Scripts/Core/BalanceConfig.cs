using Godot;
using System;
using System.Text.Json;

public class BalanceConfig
{
    // Difficulty / pace
    public float BaseFallSpeed = 16.0f;
    public float LevelSpeedGrowth = 1.12f;
    public float DdaMinFallMultiplier = 0.85f;
    public float DdaMaxFallMultiplier = 1.20f;

    // Generator fairness
    public float IdealPieceChanceEarly = 0.85f;
    public float IdealPieceChanceLate = 0.45f;
    public int PityEveryNSpawns = 7;
    public int CandidateTopBand = 3;

    // DDA signals
    public float TargetMoveTimeSec = 2.4f;
    public float FillDangerThreshold = 0.72f;
    public float DdaRatePerMove = 0.08f;

    // Anti-exploit / assistance
    public int MaxRerollsPerRound = 0;
    public float CancelDragPenalty = 0.02f;

    // Simulator
    public int SimulationMaxMoves = 250;

    public static BalanceConfig LoadOrDefault(string path)
    {
        try
        {
            if (!FileAccess.FileExists(path))
                return new BalanceConfig();

            using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
            var text = file.GetAsText();
            var cfg = JsonSerializer.Deserialize<BalanceConfig>(text);
            return cfg ?? new BalanceConfig();
        }
        catch (Exception e)
        {
            GD.PrintErr($"BalanceConfig load failed: {e.Message}");
            return new BalanceConfig();
        }
    }
}
