using Godot;

public class DifficultyDirector
{
    // 0 = easier (more assistance), 1 = harder (less assistance)
    private float _difficulty01 = 0.35f;

    public void Update(MetricsSnapshot metrics, BalanceConfig config)
    {
        var movePressure = Mathf.Clamp((metrics.AvgMoveTimeSec - config.TargetMoveTimeSec) / config.TargetMoveTimeSec, -1f, 1f);
        var fillPressure = Mathf.Clamp((metrics.AvgBoardFill - config.FillDangerThreshold) / 0.25f, -1f, 1f);
        var cancelPressure = Mathf.Clamp(metrics.CancelRate, 0f, 1f);

        var desired = 0.5f - movePressure * 0.25f - fillPressure * 0.30f - cancelPressure * 0.20f;
        desired = Mathf.Clamp(desired, 0.1f, 0.95f);

        _difficulty01 = Mathf.MoveToward(_difficulty01, desired, config.DdaRatePerMove);
    }

    public float GetFallMultiplier(BalanceConfig config)
    {
        return Mathf.Lerp(config.DdaMinFallMultiplier, config.DdaMaxFallMultiplier, _difficulty01);
    }

    public float GetIdealPieceChance(BalanceConfig config)
    {
        return Mathf.Lerp(config.IdealPieceChanceEarly, config.IdealPieceChanceLate, _difficulty01);
    }

    public float Difficulty01 => _difficulty01;
}
