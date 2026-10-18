# Creating characters, skins and animations

What you can change today, from easiest to hardest:

| I want to… | How | Code needed |
|---|---|---|
| Put a hat, glasses or a crown on Clawd | a skin file (`.txt`) | none |
| Recolour Clawd (body and eyes) | the same skin file | none |
| Make Clawd do a new move | a frame list in `Clawd.seqs` | a few lines of Swift |
| Add something to the sky or a new particle | pixel art with `rows([...])` in `Scene.swift` | Swift |
| A different creature (another silhouette) | not possible with a skin yet, see [Other creatures](#other-creatures) | Swift |

Everything is pixel art on one grid, so the same ideas apply to all of them.

## 1. Clawd's grid

Clawd is 18 pixels wide and 12 tall (the last two rows are empty: his feet end at row 9, the rest is "ground").
Pixels are drawn a little taller than wide (2.0 × 2.2 units), like a terminal character cell.
`#` is the body, `o` is the eyes (default, open):

```
    012345678901234567
  0 ...#############..
  1 ...#############..
  2 ...##o#######o##..
  3 ...##o#######o##..
  4 .#################      <- arms: row 4 and 5 reach out to x=1 and x=17
  5 .#################
  6 ...#############..
  7 ...#############..
  8 ...#.#.......#.#..      <- legs
  9 ...#.#.......#.#..
 10 ..................
 11 ..................
```

The head is x 3..15, y 0..7. This is what you draw on top of. Coordinates are `x` (column, 0 = left) and `y` (row, 0 = Clawd's top row).
Rows above his head are negative: `y = -1` is the row right over his head.

Inside the code the shape is built from the same block characters Claude Code draws in the terminal (`▛ ▜ ▐ ▌ ▝ ▘ ▖ ▗ █`),
each one a cell of 2×4 pixels. That is why the arms and feet look exactly like the terminal.

## 2. Skins (no code)

A skin is a text file. The file name (lowercase, without `.txt`) is its id.

```
---
name: Headphones
top: -2
k: #374151
g: #9CA3AF
---
....kkkkkkkkkkk...
...k...........k..
.ggk...........kgg
.gg.............gg
.gg.............gg
.gg.............gg
```

(That one is `docs/examples/headphones.txt`.)

**Header**, between the two `---` lines, one `key: value` per line:

| key | meaning |
|---|---|
| `name` | display name (settings window, later) |
| `body` | Clawd's colour, `#RRGGBB` (default `#D77757`). Optional |
| `eyes` | colour of the eyes and face, `#RRGGBB` (default `#141416`). Optional |
| `top` | the row number (counted from Clawd's top row) where the first art row goes. Optional. Without it the art sits right on his head: the last art row is `y = -1`, so a 4-row hat covers `y = -4..-1` |
| any single character | a colour for that character in the art. `k: #374151` means every `k` in the art is that grey |

**Art**, after the second `---`: rows of exactly 18 characters. `.` is empty. A character with no colour defined is ignored, so you can leave notes.

How accessories behave (so you are not surprised):

- Pixels above his head (`y < 0`) show while his head is inside the frame. When he crouches into the sand or ducks (`peekaboo`), a hat goes with the head.
- Pixels on the body (`y >= 0`) are drawn like the body: they move with him and are clipped like him.
- While he turns around (`turn`, `coin-hop`) only what is above the head stays.
- On his back (limit at 100%) he loses every accessory.
- Layers are drawn in the order of the colour letters (alphabetical), over the body. Later letters win where they overlap.

### Try it

```
# 1. put the file in your skins folder (the same name as a built-in one replaces it)
mkdir -p ~/Library/Application\ Support/ClaudyUsage/skins
cp my-skin.txt ~/Library/Application\ Support/ClaudyUsage/skins/

# 2. preview in 8 situations (day, rain, sleeping, dead, ...) without installing anything
S=$HOME/Library/Caches/claudy-build
CLAUDY_SKIN=my-skin $S/debug/ClaudyUsage --scenes /some/folder      # writes /some/folder/sheet.png

# 3. use it: pick its card in Settings → Look (the panel picks it up the next time it opens)
# or: Settings → Look → Clawd's skin (cards with a live preview; "Your own" opens the folder)
defaults write dev.julio.claudy-usage skin my-skin
defaults delete dev.julio.claudy-usage skin                         # back to classic
```

To preview a skin that is still in your project folder, add `CLAUDY_SKINS_DIR=$PWD/docs/examples`.
Built-in skins live in `Sources/ClaudyUsage/skins` and ship inside the app (`scripts/bundle.sh` copies them).

### Tips for good skins

- Draw on the 18×N grid on paper or in a text editor with a monospace font; line up columns with the map in section 1.
- Keep accessories to the head and the face. Anything over the arms and legs (rows 4-9) moves with the walking frames and can look noisy.
- Face accessories (glasses): put the eyes in your skin's `eyes:` colour logic. The eyes themselves change per mood (`open`, `wide`, `x`, `happy`...), so glasses should sit around them, not on top of them. See `shades.txt` (`top: 1`).
- Dark colours vanish on the dark panel. The built-in hats use mid-tone colours with a lighter accent.
- Share a skin by sending the `.txt`; nothing else is needed.

## 3. Animations (a few lines of Swift)

One-shot animations are lists of frames in `Clawd.seqs` (`Sources/ClaudyCore/Clawd.swift`). A frame lasts 60 ms.
`F(pose, count, off:, x:, poof:, shadow:)` makes `count` identical frames.

**Poses**: a name (`default`, `arms-up`, `look-left`, `look-right`) or `"eyes/arms/feet"`:

| part | values |
|---|---|
| eyes | `open left right closed blink wink happy focus wide x yawn gasp` |
| arms | `down up right left` |
| feet | `both left right` |

Other frame options:

| option | meaning |
|---|---|
| `off` | rows lowered: `1` crouched (legs hidden), `2`-`3` mostly hidden, negative = above the frame (he drops in) |
| `x` | shift in cells (2 pixels each), negative = left. Anything outside the 9-cell frame is clipped, so `x: -9` is "off the left edge". The frame is the clip: he slides in from nothing |
| `poof` | `dot` or `wave`: dust at his sides while crouched |
| `shadow` | `wide` or `narrow`: the shadow under a hopping coin |
| `"face:<name>"` as pose | a turn-around frame: `right-12 right-30 right-55 right-75 edge back-105 back-125 back-150 back left-75 left-55 left-30 left-12` |

Example: a little dance. Add inside the dictionary in `Clawd.seqs`:

```swift
"dance": F("left/down/left", 2) + F("right/down/right", 2) + F("left/down/left", 2) + F("right/down/right", 2) +
         F("arms-up", 2, off: 1) + F("arms-up", 3) + bo,
```

and add `"dance"` to `Clawd.seqNames`. That is all: it becomes one of the moves a click can pick, because
`clickActs` is every sequence that starts in place (first frame `x == 0`) except `celebrate`.
Run `swift test`: a test checks that `seqs` and `seqNames` agree.

Moves that need logic instead of a frame list (wave, stretch, yawn, stumble, burrow, unburrow, stir, soul) are in
`Mascot.stepAct`. They set `look`, `lift` (pixels off the ground), `dig` and so on per frame, and have a length in
`Clawd.customLen`. Copy one of them if you need a move that depends on the frame number.

Moods (what he does without a click) and the health tiers live in `Mascot.step` and `Health.tiers`.
To see a move or mood while you tune it: right-click the sky in the open panel. The developer menu forces a mood, plays any move, sets the hearts, the time of day and the weather; **Auto** goes back to live data.

## 4. Sky and particles

The sun, moon, clouds, hearts and sparkles are pixel art in code: rows of `#` and `.` turned into rectangles by `rows([...])`
(bottom of `Scene.swift`), drawn at a pixel size you choose:

```swift
private let sunRects = rows(["..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###.."])
```

To add a new thing (a star shape, a bird, a kite on windy days) draw it like that, give it a position in `Sky.step`
(`Sources/ClaudyCore/Sky.swift`, produces the numbers) and draw it in `SceneCanvas` (`Scene.swift`).
The sky logic never draws; the view never decides. Keep it that way so the logic stays testable.

## Other creatures

A skin only recolours Clawd and adds pixels on top; it cannot change his silhouette, his arms or his walk.
A different character (a cat, a ghost) needs its own pixel map: the glyph tables `arms`, `feet`, `facing`, the eye positions and the
body rows in `Clawd.pixels`. Today these are Clawd's.

If you want this, the clean way is a small change: let a skin file carry its own body map (`body-art` block, with `#` for the body and `o` for the eyes,
like the map in section 1) and fall back to the built-in Clawd when it is missing. Walking, moods and animations would keep working because they only
choose poses; a custom body would use one drawing for all poses at first, and extra drawings (`legs-left`, `legs-right`) later for the walk.
It is on the backlog (`docs/STATUS.md`). Ask for it when you have an idea for the character.

## Credits and licence

The built-in skins, Clawd's glyph tables and the animation sequences come from
[Enhed/clawd-usage-winwidget](https://github.com/Enhed/clawd-usage-winwidget) (MIT). Clawd is Anthropic's character; this is a fan project.
