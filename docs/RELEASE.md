# Beta and Store Release Checklist

## Identity and signing

- Replace `com.example.sudoku` in the Android and iOS presets in `export_presets.cfg`.
- Set the Apple team ID in the iOS export preset.
- Create the App Store Connect and Google Play Console records.
- Publish the final privacy policy and support URL.
- Prepare production Android and Apple signing credentials outside the repository.

## Verification

```bash
make test
make smoke
make web-export
make android-debug
```

Verify release candidates on at least one current iPhone, iPad, Android phone, Android tablet, and a desktop browser. Check small screens, light/dark appearance, keyboard and touch input, background/resume timing, offline startup, save restoration, IndexedDB persistence, and reset-data behavior.

## Store disclosures

- The app has no accounts, analytics, advertising, or cross-app tracking.
- Puzzle progress, preferences, and aggregate statistics stay on the device.
- No network permission is required for the Android game build.
- Supply screenshots, support URL, privacy-policy URL, age rating, copyright, and review notes.

## Production builds

- Android: select the Android preset in Godot, configure a release keystore, and export an AAB for Google Play.
- iOS: export the Xcode project on macOS, configure the Apple team and signing profile, then archive it in Xcode.
- Web: export the Web preset and deploy the complete contents of `build/web/` without renaming generated files.
