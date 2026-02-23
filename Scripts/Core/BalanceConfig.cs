using Godot;
using System;
using System.Text.Json;

public class BalanceConfig
{
    // Difficulty / pace
    public float BaseFallSpeed = 16.5f;
    public float LevelSpeedGrowth = 1.14f;
    public float TimeSpeedRampPerMinute = 0.13f;
    public float MaxFallSpeedCap = 78.0f;
    public float MaxFallSpeedDeltaPerSec = 16.0f;
    public float DdaMinFallMultiplier = 0.88f;
    public float DdaMaxFallMultiplier = 1.24f;

    // Generator fairness
    public float IdealPieceChanceEarly = 0.58f;
    public float IdealPieceChanceLate = 0.18f;
    public float IdealChanceDecayPerMinute = 0.09f;
    public float IdealChanceFloor = 0.10f;
    public int PityEveryNSpawns = 14;
    public int NoProgressMovesForPity = 4;
    public int CandidateTopBand = 5;

    // Well participation / anti-drought
    public float WellSpawnChanceEarly = 0.14f;
    public float WellSpawnChanceLate = 0.24f;
    public int ForceWellAfterSeconds = 35;
    public int ForceWellEveryNPieces = 7;

    // DDA signals
    public float TargetMoveTimeSec = 2.1f;
    public float FillDangerThreshold = 0.72f;
    public float DdaRatePerMove = 0.10f;

    // Well / pile knobs
    public int WellSize = 6;
    public int PileMax = 6;
    public int TopSelectable = 3;
    public int PileVisible = 8;
    public float DangerLineStartRatio = 0.64f;
    public float DangerLineEndRatio = 0.84f;

    // Scoring / leveling
    public int PointsPerLevel = 320;

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
