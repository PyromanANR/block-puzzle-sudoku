using Godot;
using Godot.Collections;
using System.Collections.Generic;

[GlobalClass]
public partial class BoardModel : Resource
{
	[Export] public int Size { get; set; } = 9;

	public const int CellEmpty = 0;
	public const int CellFilled = 1;
	public const int CellStone = 2;

	public class PendingStickyEffect : RefCounted
	{
		public int RemainingMoves;
		public Array<Vector2I> FootprintCells = new();
		public int StonesToCreate;
	}

	private int[] _grid;
	private readonly List<PendingStickyEffect> _pendingSticky = new();
	private int _deadZoneScoreBefore = 0;
	private Rect2I _deadZoneRegion = new Rect2I(0, 0, 0, 0);

	public void Reset()
	{
		_grid = new int[Size * Size];
		_pendingSticky.Clear();
		_deadZoneScoreBefore = 0;
		_deadZoneRegion = new Rect2I(0, 0, 0, 0);
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
			if (GetCell(x, y) != CellEmpty) return false;
		}
		return true;
	}

	public void BeginDeadZoneEvaluation(PieceData piece, int ax, int ay, int margin, int wHole1x1, int wPocket1x2, int wOverhang)
	{
		_deadZoneRegion = BuildRegionAroundPiece(piece, ax, ay, margin);
		_deadZoneScoreBefore = ComputeDeadZoneScore(_deadZoneRegion, wHole1x1, wPocket1x2, wOverhang);
	}

	public int EndDeadZoneEvaluation(int wHole1x1, int wPocket1x2, int wOverhang)
	{
		var scoreAfter = ComputeDeadZoneScore(_deadZoneRegion, wHole1x1, wPocket1x2, wOverhang);
		return scoreAfter - _deadZoneScoreBefore;
	}

	public Dictionary PlaceAndClear(PieceData piece, int ax, int ay, int stickyDelayMoves, int stickyStonesToCreate)
	{
		foreach (var c in piece.Cells)
			SetCell(ax + c.X, ay + c.Y, CellFilled);

		if (piece.IsSticky)
		{
			var effect = new PendingStickyEffect
			{
				RemainingMoves = stickyDelayMoves,
				StonesToCreate = stickyStonesToCreate,
				FootprintCells = new Array<Vector2I>()
			};
			foreach (var c in piece.Cells)
				effect.FootprintCells.Add(new Vector2I(ax + c.X, ay + c.Y));
			_pendingSticky.Add(effect);
		}

		var toClear = new Array<Vector2I>();

		for (int y = 0; y < Size; y++)
		{
			bool full = true;
			for (int x = 0; x < Size; x++)
				if (GetCell(x, y) == CellEmpty) { full = false; break; }

			if (full)
				for (int x = 0; x < Size; x++)
					toClear.Add(new Vector2I(x, y));
		}

		for (int x = 0; x < Size; x++)
		{
			bool full = true;
			for (int y = 0; y < Size; y++)
				if (GetCell(x, y) == CellEmpty) { full = false; break; }

			if (full)
				for (int y = 0; y < Size; y++)
					toClear.Add(new Vector2I(x, y));
		}

		for (int by = 0; by < Size; by += 3)
		for (int bx = 0; bx < Size; bx += 3)
		{
			bool full = true;
			for (int dy = 0; dy < 3; dy++)
			for (int dx = 0; dx < 3; dx++)
			{
				if (GetCell(bx + dx, by + dy) == CellEmpty) { full = false; goto EndBlock; }
			}
			EndBlock:
			if (full)
			{
				for (int dy = 0; dy < 3; dy++)
				for (int dx = 0; dx < 3; dx++)
					toClear.Add(new Vector2I(bx + dx, by + dy));
			}
		}

		var unique = new Godot.Collections.Dictionary();
		foreach (var p in toClear)
			unique[p] = true;

		var cleared = new Array<Vector2I>();
		foreach (var key in unique.Keys)
		{
			var pos = (Vector2I)key;
			SetCell(pos.X, pos.Y, CellEmpty);
			cleared.Add(pos);
		}

		var stickyCreatedCells = ApplyPendingStickyEffects();

		return new Dictionary
		{
			{ "cleared", cleared },
			{ "cleared_count", cleared.Count },
			{ "sticky_triggered_count", stickyCreatedCells.Count },
			{ "sticky_triggered_cells", stickyCreatedCells }
		};
	}

	private Array<Vector2I> ApplyPendingStickyEffects()
	{
		var allCreated = new Array<Vector2I>();
		if (_pendingSticky.Count == 0)
			return allCreated;

		var removeIndices = new List<int>();
		for (int i = 0; i < _pendingSticky.Count; i++)
		{
			var effect = _pendingSticky[i];
			effect.RemainingMoves -= 1;
			if (effect.RemainingMoves > 0)
				continue;

			var created = new Array<Vector2I>();
			var candidates = new List<Vector2I>();
			foreach (var pos in effect.FootprintCells)
			{
				if (pos.X < 0 || pos.X >= Size || pos.Y < 0 || pos.Y >= Size)
					continue;
				if (GetCell(pos.X, pos.Y) != CellEmpty)
					candidates.Add(pos);
			}
			candidates.Sort((a, b) =>
			{
				if (a.Y != b.Y) return a.Y.CompareTo(b.Y);
				return a.X.CompareTo(b.X);
			});

			var toCreate = Mathf.Clamp(effect.StonesToCreate, 0, candidates.Count);
			for (int k = 0; k < toCreate; k++)
			{
				var pos = candidates[k];
				SetCell(pos.X, pos.Y, CellStone);
				created.Add(pos);
				allCreated.Add(pos);
			}

#if DEBUG
			GD.Print($"[STICKY_TRIGGER] attempted={effect.StonesToCreate}, placed={created.Count}, footprint_count={effect.FootprintCells.Count}");
#endif
			removeIndices.Add(i);
		}

		for (int i = removeIndices.Count - 1; i >= 0; i--)
			_pendingSticky.RemoveAt(removeIndices[i]);

		return allCreated;
	}

	private Rect2I BuildRegionAroundPiece(PieceData piece, int ax, int ay, int margin)
	{
		if (piece == null || piece.Cells.Count == 0)
			return new Rect2I(0, 0, Size, Size);

		int minX = Size - 1;
		int minY = Size - 1;
		int maxX = 0;
		int maxY = 0;
		foreach (var c in piece.Cells)
		{
			int px = ax + c.X;
			int py = ay + c.Y;
			if (px < minX) minX = px;
			if (py < minY) minY = py;
			if (px > maxX) maxX = px;
			if (py > maxY) maxY = py;
		}

		int x0 = Mathf.Clamp(minX - margin, 0, Size - 1);
		int y0 = Mathf.Clamp(minY - margin, 0, Size - 1);
		int x1 = Mathf.Clamp(maxX + margin, 0, Size - 1);
		int y1 = Mathf.Clamp(maxY + margin, 0, Size - 1);
		return new Rect2I(x0, y0, x1 - x0 + 1, y1 - y0 + 1);
	}

	private int ComputeDeadZoneScore(Rect2I region, int wHole1x1, int wPocket1x2, int wOverhang)
	{
		if (region.Size.X <= 0 || region.Size.Y <= 0)
			return 0;

		int holes1x1 = 0;
		int pockets1x2 = 0;
		int overhangs = 0;

		for (int y = region.Position.Y; y < region.End.Y; y++)
		for (int x = region.Position.X; x < region.End.X; x++)
		{
			if (!IsEmpty(x, y))
				continue;

			if (IsBlockedCardinal(x, y))
				holes1x1++;

			if (IsBlocked(x, y - 1) && (IsBlocked(x - 1, y) || IsBlocked(x + 1, y)))
				overhangs++;

			if (x + 1 < region.End.X && IsSealedHorizontalPocket(x, y))
				pockets1x2++;
			if (y + 1 < region.End.Y && IsSealedVerticalPocket(x, y))
				pockets1x2++;
		}

		return holes1x1 * wHole1x1 + pockets1x2 * wPocket1x2 + overhangs * wOverhang;
	}

	private bool IsSealedHorizontalPocket(int x, int y)
	{
		return IsEmpty(x, y)
			&& IsEmpty(x + 1, y)
			&& IsBlocked(x, y - 1)
			&& IsBlocked(x + 1, y - 1)
			&& IsBlocked(x, y + 1)
			&& IsBlocked(x + 1, y + 1)
			&& IsBlocked(x - 1, y)
			&& IsBlocked(x + 2, y);
	}

	private bool IsSealedVerticalPocket(int x, int y)
	{
		return IsEmpty(x, y)
			&& IsEmpty(x, y + 1)
			&& IsBlocked(x - 1, y)
			&& IsBlocked(x - 1, y + 1)
			&& IsBlocked(x + 1, y)
			&& IsBlocked(x + 1, y + 1)
			&& IsBlocked(x, y - 1)
			&& IsBlocked(x, y + 2);
	}

	private bool IsBlockedCardinal(int x, int y)
	{
		return IsBlocked(x - 1, y) && IsBlocked(x + 1, y) && IsBlocked(x, y - 1) && IsBlocked(x, y + 1);
	}

	private bool IsBlocked(int x, int y)
	{
		if (x < 0 || x >= Size || y < 0 || y >= Size)
			return true;
		return GetCell(x, y) != CellEmpty;
	}

	private bool IsEmpty(int x, int y)
	{
		if (x < 0 || x >= Size || y < 0 || y >= Size)
			return false;
		return GetCell(x, y) == CellEmpty;
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
