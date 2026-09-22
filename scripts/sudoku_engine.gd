class_name SudokuEngine
extends RefCounted

const SIZE := 9
const CELL_COUNT := 81
const ALL_DIGITS_MASK := 0b1111111110
const GENERATOR_VERSION := 1
const DIFFICULTIES := ["easy", "medium", "hard", "expert"]
const TARGET_CLUES := {
	"easy": 44,
	"medium": 38,
	"hard": 32,
	"expert": 28,
}


static func get_peers(index: int) -> Array[int]:
	var result: Array[int] = []
	var seen := {}
	var row := index / SIZE
	var column := index % SIZE
	var box_row := (row / 3) * 3
	var box_column := (column / 3) * 3
	for cursor in range(SIZE):
		var row_peer := row * SIZE + cursor
		var column_peer := cursor * SIZE + column
		if row_peer != index and not seen.has(row_peer):
			seen[row_peer] = true
			result.append(row_peer)
		if column_peer != index and not seen.has(column_peer):
			seen[column_peer] = true
			result.append(column_peer)
	for row_offset in range(3):
		for column_offset in range(3):
			var box_peer := (box_row + row_offset) * SIZE + box_column + column_offset
			if box_peer != index and not seen.has(box_peer):
				seen[box_peer] = true
				result.append(box_peer)
	return result


static func is_valid_board(board: Array) -> bool:
	if board.size() != CELL_COUNT:
		return false
	for row in range(SIZE):
		if not _unit_is_valid(board, _row_indices(row)):
			return false
	for column in range(SIZE):
		if not _unit_is_valid(board, _column_indices(column)):
			return false
	for box in range(SIZE):
		if not _unit_is_valid(board, _box_indices(box)):
			return false
	return true


static func count_solutions(input: Array, limit: int = 2) -> int:
	if not is_valid_board(input):
		return 0
	return _search_solutions(input.duplicate(), limit)


static func generate_puzzle(difficulty: String, seed_value: int = 0, excluded_ids: Array = []) -> Dictionary:
	if difficulty not in DIFFICULTIES:
		push_error("Unknown Sudoku difficulty: %s" % difficulty)
		return {}
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system() * 1000000.0) ^ Time.get_ticks_usec()
	rng.seed = seed_value
	var target: int = TARGET_CLUES[difficulty]
	var best_givens: Array = []
	for _attempt in range(20):
		var solution := _generate_solved_grid(rng)
		var givens := _carve_unique(solution, target, rng)
		if best_givens.is_empty() or _clue_count(givens) < _clue_count(best_givens):
			best_givens = givens
		if _clue_count(givens) <= target + 1:
			var puzzle_id := _board_id(givens)
			if puzzle_id not in excluded_ids:
				return _puzzle_dictionary(puzzle_id, seed_value, difficulty, givens, solution)
	if not best_givens.is_empty():
		var fallback_solution := _solve_copy(best_givens)
		var fallback_id := _board_id(best_givens)
		if not fallback_solution.is_empty() and fallback_id not in excluded_ids:
			return _puzzle_dictionary(fallback_id, seed_value, difficulty, best_givens, fallback_solution)
	push_error("Unable to generate a unique %s puzzle." % difficulty)
	return {}


static func difficulty_label(difficulty: String) -> String:
	return difficulty.capitalize()


static func _puzzle_dictionary(puzzle_id: String, seed_value: int, difficulty: String, givens: Array, solution: Array) -> Dictionary:
	return {
		"id": "%s-v%d" % [puzzle_id, GENERATOR_VERSION],
		"seed": seed_value,
		"generator_version": GENERATOR_VERSION,
		"difficulty": difficulty,
		"givens": givens.duplicate(),
		"solution": solution.duplicate(),
		"created_at": int(Time.get_unix_time_from_system() * 1000.0),
	}


static func _generate_solved_grid(rng: RandomNumberGenerator) -> Array:
	var bands := [0, 1, 2]
	var stacks := [0, 1, 2]
	_shuffle(bands, rng)
	_shuffle(stacks, rng)
	var row_order: Array = []
	var column_order: Array = []
	for band in bands:
		var rows := [0, 1, 2]
		_shuffle(rows, rng)
		for row in rows:
			row_order.append(band * 3 + row)
	for stack in stacks:
		var columns := [0, 1, 2]
		_shuffle(columns, rng)
		for column in columns:
			column_order.append(stack * 3 + column)
	var digits := [1, 2, 3, 4, 5, 6, 7, 8, 9]
	_shuffle(digits, rng)
	var result: Array = []
	for row in row_order:
		for column in column_order:
			var pattern: int = (row * 3 + row / 3 + column) % SIZE
			result.append(digits[pattern])
	return result


static func _carve_unique(solution: Array, target: int, rng: RandomNumberGenerator) -> Array:
	var puzzle := solution.duplicate()
	var pair_starts: Array = []
	for index in range(41):
		pair_starts.append(index)
	_shuffle(pair_starts, rng)
	for first in pair_starts:
		var second: int = CELL_COUNT - 1 - first
		var removal_count := 1 if first == second else 2
		if _clue_count(puzzle) - removal_count < target:
			continue
		var first_value: int = puzzle[first]
		var second_value: int = puzzle[second]
		puzzle[first] = 0
		puzzle[second] = 0
		if count_solutions(puzzle, 2) != 1:
			puzzle[first] = first_value
			puzzle[second] = second_value
		if _clue_count(puzzle) <= target:
			break
	return puzzle


static func _search_solutions(board: Array, limit: int) -> int:
	var best_index := -1
	var best_mask := 0
	var best_count := 10
	for index in range(CELL_COUNT):
		if int(board[index]) != 0:
			continue
		var mask := _allowed_mask(board, index)
		var option_count := _bit_count(mask)
		if option_count == 0:
			return 0
		if option_count < best_count:
			best_index = index
			best_mask = mask
			best_count = option_count
			if option_count == 1:
				break
	if best_index == -1:
		return 1
	var found := 0
	for digit in range(1, 10):
		if best_mask & (1 << digit) == 0:
			continue
		board[best_index] = digit
		found += _search_solutions(board, limit - found)
		board[best_index] = 0
		if found >= limit:
			break
	return found


static func _solve_copy(input: Array) -> Array:
	var board := input.duplicate()
	if _solve_first(board):
		return board
	return []


static func _solve_first(board: Array) -> bool:
	var best_index := -1
	var best_mask := 0
	var best_count := 10
	for index in range(CELL_COUNT):
		if int(board[index]) != 0:
			continue
		var mask := _allowed_mask(board, index)
		var option_count := _bit_count(mask)
		if option_count == 0:
			return false
		if option_count < best_count:
			best_index = index
			best_mask = mask
			best_count = option_count
	if best_index == -1:
		return true
	for digit in range(1, 10):
		if best_mask & (1 << digit) == 0:
			continue
		board[best_index] = digit
		if _solve_first(board):
			return true
		board[best_index] = 0
	return false


static func _allowed_mask(board: Array, index: int) -> int:
	var used := 0
	for peer in get_peers(index):
		var value: int = board[peer]
		if value != 0:
			used |= 1 << value
	return ALL_DIGITS_MASK & ~used


static func _unit_is_valid(board: Array, indices: Array[int]) -> bool:
	var seen := 0
	for index in indices:
		var value: int = board[index]
		if value < 0 or value > 9:
			return false
		if value == 0:
			continue
		var bit := 1 << value
		if seen & bit:
			return false
		seen |= bit
	return true


static func _row_indices(row: int) -> Array[int]:
	var result: Array[int] = []
	for column in range(SIZE):
		result.append(row * SIZE + column)
	return result


static func _column_indices(column: int) -> Array[int]:
	var result: Array[int] = []
	for row in range(SIZE):
		result.append(row * SIZE + column)
	return result


static func _box_indices(box: int) -> Array[int]:
	var result: Array[int] = []
	var top := (box / 3) * 3
	var left := (box % 3) * 3
	for row_offset in range(3):
		for column_offset in range(3):
			result.append((top + row_offset) * SIZE + left + column_offset)
	return result


static func _bit_count(mask: int) -> int:
	var value := mask
	var count := 0
	while value != 0:
		value &= value - 1
		count += 1
	return count


static func _clue_count(board: Array) -> int:
	var count := 0
	for value in board:
		if int(value) != 0:
			count += 1
	return count


static func _board_id(board: Array) -> String:
	var encoded := ""
	for value in board:
		encoded += str(value)
	return "p%08x" % (encoded.hash() & 0xffffffff)


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var current = items[index]
		items[index] = items[swap_index]
		items[swap_index] = current
