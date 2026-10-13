class_name Hud
extends Control
## Heads-up display. A passive view: UIManager calls these setters when game state changes.

var _last_health: float = -1.0
var _flash_tween: Tween
var _banner_tween: Tween

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


func reset() -> void:
	_last_health = -1.0
	damage_flash.color.a = 0.0
	banner.modulate.a = 0.0
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


func set_weapon_name(weapon_name: String) -> void:
	weapon_label.text = weapon_name


func set_reloading(reloading: bool) -> void:
	reload_label.visible = reloading


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


func _flash_damage() -> void:
	damage_flash.color.a = 0.35
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.4)
