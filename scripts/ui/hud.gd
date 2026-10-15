class_name Hud
extends Control
## Heads-up display. A passive view: UIManager calls these setters when game state changes.
##
## The crosshair's gap shows the weapon's real spread cone, so shots land inside it.
## The hit marker flashes white on a hit, red on a kill, and bigger on a headshot.
##
## Mission mode swaps the wave/enemy labels for an objective tracker (text, distance,
## progress bar) and a waypoint marker that sits on the objective's screen position, or
## clamps to the screen edge with an arrow when it's off-screen or behind the camera.

const CROSSHAIR_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const CROSSHAIR_LENGTH := 8.0
const CROSSHAIR_THICKNESS := 2.0
const CROSSHAIR_MIN_GAP := 3.0
## How quickly the drawn gap follows the weapon's spread (exponential rate per second).
const CROSSHAIR_SMOOTHING := 25.0
const HIT_COLOR := Color(1.0, 1.0, 1.0)
const KILL_COLOR := Color(1.0, 0.2, 0.15)
## Ammo turns amber at or below this fraction of a magazine, red when empty.
const AMMO_LOW_FRACTION := 0.3
const AMMO_LOW_COLOR := Color(1.0, 0.72, 0.2)
const AMMO_EMPTY_COLOR := Color(1.0, 0.25, 0.2)
const MARKER_COLOR := Color(0.93, 0.7, 0.26)
## Half-size of the waypoint diamond, in pixels.
const MARKER_SIZE := 9.0
## Off-screen markers stay this far inside the screen edge.
const MARKER_EDGE_MARGIN := 56.0
const MARKER_FONT_SIZE := 16
## Marker opacity while aiming down sights, and how fast it fades (alpha per second).
const MARKER_AIM_ALPHA := 0.3
const MARKER_FADE_SPEED := 4.0

var _last_health: float = -1.0
var _flash_tween: Tween
var _banner_tween: Tween
var _hit_tween: Tween
var _crosshair_gap: float = CROSSHAIR_MIN_GAP
var _crosshair_target_gap: float = CROSSHAIR_MIN_GAP
var _hit_color: Color = HIT_COLOR
var _hit_size: float = 10.0
var _magazine_size: int = 0
var _ammo_in_magazine: int = 0
var _mission_mode: bool = false
var _waypoint: Node3D
var _marker_position: Vector2 = Vector2.ZERO
## Direction of the off-screen arrow; zero while the waypoint is on screen.
var _marker_direction: Vector2 = Vector2.ZERO
var _marker_distance: float = 0.0
var _marker_alpha: float = 1.0
var _objective_tween: Tween
var _objective_flash_tween: Tween

@onready var health_label: Label = %HealthLabel
@onready var health_bar: ProgressBar = %HealthBar
@onready var ammo_label: Label = %AmmoLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var reload_label: Label = %ReloadLabel
@onready var score_label: Label = %ScoreLabel
@onready var wave_label: Label = %WaveLabel
@onready var enemies_label: Label = %EnemiesLabel
@onready var banner: Label = %Banner
@onready var damage_flash: ColorRect = %DamageFlash
@onready var crosshair: Control = %Crosshair
@onready var hit_marker: Control = %HitMarker
@onready var wave_box: Control = %TopLeft
@onready var objective_box: Control = %ObjectiveBox
@onready var objective_label: Label = %ObjectiveLabel
@onready var objective_distance: Label = %ObjectiveDistance
@onready var objective_progress: Control = %ObjectiveProgress
@onready var progress_label: Label = %ProgressLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var objective_flash: Control = %ObjectiveFlash
@onready var waypoint_marker: Control = %WaypointMarker


func _ready() -> void:
	crosshair.draw.connect(_draw_crosshair)
	hit_marker.draw.connect(_draw_hit_marker)
	waypoint_marker.draw.connect(_draw_waypoint_marker)


func _process(delta: float) -> void:
	if absf(_crosshair_gap - _crosshair_target_gap) > 0.05:
		_crosshair_gap = lerpf(_crosshair_gap, _crosshair_target_gap, 1.0 - exp(-CROSSHAIR_SMOOTHING * delta))
		crosshair.queue_redraw()
	if waypoint_marker.visible:
		waypoint_marker.modulate.a = move_toward(waypoint_marker.modulate.a, _marker_alpha, MARKER_FADE_SPEED * delta)


func reset() -> void:
	_last_health = -1.0
	damage_flash.color.a = 0.0
	banner.modulate.a = 0.0
	hit_marker.modulate.a = 0.0
	objective_flash.modulate.a = 0.0
	crosshair.show()
	wave_label.text = "Get ready"
	enemies_label.text = ""
	set_score(0)
	set_reloading(false)


func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "%d HP" % ceili(current)
	if _last_health >= 0.0 and current < _last_health:
		_flash_damage()
	_last_health = current


func set_ammo(in_magazine: int, reserve: int) -> void:
	ammo_label.text = "%d / %d" % [in_magazine, reserve]
	_ammo_in_magazine = in_magazine
	_update_ammo_color()


func set_magazine_size(magazine_size: int) -> void:
	_magazine_size = magazine_size
	_update_ammo_color()


func set_weapon_name(weapon_name: String) -> void:
	weapon_label.text = weapon_name


func set_reloading(reloading: bool) -> void:
	reload_label.visible = reloading


## `spread_degrees` is the weapon's cone half-angle; `camera_fov` the camera's vertical FOV.
func set_crosshair(spread_degrees: float, camera_fov: float, shown: bool) -> void:
	crosshair.visible = shown
	var gap := tan(deg_to_rad(spread_degrees)) / tan(deg_to_rad(camera_fov * 0.5)) * size.y * 0.5
	_crosshair_target_gap = maxf(gap, CROSSHAIR_MIN_GAP)


func show_hit_marker(headshot: bool, killed: bool) -> void:
	_hit_color = KILL_COLOR if killed else HIT_COLOR
	_hit_size = 15.0 if headshot else 10.0
	hit_marker.queue_redraw()
	hit_marker.modulate.a = 1.0
	if _hit_tween:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_interval(0.12 if killed else 0.06)
	_hit_tween.tween_property(hit_marker, "modulate:a", 0.0, 0.3 if killed else 0.18)


func set_score(score: int) -> void:
	score_label.text = "Score: %d" % score


func set_wave(wave: int, total_waves: int) -> void:
	wave_label.text = "Wave %d / %d" % [wave, total_waves]
	show_banner("Wave %d" % wave)


func set_enemies_remaining(count: int) -> void:
	enemies_label.text = "Enemies left: %d" % count


func show_banner(text: String) -> void:
	banner.text = text
	banner.modulate.a = 1.0
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.2)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.6)


func _update_ammo_color() -> void:
	var color := Color.WHITE
	if _ammo_in_magazine <= 0:
		color = AMMO_EMPTY_COLOR
	elif _magazine_size > 0 and _ammo_in_magazine <= _magazine_size * AMMO_LOW_FRACTION:
		color = AMMO_LOW_COLOR
	ammo_label.self_modulate = color


func _flash_damage() -> void:
	damage_flash.color.a = 0.35
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.4)


# Four outlined ticks around the centre, `_crosshair_gap` pixels out.
func _draw_crosshair() -> void:
	var center := (crosshair.size * 0.5).round()
	var gap := roundf(_crosshair_gap)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var extent := Vector2(
				absf(dir.x) * CROSSHAIR_LENGTH + absf(dir.y) * CROSSHAIR_THICKNESS,
				absf(dir.y) * CROSSHAIR_LENGTH + absf(dir.x) * CROSSHAIR_THICKNESS)
		var rect := Rect2(center + dir * (gap + CROSSHAIR_LENGTH * 0.5) - extent * 0.5, extent)
		crosshair.draw_rect(rect.grow(1.0), OUTLINE_COLOR)
		crosshair.draw_rect(rect, CROSSHAIR_COLOR)


func _draw_hit_marker() -> void:
	var center := hit_marker.size * 0.5
	for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var from := center + dir.normalized() * _hit_size * 0.4
		var to := center + dir.normalized() * _hit_size
		hit_marker.draw_line(from, to, OUTLINE_COLOR, 4.0, true)
		hit_marker.draw_line(from, to, _hit_color, 2.0, true)


## Mission mode shows the objective tracker and waypoint instead of the wave labels.
func set_mission_mode(enabled: bool) -> void:
	_mission_mode = enabled
	wave_box.visible = not enabled
	objective_box.visible = enabled and objective_label.text != ""
	waypoint_marker.visible = false


## `waypoint` is where the marker points; null hides it.
func set_objective(text: String, waypoint: Node3D) -> void:
	_waypoint = waypoint
	objective_label.text = text
	objective_distance.text = ""
	objective_progress.hide()
	objective_box.visible = _mission_mode and text != ""
	if objective_box.visible:
		_pulse(objective_box)


## 0..1 fills the bar; a negative fraction hides it.
func set_objective_progress(fraction: float, label: String) -> void:
	if fraction < 0.0:
		objective_progress.hide()
		return
	objective_progress.show()
	progress_bar.value = clampf(fraction, 0.0, 1.0)
	progress_label.text = label
	progress_label.visible = label != ""


func show_objective_complete(text: String, bonus: int) -> void:
	%FlashDetail.text = "%s    +%d" % [text, bonus] if bonus > 0 else text
	objective_flash.modulate.a = 0.0
	if _objective_flash_tween:
		_objective_flash_tween.kill()
	_objective_flash_tween = create_tween()
	_objective_flash_tween.tween_property(objective_flash, "modulate:a", 1.0, 0.15)
	_objective_flash_tween.tween_interval(1.8)
	_objective_flash_tween.tween_property(objective_flash, "modulate:a", 0.0, 0.6)
	_pulse(objective_box)


func clear_objective() -> void:
	_waypoint = null
	objective_label.text = ""
	objective_distance.text = ""
	objective_progress.hide()
	objective_box.hide()
	waypoint_marker.hide()
	objective_flash.modulate.a = 0.0


## Called every frame with the player's camera: updates the distance readout and moves the
## waypoint marker. While aiming the marker fades so it doesn't cover the sights.
func update_waypoint(camera: Camera3D, aiming: bool) -> void:
	var active := _mission_mode and camera != null and is_instance_valid(_waypoint) and _waypoint.is_inside_tree()
	if not active:
		waypoint_marker.visible = false
		objective_distance.text = ""
		return
	var target := _waypoint.global_position
	_marker_distance = camera.global_position.distance_to(target)
	objective_distance.text = "%d m" % roundi(_marker_distance)
	_marker_alpha = MARKER_AIM_ALPHA if aiming else 1.0

	var center := size * 0.5
	var margin := minf(MARKER_EDGE_MARGIN, minf(size.x, size.y) * 0.25)
	var bounds := Rect2(Vector2.ONE * margin, size - Vector2.ONE * margin * 2.0)
	if camera.is_position_behind(target):
		# unproject_position mirrors points behind the camera, so use camera-space x/y instead.
		var local := camera.global_transform.affine_inverse() * target
		var flat := Vector2(local.x, -local.y)
		_marker_direction = flat.normalized() if flat.length_squared() > 0.0001 else Vector2.DOWN
		_marker_position = _edge_point(center, _marker_direction, bounds)
	else:
		var screen := camera.unproject_position(target)
		if bounds.has_point(screen):
			_marker_direction = Vector2.ZERO
			_marker_position = screen
		else:
			_marker_direction = (screen - center).normalized()
			_marker_position = _edge_point(center, _marker_direction, bounds)
	if not waypoint_marker.visible:
		waypoint_marker.modulate.a = _marker_alpha
		waypoint_marker.visible = true
	waypoint_marker.queue_redraw()


# Where a ray from `center` along `direction` leaves `bounds` (centred on `center`).
func _edge_point(center: Vector2, direction: Vector2, bounds: Rect2) -> Vector2:
	var half := bounds.size * 0.5
	var t := INF
	if absf(direction.x) > 0.0001:
		t = minf(t, half.x / absf(direction.x))
	if absf(direction.y) > 0.0001:
		t = minf(t, half.y / absf(direction.y))
	return center + direction * (t if t != INF else 0.0)


func _pulse(target: CanvasItem) -> void:
	if _objective_tween:
		_objective_tween.kill()
	target.modulate = Color(1.8, 1.6, 1.1)
	_objective_tween = create_tween()
	_objective_tween.tween_property(target, "modulate", Color.WHITE, 0.6)


# A diamond on the waypoint; off-screen, an arrow points outward from the clamped diamond.
func _draw_waypoint_marker() -> void:
	var p := _marker_position
	var s := MARKER_SIZE
	var diamond := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	var outline := diamond.duplicate()
	outline.append(diamond[0])
	waypoint_marker.draw_colored_polygon(diamond, Color(MARKER_COLOR, 0.3))
	waypoint_marker.draw_polyline(outline, OUTLINE_COLOR, 4.5, true)
	waypoint_marker.draw_polyline(outline, MARKER_COLOR, 2.0, true)

	var text_center := p + Vector2(0.0, s + 14.0)
	if _marker_direction != Vector2.ZERO:
		var base := p + _marker_direction * (s + 5.0)
		var side := _marker_direction.orthogonal() * 7.0
		var arrow := PackedVector2Array([p + _marker_direction * (s + 17.0), base + side, base - side])
		var arrow_outline := arrow.duplicate()
		arrow_outline.append(arrow[0])
		waypoint_marker.draw_polyline(arrow_outline, OUTLINE_COLOR, 3.0, true)
		waypoint_marker.draw_colored_polygon(arrow, MARKER_COLOR)
		text_center = p - _marker_direction * Vector2(s + 30.0, s + 18.0)

	var font := ThemeDB.fallback_font
	var text := "%d m" % roundi(_marker_distance)
	var width := 90.0
	var baseline := text_center + Vector2(-width * 0.5, MARKER_FONT_SIZE * 0.35)
	waypoint_marker.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, width, MARKER_FONT_SIZE, 5, OUTLINE_COLOR)
	waypoint_marker.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, width, MARKER_FONT_SIZE, Color(1, 1, 1, 0.95))
