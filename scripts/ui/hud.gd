class_name Hud
extends Control
## Heads-up display. A passive view: UIManager calls these setters when game state changes.
##
## The crosshair's gap shows the weapon's real spread cone, so shots land inside it.
## The hit marker flashes white on a hit, red on a kill, and bigger on a headshot.

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


func _ready() -> void:
	crosshair.draw.connect(_draw_crosshair)
	hit_marker.draw.connect(_draw_hit_marker)


func _process(delta: float) -> void:
	if absf(_crosshair_gap - _crosshair_target_gap) > 0.05:
		_crosshair_gap = lerpf(_crosshair_gap, _crosshair_target_gap, 1.0 - exp(-CROSSHAIR_SMOOTHING * delta))
		crosshair.queue_redraw()


func reset() -> void:
	_last_health = -1.0
	damage_flash.color.a = 0.0
	banner.modulate.a = 0.0
	hit_marker.modulate.a = 0.0
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
