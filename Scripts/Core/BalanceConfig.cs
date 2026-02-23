using Godot;
using System;
using System.Text.Json;

public class BalanceConfig
{
    // Difficulty / pace
    public float BaseFallSpeed = 14.0f;
    public float LevelSpeedGrowth = 1.16f;
    public float TimeSpeedRampPerMinute = 0.11f;
    public float MaxFallSpeedCap = 72.0f;
    public float DdaMinFallMultiplier = 0.85f;
    public float DdaMaxFallMultiplier = 1.25f;

    // Generator fairness
    public float IdealPieceChanceEarly = 0.82f;
    public float IdealPieceChanceLate = 0.30f;
    public float IdealChanceDecayPerMinute = 0.06f;
    public float IdealChanceFloor = 0.22f;
    public int PityEveryNSpawns = 8;
    public int NoProgressMovesForPity = 3;
    public int CandidateTopBand = 3;

    // DDA signals
    public float TargetMoveTimeSec = 2.2f;
    public float FillDangerThreshold = 0.70f;
    public float DdaRatePerMove = 0.10f;

    // Well / pile knobs
    public int WellSize = 6;
    public int PileMax = 6;
    public int TopSelectable = 3;
    public int PileVisible = 8;
    public float DangerLineStartRatio = 0.68f;
    public float DangerLineEndRatio = 0.88f;

    // Scoring / leveling
    public int PointsPerLevel = 200;

    // Anti-exploit / assistance
    public int MaxRerollsPerRound = 0;
    public float CancelDragPenalty = 0.02f;

    // Simulator
    public int SimulationMaxMoves = 320;

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
