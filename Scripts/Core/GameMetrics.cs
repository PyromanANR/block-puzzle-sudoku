using Godot;

public class GameMetrics
{
    private int _moves;
    private int _cancelledDrags;
    private int _clears;
    private float _avgMoveTimeSec = 2.0f;
    private float _avgBoardFill = 0.2f;

    public void RegisterMove(float moveTimeSec, int clearedCount, float boardFill)
    {
        _moves++;
        _clears += clearedCount > 0 ? 1 : 0;
        _avgMoveTimeSec = Lerp(_avgMoveTimeSec, moveTimeSec, 0.12f);
        _avgBoardFill = Lerp(_avgBoardFill, boardFill, 0.10f);
    }

    public void RegisterCancelledDrag() => _cancelledDrags++;

    public MetricsSnapshot Snapshot()
    {
        var cancelRate = _moves <= 0 ? 0f : (float)_cancelledDrags / _moves;
        return new MetricsSnapshot
        {
            Moves = _moves,
            AvgMoveTimeSec = _avgMoveTimeSec,
            AvgBoardFill = _avgBoardFill,
            CancelRate = cancelRate,
            Clears = _clears
        };
    }

    private static float Lerp(float a, float b, float t) => a + (b - a) * t;
}

public struct MetricsSnapshot
{
    public int Moves;
    public float AvgMoveTimeSec;
    public float AvgBoardFill;
    public float CancelRate;
    public int Clears;
}
