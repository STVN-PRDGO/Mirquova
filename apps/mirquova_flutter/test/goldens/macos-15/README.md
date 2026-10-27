# Hosted macOS visual references

These four images were produced by Flutter 3.47.8 in the `desktop-unix (macos-15)` job for commit `02319729e1762d127e3c4ece9c88a92a4789e6a1`, [Actions run 40472537161](https://github.com/STVN-PRDGO/Mirquova/actions/runs/40472537161). They were downloaded unchanged from artifact `visual-comparison-macOS` (artifact ID `12719801793`), using the `*_testImage.png` renders. The actual renders and difference images were reviewed before adoption. Differences from the preserved local references were at glyph/icon edges (approximately 0.05–0.13% of pixels); no layout change or broad comparator tolerance was accepted.

CI selects these exact references with `--dart-define=MIRQUOVA_GOLDEN_PROFILE=macos-15`, including when its macOS packaging script reruns tests. The existing parent-directory images remain the default `local` profile. Unknown profiles fail explicitly. These are widget renders, not native-app or physical-device evidence.

| File | Raster dimensions | SHA-256 |
| --- | --- | --- |
| `nearby_dark_1440.png` | 4320 × 2700 | `e1854c7278f3fba0d7c1928974fd83847a0e2d13b3a57c6e924c6820b08e1779` |
| `nearby_dark_375.png` | 1125 × 2436 | `02fb4a9aa58ca5773b86889310907eb6252a5f3194785b3442d04ffc13def1c7` |
| `nearby_light_1440.png` | 4320 × 2700 | `608a3220042e4e6340933ec893050ee125d21dea2627c6f54ff5f7661a9b08eb` |
| `nearby_light_375.png` | 1125 × 2436 | `4f13a6b99a2bb86cbdc456cce9aa5d31f31e4e570e071394acb362e1163dd08e` |

To update this profile deliberately, render on the matching hosted macOS reference toolchain with:

```sh
flutter test --no-pub --tags golden --dart-define=MIRQUOVA_GOLDEN_PROFILE=macos-15 --update-goldens test/render_previews_test.dart
```

Review all four outputs and record the producing run/toolchain before committing them. Do not overwrite this profile with a developer-machine render or regenerate images automatically during normal CI comparisons. The existing artifact upload preserves differences for review when a comparison fails.
