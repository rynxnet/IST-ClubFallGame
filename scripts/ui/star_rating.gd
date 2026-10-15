class_name StarRating
extends Control
## A row of drawn stars (no textures). `set_stars(n)` fills the first `n`; with `animate`,
## the filled stars pop in one by one and `star_revealed` fires as each one starts.
##
## Used by the main menu cards (best rating) and the mission complete screen.

signal star_revealed(index: int)

const FILLED_COLOR := Color(0.95, 0.72, 0.25)
const EMPTY_COLOR := Color(1.0, 1.0, 1.0, 0.1)
const EMPTY_OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.3)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.55)
## Inner radius of the star points as a fraction of the outer radius.
const INNER_RATIO := 0.45

@export var max_stars: int = 3
## Gap between stars as a fraction of each star's slot.
@export_range(0.0, 0.8) var gap: float = 0.2

var stars: int = 0
var _scales: Array[float] = []
var _tween: Tween


func _ready() -> void:
	_reset_scales()


## `delay` waits before the first star; `step` is the time each star takes to pop in.
func set_stars(count: int, animate: bool = false, delay: float = 0.0, step: float = 0.4) -> void:
	stars = clampi(count, 0, max_stars)
	if _tween:
		_tween.kill()
	_reset_scales()
	if animate and stars > 0:
		for i in stars:
			_scales[i] = 0.0
		_tween = create_tween()
		_tween.tween_interval(maxf(delay, 0.01))
		for i in stars:
			_tween.tween_callback(star_revealed.emit.bind(i))
			_tween.tween_method(_set_star_scale.bind(i), 0.0, 1.0, step) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _reset_scales() -> void:
	_scales.resize(max_stars)
	_scales.fill(1.0)


func _set_star_scale(value: float, index: int) -> void:
	_scales[index] = value
	queue_redraw()


func _draw() -> void:
	if max_stars <= 0:
		return
	var slot := size.x / max_stars
	var radius := minf(slot * (1.0 - gap), size.y) * 0.5
	for i in max_stars:
		var center := Vector2(slot * (i + 0.5), size.y * 0.5)
		var empty := _star_points(center, radius)
		draw_colored_polygon(empty, EMPTY_COLOR)
		draw_polyline(_closed(empty), EMPTY_OUTLINE_COLOR, 1.5, true)
		if i < stars and _scales[i] > 0.05:
			var filled := _star_points(center, radius * _scales[i])
			draw_polyline(_closed(filled), OUTLINE_COLOR, 3.0, true)
			draw_colored_polygon(filled, FILLED_COLOR)


func _star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + i * PI / 5.0
		var r := radius if i % 2 == 0 else radius * INNER_RATIO
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
