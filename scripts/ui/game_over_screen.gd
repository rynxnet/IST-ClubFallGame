class_name GameOverScreen
extends Control
## Win/lose screen. Only emits button signals; UIManager forwards them to GameManager.

signal restart_pressed
signal quit_pressed


func _ready() -> void:
	%RestartButton.pressed.connect(restart_pressed.emit)
	%QuitButton.pressed.connect(quit_pressed.emit)


func open(won: bool, score: int, wave: int) -> void:
	%Title.text = "Victory!" if won else "You died"
	%Details.text = "Score: %d\nReached wave %d" % [score, wave]
	show()
	%RestartButton.grab_focus()
