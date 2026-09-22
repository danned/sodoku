# Sudoku

A calm, offline-first Sudoku game built with Godot 4 for Android, iOS, desktop, and the web.

The game generates unique puzzles on-device, supports notes, hints, undo/redo, pause and resume, autosaves progress, tracks local statistics, and adapts from phone-sized portrait layouts to desktop browsers. Entries are not compared with the hidden solution unless the optional Auto-check mistakes setting is enabled. It has no accounts, analytics, ads, or remote puzzle service.

## Run it

Install Godot 4.7.2 or another compatible Godot 4.7 release, then open `project.godot` in the editor and press **F6/F5**, or run it directly:

```bash
godot --path .
```

## Browser version

Install the matching Godot web export templates from **Editor → Manage Export Templates**, then run:

```bash
make web-export
make web-serve
```

Open `http://127.0.0.1:4173`. The exported progressive web app is written to `build/web/`. Browser saves use Godot's persistent `user://` filesystem, backed by IndexedDB when site storage is available.

### GitHub Pages

The [Pages workflow](.github/workflows/pages.yml) tests and exports the game with Godot 4.7.2, then deploys `build/web/` whenever a commit is pushed to `main`. Pull requests run the same tests and export without deploying. The workflow can also be started manually from the **Actions** tab.

Before the first deployment, open **Settings → Pages** in the GitHub repository and set **Build and deployment → Source** to **GitHub Actions**. Once the workflow succeeds, the game will be available at `https://danned.github.io/soduko/`.

During a game, use the on-screen controls or:

- `1`–`9` to enter a number
- `Backspace` or `Delete` to erase
- `N` to toggle notes
- `H` for a hint
- `Space` to pause or resume
- `Ctrl/Cmd+Z` to undo and `Ctrl/Cmd+Y` to redo

## Android

With the Android SDK and matching Godot Android templates installed:

```bash
make android-debug
```

The debug APK is created at `build/android/sudoku-debug.apk`. Replace `com.example.sudoku` in `export_presets.cfg` before publishing.

iOS export is configured in `export_presets.cfg`, but signing and final export require macOS, Xcode, and an Apple team ID.

## Tests

```bash
make test
make smoke
```

The automated suite checks puzzle validity, unique solutions across all four difficulties, clue targets, notes, hints, undo/redo, and timer state. The smoke check constructs every non-game screen in a headless Godot instance.

## Project structure

- `project.godot`: Godot project and cross-platform display settings.
- `scenes/`: the main scene.
- `scripts/sudoku_engine.gd`: deterministic generator, validator, solver, and uniqueness checks.
- `scripts/game_rules.gd`: gameplay state transitions.
- `scripts/app_store.gd`: local persistence, settings, and statistics.
- `scripts/main.gd`: responsive screen and board UI.
- `scripts/tests/`: headless engine and UI smoke tests.
- `assets/`: shared app icon and splash artwork.

## License

Copyright © 2026 Daniel Dahlberg. All rights reserved. The original work in this repository may not be copied, modified, distributed, or reused without prior written permission. Playing the official published version for personal, non-commercial purposes is permitted. See [LICENSE](LICENSE) for the complete terms and [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) for software covered by other licenses.
