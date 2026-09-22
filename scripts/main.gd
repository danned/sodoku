extends Control

const APP_VERSION := "0.1.0"
const MAX_CONTENT_WIDTH := 620.0
const PAGE_GUTTER := 20.0
const DIFFICULTY_DESCRIPTIONS := {
	"easy": "A gentle warm-up",
	"medium": "A balanced challenge",
	"hard": "Careful deductions",
	"expert": "Deep focus required",
}

const LIGHT_PALETTE := {
	"background": Color("f7f5ef"),
	"surface": Color("ffffff"),
	"surface_raised": Color("fcfbf7"),
	"text": Color("10233f"),
	"muted": Color("637083"),
	"line": Color("d9ded9"),
	"line_strong": Color("40536b"),
	"accent": Color("2e8584"),
	"accent_soft": Color("dcefed"),
	"accent_text": Color("ffffff"),
	"danger": Color("c44d56"),
	"danger_soft": Color("fbe6e6"),
	"given": Color("0a1d39"),
}
const DARK_PALETTE := {
	"background": Color("071426"),
	"surface": Color("10243a"),
	"surface_raised": Color("142b43"),
	"text": Color("f6f2e8"),
	"muted": Color("a7b4c2"),
	"line": Color("30465a"),
	"line_strong": Color("93a8ba"),
	"accent": Color("62c2bc"),
	"accent_soft": Color("173f48"),
	"accent_text": Color("071426"),
	"danger": Color("ff858b"),
	"danger_soft": Color("4a2530"),
	"given": Color("ffffff"),
}

var palette: Dictionary = LIGHT_PALETTE.duplicate()
var current_screen := "home"
var background: ColorRect
var screen_host: Control
var page_root: Control
var loading_overlay: PanelContainer
var loading_label: Label
var generation_in_progress := false

var game_board_stack: Control
var game_grid: GridContainer
var game_cells: Array[Button] = []
var game_pause_overlay: PanelContainer
var game_pause_button: Button
var game_mistakes_label: Label
var game_time_label: Label
var game_hints_label: Label
var game_notes_button: Button
var game_keyboard_help: Label
var last_timer_second := -1


func _ready() -> void:
	palette = _resolve_palette()
	_build_shell()
	Store.changed.connect(_on_store_changed)
	Store.game_completed.connect(_on_game_completed)
	resized.connect(_layout_page)
	_navigate("home")
	set_process(true)


func _process(_delta: float) -> void:
	if current_screen != "game" or Store.active_game.is_empty() or game_time_label == null:
		return
	if Store.active_game.get("status", "") != "active" or not bool(Store.settings.show_timer):
		return
	var elapsed: int = GameRules.elapsed_time(Store.active_game, Store.now_ms())
	var second := elapsed / 1000
	if second != last_timer_second:
		last_timer_second = second
		game_time_label.text = _format_time(elapsed)


func _build_shell() -> void:
	background = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = palette.background
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	screen_host = Control.new()
	screen_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen_host)

	loading_overlay = PanelContainer.new()
	loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.add_theme_stylebox_override("panel", _style_box(Color(0.02, 0.07, 0.13, 0.58), 0))
	loading_overlay.visible = false
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(loading_overlay)
	var loading_center := CenterContainer.new()
	loading_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_overlay.add_child(loading_center)
	var loading_card := PanelContainer.new()
	loading_card.custom_minimum_size = Vector2(270, 108)
	loading_card.add_theme_stylebox_override("panel", _style_box(palette.surface, 20))
	loading_center.add_child(loading_card)
	var loading_content := VBoxContainer.new()
	loading_content.alignment = BoxContainer.ALIGNMENT_CENTER
	loading_content.add_theme_constant_override("separation", 8)
	loading_card.add_child(loading_content)
	loading_label = _label("Creating a unique puzzle…", 16, palette.text, HORIZONTAL_ALIGNMENT_CENTER)
	loading_content.add_child(loading_label)
	var loading_copy := _label("This happens entirely on your device.", 12, palette.muted, HORIZONTAL_ALIGNMENT_CENTER)
	loading_content.add_child(loading_copy)


func _navigate(screen_name: String) -> void:
	current_screen = screen_name
	_rebuild_screen()


func _open_game() -> void:
	if Store.active_game.is_empty():
		_navigate("home")
		return
	Store.resume_game()
	_navigate("game")


func _leave_game() -> void:
	Store.pause_game()
	_navigate("home")


func _rebuild_screen() -> void:
	for child in screen_host.get_children():
		screen_host.remove_child(child)
		child.free()
	_reset_game_references()
	page_root = Control.new()
	screen_host.add_child(page_root)
	match current_screen:
		"game":
			_build_game()
		"results":
			_build_results()
		"stats":
			_build_stats()
		"settings":
			_build_settings()
		"privacy":
			_build_privacy()
		_:
			_build_home()
	_layout_page()


func _reset_game_references() -> void:
	game_board_stack = null
	game_grid = null
	game_cells = []
	game_pause_overlay = null
	game_pause_button = null
	game_mistakes_label = null
	game_time_label = null
	game_hints_label = null
	game_notes_button = null
	game_keyboard_help = null
	last_timer_second = -1


func _layout_page() -> void:
	if page_root == null:
		return
	var available_width := maxf(280.0, size.x - PAGE_GUTTER * 2.0)
	var target_width := minf(MAX_CONTENT_WIDTH, available_width)
	page_root.position = Vector2((size.x - target_width) * 0.5, 0)
	page_root.size = Vector2(target_width, size.y)
	if game_board_stack != null and is_instance_valid(game_board_stack):
		var board_limit := minf(520.0, minf(target_width - 4.0, size.y - 292.0))
		var cell_size := maxf(26.0, floor(board_limit / 9.0))
		var board_size := cell_size * 9.0
		game_board_stack.custom_minimum_size = Vector2(board_size, board_size)
		if game_grid != null:
			game_grid.custom_minimum_size = Vector2(board_size, board_size)
		for cell in game_cells:
			cell.custom_minimum_size = Vector2(cell_size, cell_size)


func _build_home() -> void:
	var scroll := _full_scroll()
	page_root.add_child(scroll)
	var content := _scroll_content(24)
	scroll.add_child(content)

	var top_actions := HBoxContainer.new()
	top_actions.alignment = BoxContainer.ALIGNMENT_END
	top_actions.add_theme_constant_override("separation", 10)
	content.add_child(top_actions)
	var stats_button := _button("▥", _navigate.bind("stats"), "icon", 46)
	stats_button.tooltip_text = "Statistics"
	stats_button.custom_minimum_size.x = 46
	top_actions.add_child(stats_button)
	var settings_button := _button("⚙", _navigate.bind("settings"), "icon", 46)
	settings_button.tooltip_text = "Settings"
	settings_button.custom_minimum_size.x = 46
	top_actions.add_child(settings_button)

	var hero := VBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 4)
	content.add_child(hero)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/icon.png")
	logo.custom_minimum_size = Vector2(96, 96)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero.add_child(logo)
	var title := _label("Sudoku", 38, palette.text, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 0)
	hero.add_child(title)
	hero.add_child(_label("A quiet space to think.", 16, palette.muted, HORIZONTAL_ALIGNMENT_CENTER))
	_add_spacer(content, 18)

	if Store.has_unfinished_game():
		var difficulty: String = Store.active_game.puzzle.difficulty
		var continue_button := _button("Continue %s" % SudokuEngine.difficulty_label(difficulty), _open_game, "primary", 54)
		content.add_child(continue_button)
		_add_spacer(content, 14)

	content.add_child(_section_label("NEW PUZZLE"))
	for index in range(SudokuEngine.DIFFICULTIES.size()):
		var difficulty: String = SudokuEngine.DIFFICULTIES[index]
		content.add_child(_difficulty_card(difficulty, index))


func _difficulty_card(difficulty: String, index: int) -> Button:
	var button := _button("", _choose_difficulty.bind(difficulty), "card", 78)
	button.tooltip_text = "%s difficulty — %s" % [SudokuEngine.difficulty_label(difficulty), DIFFICULTY_DESCRIPTIONS[difficulty]]
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 13)
	margin.add_theme_constant_override("margin_right", 13)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var number_panel := PanelContainer.new()
	number_panel.custom_minimum_size = Vector2(50, 50)
	var number_color: Color = palette.accent if index == 0 else palette.accent_soft
	number_panel.add_theme_stylebox_override("panel", _style_box(number_color, 14))
	number_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(number_panel)
	var number_text_color: Color = palette.accent_text if index == 0 else palette.accent
	number_panel.add_child(_label(str(index + 1), 18, number_text_color, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER))
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(copy)
	copy.add_child(_label(SudokuEngine.difficulty_label(difficulty), 17, palette.text))
	copy.add_child(_label(DIFFICULTY_DESCRIPTIONS[difficulty], 13, palette.muted))
	row.add_child(_label("›", 27, palette.muted, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER))
	return button


func _choose_difficulty(difficulty: String) -> void:
	if generation_in_progress:
		return
	if Store.has_unfinished_game():
		_show_confirmation(
			"Start a new puzzle?",
			"Your current puzzle will be replaced. Its progress cannot be recovered.",
			"Start new",
			_generate_and_open.bind(difficulty)
		)
	else:
		_generate_and_open(difficulty)


func _generate_and_open(difficulty: String) -> void:
	if generation_in_progress:
		return
	generation_in_progress = true
	loading_label.text = "Creating a unique %s puzzle…" % difficulty
	loading_overlay.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var succeeded: bool = Store.start_game(difficulty)
	loading_overlay.visible = false
	generation_in_progress = false
	if succeeded:
		_navigate("game")
	else:
		_show_message("Could not create puzzle", "Please try again.")


func _build_game() -> void:
	if Store.active_game.is_empty():
		current_screen = "home"
		_build_home()
		return
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	page_root.add_child(page)
	var difficulty: String = Store.active_game.puzzle.difficulty
	_make_header(page, SudokuEngine.difficulty_label(difficulty), "Sudoku", "Pause", Store.toggle_pause, _leave_game)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	page.add_child(meta)
	var mistakes := _meta_block("MISTAKES", "0", HORIZONTAL_ALIGNMENT_LEFT)
	meta.add_child(mistakes)
	game_mistakes_label = mistakes.get_node("Value")
	var time := _meta_block("TIME", "0:00", HORIZONTAL_ALIGNMENT_CENTER)
	time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(time)
	game_time_label = time.get_node("Value")
	var hints := _meta_block("HINTS", "0", HORIZONTAL_ALIGNMENT_RIGHT)
	meta.add_child(hints)
	game_hints_label = hints.get_node("Value")

	var board_center := CenterContainer.new()
	board_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.add_child(board_center)
	game_board_stack = Control.new()
	board_center.add_child(game_board_stack)
	game_grid = GridContainer.new()
	game_grid.columns = 9
	game_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_grid.add_theme_constant_override("h_separation", 0)
	game_grid.add_theme_constant_override("v_separation", 0)
	game_board_stack.add_child(game_grid)
	for index in range(81):
		var cell := Button.new()
		cell.focus_mode = Control.FOCUS_ALL
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.add_theme_font_size_override("font_size", 23)
		cell.pressed.connect(Store.select_cell.bind(index))
		game_grid.add_child(cell)
		game_cells.append(cell)

	game_pause_overlay = PanelContainer.new()
	game_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_pause_overlay.add_theme_stylebox_override("panel", _style_box(palette.background, 5))
	game_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	game_board_stack.add_child(game_pause_overlay)
	var pause_center := CenterContainer.new()
	game_pause_overlay.add_child(pause_center)
	var pause_content := VBoxContainer.new()
	pause_content.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_content.add_theme_constant_override("separation", 6)
	pause_center.add_child(pause_content)
	pause_content.add_child(_label("Puzzle paused", 23, palette.text, HORIZONTAL_ALIGNMENT_CENTER))
	pause_content.add_child(_label("Your board is hidden.", 14, palette.muted, HORIZONTAL_ALIGNMENT_CENTER))
	_add_spacer(pause_content, 8)
	var resume_button := _button("Resume", Store.resume_game, "primary", 48)
	resume_button.custom_minimum_size.x = 150
	resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pause_content.add_child(resume_button)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	page.add_child(actions)
	for action_data in [
		["Undo", Store.undo],
		["Redo", Store.redo],
		["Erase", Store.erase],
	]:
		var action_button := _button(action_data[0], action_data[1], "control", 42)
		action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(action_button)
	game_notes_button = _button("Notes", Store.toggle_notes, "control", 42)
	game_notes_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(game_notes_button)
	var hint_button := _button("Hint", Store.hint, "control", 42)
	hint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(hint_button)

	var keypad := HBoxContainer.new()
	keypad.add_theme_constant_override("separation", 4)
	page.add_child(keypad)
	for digit in range(1, 10):
		var digit_button := _button(str(digit), Store.enter_digit.bind(digit), "key", 50)
		digit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keypad.add_child(digit_button)

	game_keyboard_help = _label("1–9 enter · Backspace erase · N notes · H hint · Space pause", 11, palette.muted, HORIZONTAL_ALIGNMENT_CENTER)
	game_keyboard_help.visible = OS.has_feature("web") or OS.has_feature("pc")
	page.add_child(game_keyboard_help)
	_refresh_game()


func _meta_block(caption: String, value: String, alignment: HorizontalAlignment) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.custom_minimum_size.x = 86
	var caption_label := _label(caption, 10, palette.muted, alignment)
	block.add_child(caption_label)
	var value_label := _label(value, 15, palette.text, alignment)
	value_label.name = "Value"
	block.add_child(value_label)
	return block


func _refresh_game() -> void:
	if current_screen != "game" or Store.active_game.is_empty() or game_cells.size() != 81:
		return
	var game: Dictionary = Store.active_game
	var auto_check: bool = bool(Store.settings.get("auto_check_mistakes", false))
	game_mistakes_label.text = str(game.mistakes) if auto_check else "—"
	game_hints_label.text = str(game.hints_used)
	game_time_label.visible = bool(Store.settings.show_timer)
	game_time_label.get_parent().visible = bool(Store.settings.show_timer)
	game_time_label.text = _format_time(GameRules.elapsed_time(game, Store.now_ms()))
	game_pause_overlay.visible = game.status == "paused"
	game_pause_button.text = "Resume" if game.status == "paused" else "Pause"
	game_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE if game.status == "paused" else Control.MOUSE_FILTER_PASS
	game_notes_button.text = "Notes on" if bool(game.notes_mode) else "Notes"
	_style_button(game_notes_button, "active_control" if bool(game.notes_mode) else "control")
	var selected: int = game.selected_cell
	var selected_value := 0
	if selected >= 0:
		selected_value = int(game.board[selected])
	var peers := {}
	if selected >= 0:
		for peer in SudokuEngine.get_peers(selected):
			peers[peer] = true
	for index in range(81):
		var cell := game_cells[index]
		var value: int = game.board[index]
		var given: bool = int(game.puzzle.givens[index]) != 0
		var wrong := (
			GameRules.has_conflict(game, index)
			or (auto_check and value != 0 and value != int(game.puzzle.solution[index]))
		)
		var hinted: bool = index in game.hinted_cells
		var is_selected := selected == index
		var is_peer: bool = bool(Store.settings.highlight_peers) and peers.has(index)
		var is_match: bool = bool(Store.settings.highlight_matches) and value != 0 and selected_value != 0 and value == selected_value
		var cell_background: Color = palette.surface
		if wrong:
			cell_background = palette.danger_soft
		elif is_selected:
			cell_background = palette.accent
		elif is_match:
			cell_background = palette.accent_soft
		elif is_peer:
			cell_background = palette.surface_raised
		var text_color: Color = palette.text
		if is_selected:
			text_color = palette.accent_text
		elif wrong:
			text_color = palette.danger
		elif hinted:
			text_color = palette.accent
		elif given:
			text_color = palette.given
		cell.text = str(value) if value != 0 else _notes_text(int(game.notes[index]))
		cell.add_theme_font_size_override("font_size", 23 if value != 0 else 9)
		cell.add_theme_color_override("font_color", text_color)
		cell.add_theme_color_override("font_hover_color", text_color)
		cell.add_theme_color_override("font_pressed_color", text_color)
		cell.add_theme_color_override("font_focus_color", text_color)
		var style := _cell_style(cell_background, index)
		cell.add_theme_stylebox_override("normal", style)
		cell.add_theme_stylebox_override("hover", _cell_style(cell_background.lerp(palette.accent_soft, 0.28), index))
		cell.add_theme_stylebox_override("pressed", _cell_style(cell_background.lerp(palette.accent, 0.18), index))
		cell.add_theme_stylebox_override("focus", _cell_style(cell_background, index, palette.accent))
		var row := index / 9 + 1
		var column := index % 9 + 1
		cell.tooltip_text = "Row %d, column %d%s" % [row, column, " — %d" % value if value != 0 else " — empty"]


func _notes_text(mask: int) -> String:
	if mask == 0:
		return ""
	var lines: Array[String] = []
	for row in range(3):
		var values: Array[String] = []
		for column in range(3):
			var digit := row * 3 + column + 1
			values.append(str(digit) if mask & (1 << digit) else " ")
		lines.append("  ".join(values))
	return "\n".join(lines)


func _build_results() -> void:
	if Store.last_completed.is_empty():
		current_screen = "home"
		_build_home()
		return
	var scroll := _full_scroll()
	page_root.add_child(scroll)
	var content := _scroll_content(12)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(76, 76)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _style_box(palette.accent_soft, 38))
	badge.add_child(_label("✓", 36, palette.accent, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER))
	content.add_child(badge)
	content.add_child(_label("PUZZLE COMPLETE", 12, palette.accent, HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(_label("Nicely solved.", 34, palette.text, HORIZONTAL_ALIGNMENT_CENTER))
	var summary: Dictionary = Store.last_completed
	var solve_type := "Assisted solve" if bool(summary.assisted) else "Unassisted solve"
	content.add_child(_label("%s · %s" % [SudokuEngine.difficulty_label(summary.difficulty), solve_type], 15, palette.muted, HORIZONTAL_ALIGNMENT_CENTER))
	_add_spacer(content, 12)
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 9)
	content.add_child(metrics)
	metrics.add_child(_metric("Time", _format_time(int(summary.elapsed_ms))))
	metrics.add_child(_metric("Mistakes", str(summary.mistakes)))
	metrics.add_child(_metric("Hints", str(summary.hints_used)))
	if bool(summary.assisted):
		var notice := _card_panel(14)
		notice.add_theme_stylebox_override("panel", _style_box(palette.accent_soft, 14))
		notice.add_child(_label("Assisted games count toward completions, but not personal-best times.", 13, palette.text, HORIZONTAL_ALIGNMENT_CENTER))
		content.add_child(notice)
	_add_spacer(content, 8)
	content.add_child(_button("Play another %s" % SudokuEngine.difficulty_label(summary.difficulty), _generate_and_open.bind(summary.difficulty), "primary", 54))
	content.add_child(_button("Back to home", _navigate.bind("home"), "secondary", 52))


func _build_stats() -> void:
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_root.add_child(page)
	_make_header(page, "Statistics", "", "", Callable(), _navigate.bind("home"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var content := _scroll_content(11)
	scroll.add_child(content)
	var totals := {"started": 0, "completed": 0, "assisted": 0}
	for difficulty in SudokuEngine.DIFFICULTIES:
		var entry: Dictionary = Store.stats[difficulty]
		totals.started += int(entry.started)
		totals.completed += int(entry.completed)
		totals.assisted += int(entry.assisted_completed)
	var overview := HBoxContainer.new()
	overview.add_theme_constant_override("separation", 8)
	content.add_child(overview)
	overview.add_child(_metric("Completed", str(totals.completed)))
	overview.add_child(_metric("Completion", _format_percent(totals.completed, totals.started)))
	overview.add_child(_metric("Assisted", str(totals.assisted)))
	_add_spacer(content, 8)
	content.add_child(_section_label("BY DIFFICULTY"))
	for difficulty in SudokuEngine.DIFFICULTIES:
		content.add_child(_stats_card(difficulty))


func _stats_card(difficulty: String) -> PanelContainer:
	var entry: Dictionary = Store.stats[difficulty]
	var card := _card_panel(17)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	card.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := _label(SudokuEngine.difficulty_label(difficulty), 18, palette.text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("%d solved" % int(entry.completed), 13, palette.accent, HORIZONTAL_ALIGNMENT_RIGHT))
	content.add_child(_stat_row("Completion rate", _format_percent(int(entry.completed), int(entry.started))))
	var average := 0
	if int(entry.completed) > 0:
		average = int(entry.total_time_ms) / int(entry.completed)
	content.add_child(_stat_row("Average time", _format_time(average) if average > 0 else "—"))
	content.add_child(_stat_row("Best unassisted", _format_time(int(entry.best_time_ms)) if int(entry.best_time_ms) > 0 else "—"))
	content.add_child(_stat_row("Mistakes / hints", "%d / %d" % [int(entry.total_mistakes), int(entry.total_hints)]))
	return card


func _stat_row(caption: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var caption_label := _label(caption, 13, palette.muted)
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption_label)
	row.add_child(_label(value, 13, palette.text, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


func _build_settings() -> void:
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_root.add_child(page)
	_make_header(page, "Settings", "", "", Callable(), _navigate.bind("home"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var content := _scroll_content(8)
	scroll.add_child(content)
	content.add_child(_section_label("APPEARANCE"))
	var segment := HBoxContainer.new()
	segment.add_theme_constant_override("separation", 4)
	content.add_child(segment)
	for mode in ["system", "light", "dark"]:
		var active: bool = Store.settings.appearance == mode
		var mode_button := _button(mode.capitalize(), Store.update_setting.bind("appearance", mode), "segment_active" if active else "segment", 44)
		mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.add_child(mode_button)
	_add_spacer(content, 8)
	content.add_child(_section_label("GAMEPLAY"))
	var gameplay_panel := _settings_group()
	content.add_child(gameplay_panel)
	var gameplay: VBoxContainer = gameplay_panel.get_node("Rows")
	gameplay.add_child(_setting_row("Haptic feedback", "haptics"))
	gameplay.add_child(_divider())
	gameplay.add_child(_setting_row("Show timer", "show_timer"))
	gameplay.add_child(_divider())
	gameplay.add_child(_setting_row("Auto-check mistakes", "auto_check_mistakes"))
	gameplay.add_child(_divider())
	gameplay.add_child(_setting_row("Highlight row, column, and box", "highlight_peers"))
	gameplay.add_child(_divider())
	gameplay.add_child(_setting_row("Highlight matching numbers", "highlight_matches"))
	_add_spacer(content, 8)
	content.add_child(_section_label("PRIVACY"))
	var privacy_panel := _settings_group()
	content.add_child(privacy_panel)
	var privacy: VBoxContainer = privacy_panel.get_node("Rows")
	privacy.add_child(_link_row("Privacy overview", _navigate.bind("privacy")))
	_add_spacer(content, 8)
	content.add_child(_section_label("DATA"))
	var data_panel := _settings_group()
	content.add_child(data_panel)
	var data: VBoxContainer = data_panel.get_node("Rows")
	data.add_child(_link_row("Reset all local data", _confirm_reset, true))
	_add_spacer(content, 10)
	content.add_child(_label("Sudoku %s · Godot 4.7" % APP_VERSION, 12, palette.muted, HORIZONTAL_ALIGNMENT_CENTER))


func _setting_row(caption: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 56
	var title := _label(caption, 15, palette.text, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var enabled: bool = bool(Store.settings[key])
	var toggle := _button("On" if enabled else "Off", Store.update_setting.bind(key, not enabled), "toggle_on" if enabled else "toggle_off", 36)
	toggle.custom_minimum_size.x = 66
	row.add_child(toggle)
	return row


func _link_row(caption: String, callback: Callable, danger := false) -> Button:
	var button := _button("", callback, "flat", 56)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label(caption, 15, palette.danger if danger else palette.text, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_CENTER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(_label("›", 25, palette.muted, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_CENTER))
	button.add_child(row)
	return button


func _settings_group() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box_with_content(palette.surface, 17, 15))
	var group := VBoxContainer.new()
	group.name = "Rows"
	group.add_theme_constant_override("separation", 0)
	panel.add_child(group)
	return panel


func _confirm_reset() -> void:
	_show_confirmation(
		"Reset all local data?",
		"This removes your active puzzle, statistics, settings, and saved progress from this device.",
		"Reset",
		_reset_data
	)


func _reset_data() -> void:
	Store.clear_all_data()
	_navigate("home")


func _build_privacy() -> void:
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_root.add_child(page)
	_make_header(page, "Privacy", "", "", Callable(), _navigate.bind("settings"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var content := _scroll_content(10)
	scroll.add_child(content)
	content.add_child(_label("A plain-language overview of how this app handles data.", 15, palette.muted))
	var sections := [
		["Your puzzle data stays here", "Current games, preferences, generated puzzles, and statistics are stored only on this device. Sudoku has no accounts and does not upload your puzzle history."],
		["Browser storage", "In the browser build, Godot stores your save in this browser’s IndexedDB. Private browsing or blocked site storage may prevent progress from surviving after the tab closes."],
		["No tracking", "This Godot version contains no analytics, account system, cross-app tracking, or remote puzzle service."],
		["Offline play", "Puzzle generation and gameplay happen on your device. Once the browser build has loaded, the game can continue without a network connection."],
		["Removing local data", "Use “Reset all local data” in Settings to remove your current game, statistics, preferences, and saved progress from this device."],
	]
	for section in sections:
		var card := _card_panel(17)
		var card_content := VBoxContainer.new()
		card_content.add_theme_constant_override("separation", 7)
		card.add_child(card_content)
		card_content.add_child(_label(section[0], 16, palette.text))
		var body := _label(section[1], 14, palette.muted)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_content.add_child(body)
		content.add_child(card)


func _make_header(parent: VBoxContainer, title_text: String, subtitle_text: String, action_text: String, action: Callable, back: Callable) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 62
	header.add_theme_constant_override("separation", 4)
	parent.add_child(header)
	var left := HBoxContainer.new()
	left.custom_minimum_size.x = 76
	header.add_child(left)
	if back.is_valid():
		var back_button := _button("‹", back, "flat", 44)
		back_button.custom_minimum_size.x = 44
		left.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label(title_text, 20, palette.text, HORIZONTAL_ALIGNMENT_CENTER))
	if not subtitle_text.is_empty():
		titles.add_child(_label(subtitle_text, 12, palette.muted, HORIZONTAL_ALIGNMENT_CENTER))
	var right := HBoxContainer.new()
	right.custom_minimum_size.x = 76
	right.alignment = BoxContainer.ALIGNMENT_END
	header.add_child(right)
	if action.is_valid() and not action_text.is_empty():
		var action_button := _button(action_text, action, "text", 44)
		action_button.custom_minimum_size.x = 72
		right.add_child(action_button)
		if current_screen == "game":
			game_pause_button = action_button


func _full_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return scroll


func _scroll_content(separation: int) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", separation)
	return content


func _card_panel(padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style_box_with_content(palette.surface, 17, padding))
	return panel


func _metric(caption: String, value: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 90
	panel.add_theme_stylebox_override("panel", _style_box_with_content(palette.surface, 16, 14))
	var content := VBoxContainer.new()
	panel.add_child(content)
	content.add_child(_label(value, 20, palette.text))
	content.add_child(_label(caption, 12, palette.muted))
	return panel


func _divider() -> ColorRect:
	var divider := ColorRect.new()
	divider.color = palette.line
	divider.custom_minimum_size.y = 1
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


func _section_label(text: String) -> Label:
	var label := _label(text, 12, palette.muted)
	label.add_theme_constant_override("outline_size", 0)
	return label


func _label(text: String, font_size: int, color: Color, horizontal := HORIZONTAL_ALIGNMENT_LEFT, vertical := VERTICAL_ALIGNMENT_TOP) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = horizontal
	label.vertical_alignment = vertical
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, callback: Callable, kind: String, height: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = height
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback, CONNECT_DEFERRED)
	_style_button(button, kind)
	return button


func _style_button(button: Button, kind: String) -> void:
	var normal_color: Color = palette.surface
	var font_color: Color = palette.text
	var radius := 14
	var border_color: Color = Color.TRANSPARENT
	var border_width := 0
	match kind:
		"primary":
			normal_color = palette.accent
			font_color = palette.accent_text
			radius = 16
		"secondary":
			normal_color = palette.surface
			border_color = palette.line
			border_width = 1
			radius = 16
		"card":
			normal_color = palette.surface
			border_color = palette.line
			border_width = 1
			radius = 18
		"icon":
			radius = 15
		"control":
			radius = 12
			button.add_theme_font_size_override("font_size", 12)
		"active_control":
			normal_color = palette.accent_soft
			font_color = palette.accent
			radius = 12
			button.add_theme_font_size_override("font_size", 12)
		"key":
			font_color = palette.accent
			radius = 12
			button.add_theme_font_size_override("font_size", 23)
		"text":
			normal_color = Color.TRANSPARENT
			font_color = palette.accent
			radius = 10
		"flat":
			normal_color = Color.TRANSPARENT
			radius = 0
		"segment":
			normal_color = palette.surface
			font_color = palette.muted
			radius = 11
		"segment_active":
			normal_color = palette.accent_soft
			font_color = palette.accent
			radius = 11
		"toggle_on":
			normal_color = palette.accent
			font_color = palette.accent_text
			radius = 18
		"toggle_off":
			normal_color = palette.line
			font_color = palette.text
			radius = 18
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_color_override("font_focus_color", font_color)
	button.add_theme_stylebox_override("normal", _button_box(normal_color, radius, border_color, border_width))
	button.add_theme_stylebox_override("hover", _button_box(normal_color.lerp(palette.accent_soft, 0.35), radius, border_color, border_width))
	button.add_theme_stylebox_override("pressed", _button_box(normal_color.lerp(palette.accent, 0.22), radius, border_color, border_width))
	button.add_theme_stylebox_override("focus", _button_box(normal_color, radius, palette.accent, 2))


func _button_box(color: Color, radius: int, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := _style_box(color, radius)
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _style_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _style_box_with_content(color: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := _style_box(color, radius)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style


func _cell_style(color: Color, index: int, focus_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = palette.line_strong if focus_color == Color.TRANSPARENT else focus_color
	var row := index / 9
	var column := index % 9
	style.border_width_left = 2 if column == 0 else 0
	style.border_width_top = 2 if row == 0 else 0
	style.border_width_right = 2 if column == 8 or column % 3 == 2 else 1
	style.border_width_bottom = 2 if row == 8 or row % 3 == 2 else 1
	if focus_color != Color.TRANSPARENT:
		style.border_width_left = maxi(style.border_width_left, 2)
		style.border_width_top = maxi(style.border_width_top, 2)
		style.border_width_right = maxi(style.border_width_right, 2)
		style.border_width_bottom = maxi(style.border_width_bottom, 2)
	if row == 0 and column == 0:
		style.corner_radius_top_left = 5
	if row == 0 and column == 8:
		style.corner_radius_top_right = 5
	if row == 8 and column == 0:
		style.corner_radius_bottom_left = 5
	if row == 8 and column == 8:
		style.corner_radius_bottom_right = 5
	return style


func _add_spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)


func _show_confirmation(title_text: String, message: String, confirm_text: String, callback: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	dialog.dialog_text = message
	dialog.ok_button_text = confirm_text
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		callback.call()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(390, 220))


func _show_message(title_text: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title_text
	dialog.dialog_text = message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(360, 190))


func _resolve_palette() -> Dictionary:
	var appearance: String = Store.settings.get("appearance", "system") if is_instance_valid(Store) else "system"
	var dark_mode := appearance == "dark"
	if appearance == "system" and DisplayServer.has_method("is_dark_mode"):
		dark_mode = DisplayServer.is_dark_mode()
	return DARK_PALETTE.duplicate() if dark_mode else LIGHT_PALETTE.duplicate()


func _on_store_changed() -> void:
	var next_palette := _resolve_palette()
	var palette_changed: bool = next_palette.background != palette.background
	if palette_changed:
		palette = next_palette
		background.color = palette.background
		_rebuild_screen()
		return
	if current_screen == "game":
		_refresh_game()
	elif current_screen in ["home", "stats", "settings"]:
		_rebuild_screen()


func _on_game_completed() -> void:
	_navigate("results")


func _format_time(milliseconds: int) -> String:
	var seconds := maxi(0, milliseconds / 1000)
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	var remainder := seconds % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, remainder]
	return "%d:%02d" % [minutes, remainder]


func _format_percent(numerator: int, denominator: int) -> String:
	if denominator <= 0:
		return "0%"
	return "%d%%" % roundi(float(numerator) / float(denominator) * 100.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		_handle_back()
		get_viewport().set_input_as_handled()
		return
	if current_screen != "game" or Store.active_game.is_empty():
		return
	if event.keycode == KEY_SPACE:
		Store.toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if Store.active_game.get("status", "") != "active":
		return
	if event.ctrl_pressed or event.meta_pressed:
		if event.keycode == KEY_Z:
			Store.redo() if event.shift_pressed else Store.undo()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Y:
			Store.redo()
			get_viewport().set_input_as_handled()
			return
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		Store.enter_digit(event.keycode - KEY_0)
		get_viewport().set_input_as_handled()
	elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
		Store.enter_digit(event.keycode - KEY_KP_0)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_BACKSPACE or event.keycode == KEY_DELETE:
		Store.erase()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_N:
		Store.toggle_notes()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_H:
		Store.hint()
		get_viewport().set_input_as_handled()


func _handle_back() -> void:
	match current_screen:
		"game":
			_leave_game()
		"privacy":
			_navigate("settings")
		"home":
			get_tree().quit()
		_:
			_navigate("home")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
