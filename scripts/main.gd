extends Node
## Run scene. Starts empty: GameManager either shows the main menu (no map chosen yet) or
## instances the chosen map as the `Map` child and starts the match. Loading a map, restarting
## and returning to the menu all reload this scene.


func _ready() -> void:
	GameManager.begin_run(self)
