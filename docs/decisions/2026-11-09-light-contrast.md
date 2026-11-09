# 2026-11-09 Light theme contrast adjustments

Made by the manager while implementing #26. Canvas note n33 ("mint and coral darken to keep 4.5:1 contrast on paper") and the 9 Nov review both require 4.5:1 for text, and two light values in the context pack fall short. The owner may override.

## Adjusted values
Each colour was darkened by the smallest uniform step that reaches 4.5:1 on every light surface it can sit on: paper `#F4F1EA`, card `#FFFFFF` and raised `#F0EDE5`.

| Token | Context pack | Adjusted | Worst case before | Worst case after |
| --- | --- | --- | --- | --- |
| Light mint (owed to you) | `#1E7F5C` | `#1D7A58` | 4.23:1 on `#F0EDE5` (4.39:1 on paper) | 4.51:1 on `#F0EDE5` |
| Light muted text | `#7A7873` | `#6D6B67` | 3.77:1 on `#F0EDE5` (3.91:1 on paper) | 4.55:1 on `#F0EDE5` |

Light coral `#B6342B` passes unchanged (5.11:1 worst case) and is kept.

## Restriction
The highest surface (`#262A30` dark, `#E6E2D8` light; avatars, chips, progress tracks, the selected tab) carries primary text only. Secondary and muted text fail there (4.29:1 dark muted, 4.14:1 light secondary) and the canvas never puts them there.

Both rules are asserted in `packages/core/test/theme/contrast_test.dart`.
