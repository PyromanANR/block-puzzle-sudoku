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


    // Endless speed curve / two peaks + tail
    public float SpeedPeak1Minutes = 5.0f;
    public float SpeedPeak2Minutes = 10.0f;
    public float SpeedEaseExponent1 = 2.0f;
    public float SpeedEaseExponent2 = 2.0f;
    public float KneeMultEasy = 8.0f;
    public float KneeMultMedium = 9.0f;
    public float KneeMultHard = 10.0f;
    public float SpeedTailStrength = 0.08f;

    // WELL drag slow-motion
    public float WellDragSlowMin = 0.80f;
    public float WellDragSlowMax = 0.40f;
    public float NoMercyExtraSlowMin = 0.70f;
    public float NoMercyExtraSlowMax = 0.40f;

    // Dual-drop chance (multi-active pieces)
    public float DualDropChanceStart = 0.05f;
    public float DualDropChanceCapMinutes = 8.0f;
    public float DualDropChanceCapEasy = 0.10f;
    public float DualDropChanceCapMedium = 0.15f;
    public float DualDropChanceCapHard = 0.20f;
    public float DualDropStaggerSec = 1.0f;

    // Auto-slow panic rescue
    public float AutoSlowThresholdBoard = 0.85f;
    public float AutoSlowThresholdWell = 0.85f;
    public float AutoSlowScale = 0.75f;
    public float AutoSlowDurationSec = 1.0f;
    public float AutoSlowCooldownSec = 10.0f;

    // WELL rescue reward
    public float RescueWindowSec = 3.0f;
    public int RescueScoreBonus = 80;
    public float RescueStabilityDurationSec = 5.0f;
    public float RescueStabilityGrowthMul = 0.50f;

    // Micro-freeze feedback
    public float MicroFreezeSec = 0.10f;

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
