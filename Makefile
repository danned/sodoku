GODOT ?= godot

.PHONY: run editor test smoke web-export web-serve android-debug

run:
	$(GODOT) --path .

editor:
	$(GODOT) --editor --path .

test:
	$(GODOT) --headless --path . --script res://scripts/tests/test_runner.gd

smoke:
	$(GODOT) --headless --path . --script res://scripts/tests/ui_smoke.gd

web-export:
	mkdir -p build/web
	$(GODOT) --headless --path . --export-release Web build/web/index.html

web-serve:
	python3 -m http.server 4173 --directory build/web

android-debug:
	mkdir -p build/android
	$(GODOT) --headless --path . --export-debug Android build/android/sudoku-debug.apk
