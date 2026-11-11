extends Control
class_name ECGScopeControl

var wave_data: Array[float] = []
var bpm: float = 72.0

func _init() -> void:
	for i in range(240):
		wave_data.append(0.0)

func push_sample(val: float, current_bpm: float) -> void:
	bpm = current_bpm
	wave_data.append(val)
	if wave_data.size() > 240:
		wave_data.pop_front()
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.04, 0.08, 0.06, 1.0), true)
	draw_rect(rect, Color(0.18, 0.35, 0.24, 1.0), false, 1.5)

	# 繪製示波器背景網格
	var gx := 0.0
	while gx < size.x:
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), Color(0.08, 0.16, 0.11, 1.0), 1.0)
		gx += 26.0
	var gy := 0.0
	while gy < size.y:
		draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(0.08, 0.16, 0.11, 1.0), 1.0)
		gy += 18.0

	if wave_data.size() < 2:
		return

	var pts := PackedVector2Array()
	var mid_y := size.y * 0.54
	var step_x := size.x / float(wave_data.size() - 1)
	for i in range(wave_data.size()):
		var px := float(i) * step_x
		var py := mid_y - wave_data[i] * (size.y * 0.38)
		pts.append(Vector2(px, clampf(py, 2.0, size.y - 2.0)))

	var line_col := Color(1.0, 0.25, 0.25, 1.0) if bpm > 98.0 else Color(0.2, 1.0, 0.48, 1.0)
	draw_polyline(pts, line_col, 2.2, true)
