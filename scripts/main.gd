extends Node
## Run scene. Hands the current map to GameManager, which starts the match.
## When the map loader exists (ARCHITECTURE.md #17), GameManager will pick the map instead.


func _ready() -> void:
	GameManager.start_match($Map)
