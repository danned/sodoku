class_name GameRules
extends RefCounted

const MAX_HISTORY := 200


static func create_session(puzzle: Dictionary, now_ms: int) -> Dictionary:
	var notes: Array = []
	notes.resize(81)
	notes.fill(0)
	return {
		"puzzle": puzzle.duplicate(true),
		"board": puzzle.givens.duplicate(),
		"notes": notes,
		"selected_cell": -1,
		"notes_mode": false,
		"history": [],
		"future": [],
		"elapsed_ms": 0,
		"running_since": now_ms,
		"mistakes": 0,
		"hints_used": 0,
		"assisted": false,
		"hinted_cells": [],
		"status": "active",
		"started_at": now_ms,
		"completed_at": 0,
	}


static func select_cell(game: Dictionary, index: int) -> Dictionary:
	if game.get("status", "") != "active" or index < 0 or index >= 81:
		return game
	var next := game.duplicate(true)
	next.selected_cell = index
	return next


static func toggle_notes(game: Dictionary) -> Dictionary:
	if game.get("status", "") != "active":
		return game
	var next := game.duplicate(true)
	next.notes_mode = not bool(next.notes_mode)
	return next


static func enter_digit(game: Dictionary, digit: int, now_ms: int, auto_check_mistakes := false) -> Dictionary:
	if game.get("status", "") != "active" or digit < 1 or digit > 9:
		return game
	var selected: int = game.get("selected_cell", -1)
	if selected < 0 or int(game.puzzle.givens[selected]) != 0:
		return game
	if bool(game.notes_mode) and int(game.board[selected]) == 0:
		var noted := _with_history(game)
		noted.notes[selected] = int(noted.notes[selected]) ^ (1 << digit)
		return noted
	if int(game.board[selected]) == digit:
		return game
	var next := _with_history(game)
	next.board[selected] = digit
	next.notes = _remove_peer_notes(next.notes, selected, digit)
	if auto_check_mistakes and int(game.puzzle.solution[selected]) != digit:
		next.mistakes = int(next.mistakes) + 1
	return _finish_if_complete(next, now_ms)


static func has_conflict(game: Dictionary, index: int) -> bool:
	if index < 0 or index >= 81 or not game.get("board") is Array or game.board.size() != 81:
		return false
	var value: int = game.board[index]
	if value == 0:
		return false
	for peer in SudokuEngine.get_peers(index):
		if int(game.board[peer]) == value:
			return true
	return false


static func erase(game: Dictionary) -> Dictionary:
	if game.get("status", "") != "active":
		return game
	var selected: int = game.get("selected_cell", -1)
	if selected < 0 or int(game.puzzle.givens[selected]) != 0:
		return game
	if int(game.board[selected]) == 0 and int(game.notes[selected]) == 0:
		return game
	var next := _with_history(game)
	next.board[selected] = 0
	next.notes[selected] = 0
	return next


static func undo(game: Dictionary) -> Dictionary:
	if game.get("status", "") != "active" or game.history.is_empty():
		return game
	var next := game.duplicate(true)
	var current_snapshot := _snapshot(game)
	var previous: Dictionary = next.history.pop_back()
	next.future.push_front(current_snapshot)
	if next.future.size() > MAX_HISTORY:
		next.future.resize(MAX_HISTORY)
	_apply_snapshot(next, previous)
	return next


static func redo(game: Dictionary) -> Dictionary:
	if game.get("status", "") != "active" or game.future.is_empty():
		return game
	var next := game.duplicate(true)
	var future_snapshot: Dictionary = next.future.pop_front()
	next.history.append(_snapshot(game))
	if next.history.size() > MAX_HISTORY:
		next.history.pop_front()
	_apply_snapshot(next, future_snapshot)
	return next


static func hint(game: Dictionary, now_ms: int) -> Dictionary:
	if game.get("status", "") != "active":
		return game
	var preferred: int = game.get("selected_cell", -1)
	if preferred < 0 or int(game.puzzle.givens[preferred]) != 0 or int(game.board[preferred]) == int(game.puzzle.solution[preferred]):
		preferred = -1
		for index in range(81):
			if int(game.puzzle.givens[index]) == 0 and int(game.board[index]) != int(game.puzzle.solution[index]):
				preferred = index
				break
	if preferred < 0:
		return game
	var next := _with_history(game)
	var digit: int = next.puzzle.solution[preferred]
	next.board[preferred] = digit
	next.notes = _remove_peer_notes(next.notes, preferred, digit)
	next.selected_cell = preferred
	next.hints_used = int(next.hints_used) + 1
	next.assisted = true
	if preferred not in next.hinted_cells:
		next.hinted_cells.append(preferred)
	return _finish_if_complete(next, now_ms)


static func pause(game: Dictionary, now_ms: int) -> Dictionary:
	if game.get("status", "") != "active":
		return game
	var next := game.duplicate(true)
	next.elapsed_ms = elapsed_time(game, now_ms)
	next.running_since = 0
	next.status = "paused"
	return next


static func resume(game: Dictionary, now_ms: int) -> Dictionary:
	if game.get("status", "") != "paused":
		return game
	var next := game.duplicate(true)
	next.running_since = now_ms
	next.status = "active"
	return next


static func elapsed_time(game: Dictionary, now_ms: int) -> int:
	var running_since: int = game.get("running_since", 0)
	if running_since <= 0:
		return int(game.get("elapsed_ms", 0))
	return int(game.get("elapsed_ms", 0)) + maxi(0, now_ms - running_since)


static func paused_for_save(game: Dictionary, now_ms: int) -> Dictionary:
	if game.is_empty():
		return {}
	var next := game.duplicate(true)
	if next.get("status", "") == "active":
		next.elapsed_ms = elapsed_time(next, now_ms)
		next.running_since = 0
		next.status = "paused"
	return next


static func completed_summary(game: Dictionary) -> Dictionary:
	if game.get("status", "") != "completed":
		return {}
	return {
		"puzzle_id": game.puzzle.id,
		"difficulty": game.puzzle.difficulty,
		"elapsed_ms": game.elapsed_ms,
		"mistakes": game.mistakes,
		"hints_used": game.hints_used,
		"assisted": game.assisted,
		"completed_at": game.completed_at,
	}


static func _with_history(game: Dictionary) -> Dictionary:
	var next := game.duplicate(true)
	next.history.append(_snapshot(game))
	if next.history.size() > MAX_HISTORY:
		next.history.pop_front()
	next.future = []
	return next


static func _snapshot(game: Dictionary) -> Dictionary:
	return {
		"board": game.board.duplicate(),
		"notes": game.notes.duplicate(),
		"selected_cell": game.selected_cell,
		"notes_mode": game.notes_mode,
	}


static func _apply_snapshot(game: Dictionary, game_snapshot: Dictionary) -> void:
	game.board = game_snapshot.board.duplicate()
	game.notes = game_snapshot.notes.duplicate()
	game.selected_cell = game_snapshot.selected_cell
	game.notes_mode = game_snapshot.notes_mode


static func _remove_peer_notes(notes: Array, index: int, digit: int) -> Array:
	var next := notes.duplicate()
	var bit := 1 << digit
	for peer in SudokuEngine.get_peers(index):
		next[peer] = int(next[peer]) & ~bit
	next[index] = 0
	return next


static func _finish_if_complete(game: Dictionary, now_ms: int) -> Dictionary:
	for index in range(81):
		if int(game.board[index]) != int(game.puzzle.solution[index]):
			return game
	var next := game.duplicate(true)
	next.elapsed_ms = elapsed_time(next, now_ms)
	next.running_since = 0
	next.status = "completed"
	next.completed_at = now_ms
	return next
