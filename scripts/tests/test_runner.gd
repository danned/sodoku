extends SceneTree

var failures := 0
var assertions := 0


func _init() -> void:
	_test_generation()
	_test_gameplay()
	_test_mistake_feedback()
	_test_validation()
	if failures == 0:
		print("PASS: %d Sudoku assertions" % assertions)
		quit(0)
	else:
		push_error("FAIL: %d of %d Sudoku assertions failed" % [failures, assertions])
		quit(1)


func _test_generation() -> void:
	var targets := {"easy": 44, "medium": 38, "hard": 32, "expert": 28}
	for difficulty in SudokuEngine.DIFFICULTIES:
		for offset in range(3):
			var puzzle := SudokuEngine.generate_puzzle(difficulty, 7000 + offset * 31 + targets[difficulty])
			_assert(not puzzle.is_empty(), "%s puzzle is generated" % difficulty)
			if puzzle.is_empty():
				continue
			_assert(SudokuEngine.is_valid_board(puzzle.givens), "%s givens are valid" % difficulty)
			_assert(SudokuEngine.is_valid_board(puzzle.solution), "%s solution is valid" % difficulty)
			_assert(SudokuEngine.count_solutions(puzzle.givens, 2) == 1, "%s puzzle has one solution" % difficulty)
			_assert(_clues(puzzle.givens) <= int(targets[difficulty]) + 1, "%s clue target is met" % difficulty)


func _test_gameplay() -> void:
	var puzzle := SudokuEngine.generate_puzzle("easy", 41023)
	var game := GameRules.create_session(puzzle, 1000)
	var empty_index: int = puzzle.givens.find(0)
	game = GameRules.select_cell(game, empty_index)
	game = GameRules.toggle_notes(game)
	game = GameRules.enter_digit(game, 4, 1100)
	_assert(int(game.notes[empty_index]) & (1 << 4) != 0, "note entry toggles a candidate")
	game = GameRules.undo(game)
	_assert(int(game.notes[empty_index]) == 0, "undo restores note state")
	game = GameRules.redo(game)
	_assert(int(game.notes[empty_index]) & (1 << 4) != 0, "redo restores note state")
	game = GameRules.toggle_notes(game)
	game = GameRules.hint(game, 1500)
	_assert(int(game.board[empty_index]) == int(puzzle.solution[empty_index]), "hint fills the selected cell")
	_assert(bool(game.assisted), "hint marks the game assisted")
	var paused := GameRules.pause(game, 2000)
	_assert(paused.status == "paused" and int(paused.running_since) == 0, "pause accumulates and stops the timer")
	var resumed := GameRules.resume(paused, 3000)
	_assert(resumed.status == "active" and int(resumed.running_since) == 3000, "resume restarts the timer")
	for index in range(81):
		if int(resumed.board[index]) == int(puzzle.solution[index]):
			continue
		resumed = GameRules.select_cell(resumed, index)
		resumed = GameRules.enter_digit(resumed, int(puzzle.solution[index]), 4000 + index)
	_assert(resumed.status == "completed", "filling the solution completes the puzzle")
	var summary := GameRules.completed_summary(resumed)
	_assert(not summary.is_empty() and bool(summary.assisted), "completion creates an assisted result summary")


func _test_validation() -> void:
	var invalid: Array = []
	invalid.resize(81)
	invalid.fill(0)
	invalid[0] = 3
	invalid[1] = 3
	_assert(not SudokuEngine.is_valid_board(invalid), "duplicate digits are rejected")
	_assert(SudokuEngine.count_solutions(invalid, 2) == 0, "invalid boards have no solutions")


func _test_mistake_feedback() -> void:
	var puzzle := SudokuEngine.generate_puzzle("easy", 91027)
	var empty_index: int = puzzle.givens.find(0)
	var wrong_digit := int(puzzle.solution[empty_index]) % 9 + 1
	var game := GameRules.create_session(puzzle, 1000)
	game = GameRules.select_cell(game, empty_index)
	game = GameRules.enter_digit(game, wrong_digit, 1100)
	_assert(int(game.board[empty_index]) == wrong_digit, "normal mode accepts an unverified entry")
	_assert(int(game.mistakes) == 0, "normal mode does not compare entries with the hidden solution")

	var checked := GameRules.create_session(puzzle, 1000)
	checked = GameRules.select_cell(checked, empty_index)
	checked = GameRules.enter_digit(checked, wrong_digit, 1100, true)
	_assert(int(checked.mistakes) == 1, "auto-check mode counts an incorrect entry")

	var conflict_digit := 0
	for peer in SudokuEngine.get_peers(empty_index):
		if int(puzzle.givens[peer]) != 0:
			conflict_digit = int(puzzle.givens[peer])
			break
	_assert(conflict_digit != 0, "test cell has a visible given peer")
	if conflict_digit != 0:
		var conflicted := GameRules.create_session(puzzle, 1000)
		conflicted = GameRules.select_cell(conflicted, empty_index)
		conflicted = GameRules.enter_digit(conflicted, conflict_digit, 1100)
		_assert(GameRules.has_conflict(conflicted, empty_index), "visible duplicate entries are detected")


func _clues(board: Array) -> int:
	var count := 0
	for value in board:
		if int(value) != 0:
			count += 1
	return count


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failures += 1
	push_error(message)
