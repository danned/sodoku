extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main := main_scene.instantiate()
	root.add_child(main)
	for _frame in range(3):
		await process_frame
	_check(main.current_screen == "home", "home screen starts")
	_check(main.page_root.get_child_count() > 0, "home screen has content")
	for screen_name in ["settings", "privacy", "stats"]:
		main._navigate(screen_name)
		for _frame in range(2):
			await process_frame
		_check(main.current_screen == screen_name, "%s screen opens" % screen_name)
		_check(main.page_root.get_child_count() > 0, "%s screen has content" % screen_name)
	if failures == 0:
		print("PASS: Godot UI smoke test")
		quit(0)
	else:
		push_error("FAIL: %d Godot UI smoke checks failed" % failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
