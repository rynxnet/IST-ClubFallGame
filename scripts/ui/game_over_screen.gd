class_name GameOverScreen
extends Control
## Win/lose screen. Only emits button signals; UIManager forwards them to GameManager.
## In mission mode a loss reads "Mission failed" (success uses MissionCompleteScreen).

signal restart_pressed
signal main_menu_pressed
signal quit_pressed


func _ready() -> void:
	%RestartButton.pressed.connect(restart_pressed.emit)
	%MainMenuButton.pressed.connect(main_menu_pressed.emit)
	%QuitButton.pressed.connect(quit_pressed.emit)


func open(won: bool, score: int, wave: int, mission: bool = false) -> void:
	if mission:
		%Title.text = "Mission complete" if won else "Mission failed"
		%Details.text = "Score: %d" % score
	else:
		%Title.text = "Victory!" if won else "You died"
		%Details.text = "Score: %d\nReached wave %d" % [score, wave]
	show()
	%RestartButton.grab_focus()
