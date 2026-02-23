using Godot;
using Godot.Collections;

[GlobalClass]
public partial class BoardModel : Resource
{
	[Export] public int Size { get; set; } = 9;

	// 0 = пусто, 1 = занято
	private int[] _grid;

	public void Reset()
	{
		_grid = new int[Size * Size];
	}

	public int GetCell(int x, int y) => _grid[y * Size + x];
	public void SetCell(int x, int y, int v) => _grid[y * Size + x] = v;

	public bool CanPlace(PieceData piece, int ax, int ay)
	{
		foreach (var c in piece.Cells)
		{
			int x = ax + c.X;
			int y = ay + c.Y;
			if (x < 0 || x >= Size || y < 0 || y >= Size) return false;
			if (GetCell(x, y) != 0) return false;
		}
		return true;
	}

	// Ставит фигуру, затем очищает заполненные ряды/колонки/квадраты 3x3
	// Возвращает список очищенных клеток (для анимации) и сколько было очищено
	public Dictionary PlaceAndClear(PieceData piece, int ax, int ay)
	{
		// поставить
		foreach (var c in piece.Cells)
			SetCell(ax + c.X, ay + c.Y, 1);

		// найти что очищать
		var toClear = new Array<Vector2I>();

		// ряды
		for (int y = 0; y < Size; y++)
		{
			bool full = true;
			for (int x = 0; x < Size; x++)
				if (GetCell(x, y) == 0) { full = false; break; }

			if (full)
				for (int x = 0; x < Size; x++)
					toClear.Add(new Vector2I(x, y));
		}

		// колонки
		for (int x = 0; x < Size; x++)
		{
			bool full = true;
			for (int y = 0; y < Size; y++)
				if (GetCell(x, y) == 0) { full = false; break; }

			if (full)
				for (int y = 0; y < Size; y++)
					toClear.Add(new Vector2I(x, y));
		}

		// блоки 3x3
		for (int by = 0; by < Size; by += 3)
		for (int bx = 0; bx < Size; bx += 3)
		{
			bool full = true;
			for (int dy = 0; dy < 3; dy++)
			for (int dx = 0; dx < 3; dx++)
			{
				if (GetCell(bx + dx, by + dy) == 0) { full = false; goto EndBlock; }
			}
			EndBlock:
			if (full)
			{
				for (int dy = 0; dy < 3; dy++)
				for (int dx = 0; dx < 3; dx++)
					toClear.Add(new Vector2I(bx + dx, by + dy));
			}
		}

		// очистить (уникально)
		var unique = new Godot.Collections.Dictionary();
		foreach (var p in toClear)
			unique[p] = true;

		var cleared = new Array<Vector2I>();
		foreach (var key in unique.Keys)
		{
			var pos = (Vector2I)key;
			SetCell(pos.X, pos.Y, 0);
			cleared.Add(pos);
		}

		return new Dictionary
		{
			{ "cleared", cleared },
			{ "cleared_count", cleared.Count }
		};
	}

	public bool HasAnyMove(Array<PieceData> hand)
	{
		foreach (var piece in hand)
		{
			for (int y = 0; y < Size; y++)
			for (int x = 0; x < Size; x++)
				if (CanPlace(piece, x, y))
					return true;
		}
		return false;
	}
}
