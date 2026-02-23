using Godot;
using System;
using System.Text.Json;

public class BalanceConfig
{
    // Difficulty / pace
    public float BaseFallSpeed = 18.0f;
    public float LevelSpeedGrowth = 1.16f;
    public float TimeSpeedRampPerMinute = 0.16f;
    public float MaxFallSpeedCap = 92.0f;
    public float MaxFallSpeedDeltaPerSec = 26.0f;
    public float DdaMinFallMultiplier = 0.90f;
    public float DdaMaxFallMultiplier = 1.28f;

    // Generator fairness
    public float IdealPieceChanceEarly = 0.46f;
    public float IdealPieceChanceLate = 0.12f;
    public float IdealChanceDecayPerMinute = 0.16f;
    public float IdealChanceFloor = 0.06f;
    public int PityEveryNSpawns = 9999;
    public int NoProgressMovesForPity = 5;
    public int CandidateTopBand = 8;

    // Well participation / anti-drought
    public float WellSpawnChanceEarly = 0.16f;
    public float WellSpawnChanceLate = 0.26f;
    public int ForceWellAfterSeconds = 30;
    public int ForceWellEveryNPieces = 6;

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


    // Endless speed curve / knee
    public float SpeedKneeMinutes = 6.0f;
    public float PostKneeSpeedTailStrength = 0.035f;

    // WELL drag slow-motion
    public float WellDragSlowMin = 0.90f;
    public float WellDragSlowMax = 0.60f;

    // Fast-next chance (single-spawn acceleration)
    public float FastNextChanceStart = 0.03f;
    public float FastNextChanceAtKneeEasy = 0.10f;
    public float FastNextChanceAtKneeMedium = 0.12f;
    public float FastNextChanceAtKneeHard = 0.15f;
    public float FastNextChanceCapEasy = 0.18f;
    public float FastNextChanceCapMedium = 0.22f;
    public float FastNextChanceCapHard = 0.26f;
    public float FastNextCapMinutes = 12.0f;

    // Auto-slow panic rescue
    public float AutoSlowThresholdBoard = 0.85f;
    public float AutoSlowThresholdWell = 0.85f;
    public float AutoSlowScale = 0.75f;
    public float AutoSlowDuration = 1.0f;
    public float AutoSlowCooldownSec = 10.0f;

    // WELL rescue reward
    public float RescueWindowSec = 3.0f;
    public int RescueScoreBonus = 80;
    public float RescueStabilityDuration = 5.0f;
    public float RescueStabilityGrowthMul = 0.50f;

    // Scoring / leveling
    public int PointsPerLevel = 360;

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
