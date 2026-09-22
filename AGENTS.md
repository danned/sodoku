This is a Godot 4 application written in typed GDScript. Keep gameplay rules independent from UI code, preserve touch/mouse/keyboard parity, and verify changes with the headless test suite plus a native or web export when relevant.

## Commands

```bash
godot --headless --path . --script res://scripts/tests/test_runner.gd
godot --headless --path . --script res://scripts/tests/ui_smoke.gd
godot --headless --path . --export-release Web build/web/index.html
godot --headless --path . --export-debug Android build/android/sudoku-debug.apk
```

## Commit Style

Never add Codex attribution. Do not add a "Generated with Codex" footer or a "Co-Authored-By: Codex" trailer to commits.
