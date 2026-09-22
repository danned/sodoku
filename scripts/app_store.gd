extends Node

signal changed
signal game_completed

const SAVE_PATH := "user://sudoku_state_v1.json"
const DIFFICULTIES := ["easy", "medium", "hard", "expert"]
const DEFAULT_SETTINGS := {
	"appearance": "system",
	"haptics": true,
	"show_timer": true,
	"auto_check_mistakes": false,
	"highlight_peers": true,
	"highlight_matches": true,
}

var active_game: Dictionary = {}
var stats: Dictionary = {}
var settings: Dictionary = {}
var recent_puzzle_ids: Array = []
var last_completed: Dictionary = {}


func _ready() -> void:
	_reset_memory()
	_load_state()


func start_game(difficulty: String) -> bool:
	var puzzle := SudokuEngine.generate_puzzle(difficulty, 0, recent_puzzle_ids)
	if puzzle.is_empty():
		return false
	var now := now_ms()
	active_game = GameRules.create_session(puzzle, now)
	stats[difficulty].started = int(stats[difficulty].started) + 1
	recent_puzzle_ids.push_front(puzzle.id)
	recent_puzzle_ids = _unique_slice(recent_puzzle_ids, 100)
	last_completed = {}
	_commit()
	return true


func select_cell(index: int) -> void:
	if active_game.is_empty():
		return
	var next := GameRules.select_cell(active_game, index)
	if next != active_game:
		active_game = next
		feedback_selection()
		emit_signal("changed")


func enter_digit(digit: int) -> void:
	if active_game.is_empty():
		return
	var was_completed: bool = active_game.get("status", "") == "completed"
	var selected: int = active_game.get("selected_cell", -1)
	var was_notes_mode: bool = bool(active_game.get("notes_mode", false))
	var previous_board: Array = active_game.get("board", []).duplicate()
	var auto_check: bool = bool(settings.get("auto_check_mistakes", false))
	active_game = GameRules.enter_digit(active_game, digit, now_ms(), auto_check)
	var entered_value := (
		selected >= 0
		and not was_notes_mode
		and previous_board.size() == 81
		and int(previous_board[selected]) != int(active_game.board[selected])
	)
	var should_warn := entered_value and (
		GameRules.has_conflict(active_game, selected)
		or (auto_check and int(active_game.puzzle.solution[selected]) != digit)
	)
	if should_warn:
		feedback_warning()
	else:
		feedback_selection()
	_after_game_change(was_completed)


func erase() -> void:
	_apply_game_result(GameRules.erase(active_game))


func undo() -> void:
	_apply_game_result(GameRules.undo(active_game))


func redo() -> void:
	_apply_game_result(GameRules.redo(active_game))


func toggle_notes() -> void:
	_apply_game_result(GameRules.toggle_notes(active_game))


func hint() -> void:
	if active_game.is_empty():
		return
	var was_completed: bool = active_game.get("status", "") == "completed"
	active_game = GameRules.hint(active_game, now_ms())
	feedback_selection()
	_after_game_change(was_completed)


func pause_game() -> void:
	if active_game.is_empty():
		return
	active_game = GameRules.pause(active_game, now_ms())
	_commit()


func resume_game() -> void:
	if active_game.is_empty():
		return
	active_game = GameRules.resume(active_game, now_ms())
	_commit()


func toggle_pause() -> void:
	if active_game.is_empty():
		return
	if active_game.get("status", "") == "paused":
		resume_game()
	elif active_game.get("status", "") == "active":
		pause_game()


func update_setting(key: String, value: Variant) -> void:
	if not settings.has(key):
		return
	settings[key] = value
	_commit()


func clear_all_data() -> void:
	_reset_memory()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	emit_signal("changed")


func has_unfinished_game() -> bool:
	return not active_game.is_empty() and active_game.get("status", "") != "completed"


func feedback_selection() -> void:
	if bool(settings.get("haptics", true)) and not OS.has_feature("web"):
		Input.vibrate_handheld(12)


func feedback_success() -> void:
	if bool(settings.get("haptics", true)) and not OS.has_feature("web"):
		Input.vibrate_handheld(35)


func feedback_warning() -> void:
	if bool(settings.get("haptics", true)) and not OS.has_feature("web"):
		Input.vibrate_handheld(24)


func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _apply_game_result(next: Dictionary) -> void:
	if active_game.is_empty() or next == active_game:
		return
	active_game = next
	feedback_selection()
	_commit()


func _after_game_change(was_completed: bool) -> void:
	if not was_completed and active_game.get("status", "") == "completed":
		last_completed = GameRules.completed_summary(active_game)
		_record_completion(last_completed)
		feedback_success()
		_save_state()
		emit_signal("changed")
		emit_signal("game_completed")
	else:
		_commit()


func _record_completion(summary: Dictionary) -> void:
	var difficulty: String = summary.difficulty
	var entry: Dictionary = stats[difficulty]
	entry.completed = int(entry.completed) + 1
	entry.assisted_completed = int(entry.assisted_completed) + (1 if bool(summary.assisted) else 0)
	entry.total_time_ms = int(entry.total_time_ms) + int(summary.elapsed_ms)
	entry.total_mistakes = int(entry.total_mistakes) + int(summary.mistakes)
	entry.total_hints = int(entry.total_hints) + int(summary.hints_used)
	if not bool(summary.assisted):
		var previous_best: int = int(entry.best_time_ms)
		entry.best_time_ms = int(summary.elapsed_ms) if previous_best <= 0 else mini(previous_best, int(summary.elapsed_ms))
	stats[difficulty] = entry


func _commit() -> void:
	_save_state()
	emit_signal("changed")


func _save_state() -> void:
	var payload := {
		"version": 1,
		"active_game": GameRules.paused_for_save(active_game, now_ms()),
		"stats": stats,
		"settings": settings,
		"recent_puzzle_ids": recent_puzzle_ids,
		"last_completed": last_completed,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Sudoku progress could not be saved: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(payload))
	file.close()


func _load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not _is_valid_payload(parsed):
		return
	active_game = parsed.active_game.duplicate(true)
	stats = parsed.stats.duplicate(true)
	settings = DEFAULT_SETTINGS.duplicate(true)
	settings.merge(parsed.settings, true)
	recent_puzzle_ids = parsed.recent_puzzle_ids.duplicate()
	last_completed = parsed.last_completed.duplicate(true)
	if not active_game.is_empty():
		active_game.running_since = 0
		if active_game.get("status", "") == "active":
			active_game.status = "paused"


func _is_valid_payload(payload: Variant) -> bool:
	if not payload is Dictionary or int(payload.get("version", 0)) != 1:
		return false
	if not payload.get("stats") is Dictionary or not payload.get("settings") is Dictionary:
		return false
	if not payload.get("recent_puzzle_ids") is Array or not payload.get("last_completed") is Dictionary:
		return false
	var saved_game = payload.get("active_game")
	if not saved_game is Dictionary:
		return false
	if not saved_game.is_empty():
		if not saved_game.get("board") is Array or saved_game.board.size() != 81:
			return false
		if not saved_game.get("notes") is Array or saved_game.notes.size() != 81:
			return false
		if not saved_game.get("puzzle") is Dictionary:
			return false
	return true


func _reset_memory() -> void:
	active_game = {}
	stats = {}
	for difficulty in DIFFICULTIES:
		stats[difficulty] = {
			"started": 0,
			"completed": 0,
			"assisted_completed": 0,
			"total_time_ms": 0,
			"best_time_ms": 0,
			"total_mistakes": 0,
			"total_hints": 0,
		}
	settings = DEFAULT_SETTINGS.duplicate(true)
	recent_puzzle_ids = []
	last_completed = {}


func _unique_slice(values: Array, limit: int) -> Array:
	var result: Array = []
	for value in values:
		if value not in result:
			result.append(value)
		if result.size() >= limit:
			break
	return result


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if not active_game.is_empty() and active_game.get("status", "") == "active":
			active_game = GameRules.pause(active_game, now_ms())
		_save_state()
