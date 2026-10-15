class_name MissionCompleteScreen
extends Control
## Mission results: stars (popped in one by one), time, kills, headshots, accuracy, damage
## taken, score, and a NEW BEST tag. Only emits button signals; UIManager forwards them
## to GameManager.
##
## `open()` takes GameManager's mission_completed stats dictionary as-is; missing keys show 0.

signal restart_pressed
signal main_menu_pressed
signal quit_pressed

## Seconds before the first star appears, and between stars.
const STAR_DELAY := 0.35
const STAR_STEP := 0.4

var _pulse_tween: Tween

@onready var _stars: StarRating = %Stars
@onready var _stats_grid: GridContainer = %StatsGrid


func _ready() -> void:
	%PlayAgainButton.pressed.connect(restart_pressed.emit)
	%MainMenuButton.pressed.connect(main_menu_pressed.emit)
	%QuitButton.pressed.connect(quit_pressed.emit)
	_stars.star_revealed.connect(_on_star_revealed)


func open(stats: Dictionary, mission_name: String) -> void:
	%MissionName.text = mission_name.to_upper()
	var fired: int = int(stats.get("shots_fired", 0))
	var hit: int = int(stats.get("shots_hit", 0))
	_fill_stats([
		["TIME", MainMenu.format_time(float(stats.get("time", 0.0)))],
		["KILLS", str(int(stats.get("kills", 0)))],
		["HEADSHOTS", str(int(stats.get("headshots", 0)))],
		["ACCURACY", "%d%%  (%d / %d)" % [roundi(float(stats.get("accuracy", 0.0)) * 100.0), hit, fired]],
		["DAMAGE TAKEN", str(roundi(float(stats.get("damage_taken", 0.0))))],
		["SCORE", str(int(stats.get("score", 0)))],
	])

	var best_time: float = float(stats.get("best_time", 0.0))
	var best_stars: int = int(stats.get("best_stars", 0))
	%BestLabel.text = "PERSONAL BEST  %s  ·  %d / 3 STARS" % [MainMenu.format_time(best_time), best_stars] \
			if best_time > 0.0 else ""
	%BestLabel.visible = best_time > 0.0

	var new_best: bool = bool(stats.get("new_best", false))
	%NewBest.visible = new_best
	if _pulse_tween:
		_pulse_tween.kill()
	if new_best:
		%NewBest.modulate.a = 1.0
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(%NewBest, "modulate:a", 0.45, 0.6)
		_pulse_tween.tween_property(%NewBest, "modulate:a", 1.0, 0.6)

	_stars.set_stars(int(stats.get("stars", 0)), true, STAR_DELAY, STAR_STEP)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	%PlayAgainButton.grab_focus()


func _fill_stats(rows: Array) -> void:
	for child in _stats_grid.get_children():
		_stats_grid.remove_child(child)
		child.queue_free()
	for row: Array in rows:
		var name_label := Label.new()
		name_label.theme_type_variation = &"MutedLabel"
		name_label.text = row[0]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := Label.new()
		value_label.theme_type_variation = &"ValueLabel"
		value_label.text = row[1]
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats_grid.add_child(name_label)
		_stats_grid.add_child(value_label)


func _on_star_revealed(_index: int) -> void:
	if visible:
		Sfx.play(&"kill_confirm", self)
