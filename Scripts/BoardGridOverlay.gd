extends Control

var board_size: int = 9
var cell_size: int = 48
var major_step: int = 3
var thin_color: Color = Color(0.65, 0.45, 0.24, 0.40)
var thick_color: Color = Color(0.90, 0.66, 0.34, 0.95)


func configure(size_cells: int, cell_px: int) -> void:
	board_size = size_cells
	cell_size = cell_px
	queue_redraw()


func _draw() -> void:
	var total := float(board_size * cell_size)
	for i in range(board_size + 1):
		var x := float(i * cell_size)
		var y := float(i * cell_size)
		var major := (i % major_step) == 0
		var w := 4.0 if major else 1.0
		var col := thick_color if major else thin_color
		draw_line(Vector2(x, 0), Vector2(x, total), col, w)
		draw_line(Vector2(0, y), Vector2(total, y), col, w)
