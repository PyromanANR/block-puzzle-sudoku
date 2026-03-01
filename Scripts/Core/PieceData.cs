using Godot;
using Godot.Collections;

[GlobalClass]
public partial class PieceData : Resource
{
    // "I","O","T","S","Z","J","L"
    [Export] public string Kind { get; set; } = "";

    // Cells relative to anchor (0,0)
    [Export] public Array<Vector2I> Cells { get; set; } = new();

    public bool IsSticky { get; set; } = false;
}
