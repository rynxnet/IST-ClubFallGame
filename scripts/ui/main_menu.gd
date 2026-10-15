class_name MainMenu
extends Control
## Main menu: one card per map plus Quit. Only emits button signals; UIManager forwards them
## to GameManager (`load_map`, `quit`) and passes in the saved records to show on each card.
##
## Hovering a button focuses it, so mouse, keyboard and controller share one highlight.

signal map_selected(map_id: StringName)
signal quit_pressed

## Display names for each map id, also used by the mission complete screen.
const MAP_NAMES := {
	&"arena": "Arena — Survival",
	&"forest": "Forest — Recon & Extract",
}
const GRID_SPACING := 48.0
const GRID_COLOR := Color(0.75, 0.85, 0.7, 0.035)

@onready var _cards := {
	&"arena": %ArenaCard as Button,
	&"forest": %ForestCard as Button,
}
@onready var _stars := {
	&"arena": %ArenaStars as StarRating,
	&"forest": %ForestStars as StarRating,
}
@onready var _best_labels := {
	&"arena": %ArenaBest as Label,
	&"forest": %ForestBest as Label,
}


func _ready() -> void:
	%Title.text = str(ProjectSettings.get_setting("application/config/name", "")).to_upper()
	%Grid.draw.connect(_draw_grid)
	for map_id: StringName in _cards:
		var card: Button = _cards[map_id]
		card.pressed.connect(map_selected.emit.bind(map_id))
		card.mouse_entered.connect(card.grab_focus)
	%QuitButton.pressed.connect(quit_pressed.emit)
	%QuitButton.mouse_entered.connect(%QuitButton.grab_focus)


## `bests` maps a map id to GameManager.get_best(map_id) ({} when there's no record).
func open(bests: Dictionary) -> void:
	for map_id: StringName in _cards:
		_show_best(map_id, bests.get(map_id, {}))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	(_cards[&"arena"] as Button).grab_focus()


func _show_best(map_id: StringName, best: Dictionary) -> void:
	var stars: int = int(best.get("best_stars", 0))
	var time: float = float(best.get("best_time", 0.0))
	(_stars[map_id] as StarRating).set_stars(stars)
	var label: Label = _best_labels[map_id]
	if best.is_empty():
		label.text = "NO RECORD"
	elif time > 0.0:
		label.text = "BEST  %s" % format_time(time)
	else:
		label.text = "BEST"


## Seconds as mm:ss.
static func format_time(seconds: float) -> String:
	var total := maxi(floori(seconds), 0)
	return "%02d:%02d" % [floori(total / 60.0), total % 60]


func _draw_grid() -> void:
	var grid: Control = %Grid
	var x := GRID_SPACING
	while x < grid.size.x:
		grid.draw_line(Vector2(x, 0.0), Vector2(x, grid.size.y), GRID_COLOR, 1.0)
		x += GRID_SPACING
	var y := GRID_SPACING
	while y < grid.size.y:
		grid.draw_line(Vector2(0.0, y), Vector2(grid.size.x, y), GRID_COLOR, 1.0)
		y += GRID_SPACING
