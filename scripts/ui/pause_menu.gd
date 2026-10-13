class_name PauseMenu
extends Control
## Pause overlay. Only emits button signals; UIManager forwards them to GameManager.

signal resume_pressed
signal restart_pressed
signal quit_pressed


func _ready() -> void:
	%ResumeButton.pressed.connect(resume_pressed.emit)
	%RestartButton.pressed.connect(restart_pressed.emit)
	%QuitButton.pressed.connect(quit_pressed.emit)


func open() -> void:
	show()
	%ResumeButton.grab_focus()
