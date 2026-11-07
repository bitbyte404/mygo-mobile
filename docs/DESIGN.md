# Design

MyGo 音乐 mobile reproduces the look and motion of the desktop **MyGo Music** app
([egoist/mygo-music](https://github.com/egoist/mygo-music), read at tag/commit `0.1.18`,
`origin/main` 93bf5a6), adapted to touch and small screens. The desktop app is native Go
(the MyGo UI framework, no WebView), so its "styles" are Go code; the values below were read
from that code (and, for the two CSS easing curves, from the project website's stylesheet).
The tokens live in `lib/ui/theme/tokens.dart`; the components in `lib/ui/components/`.

No stock Material chrome is used: no AppBar, NavigationBar, FAB, ListTile, Card, SnackBar,
ripples or Material 3 colors. `MaterialApp` and a transparent `Material` are kept only as
plumbing (Navigator, text fields, localizations); `NoSplash` is set everywhere.

## Colors (`MgPalette`, from `internal/app/ui_kit.go` `paletteFor`)

| token | dark | light | use |
|---|---|---|---|
| bg | `#141416` | `#ffffff` | content background |
| sidebar | `#1c1c1f` | `#f4f4f6` | sidebar / rail |
| text | `#f5f5f7` | `#1d1d1f` | |
| muted | rgba(235,235,245,.56) | rgba(60,60,67,.62) | secondary text, icons |
| faint | rgba(235,235,245,.30) | rgba(60,60,67,.32) | numbers, times, placeholders |
| hairline | white .07 | black .07 | separators |
| hover | white .06 | black .04 | placeholder fill, chips |
| press | white .10 | black .08 | pressed / selected fill |
| accent | `oklch(0.66 0.2 22)` = `#f45058` | `oklch(0.6 0.21 24)` = `#e2333c` | MyGo red |
| cardShade | black .45 | black .16 | cover shadows |
| popover / edge | `#2b2b2e` / white .14 | `#f6f6f6` / black .12 | sheets, dialogs, mini player (`ui_player.go popoverColors`) |

Accent pressed: mixed 15% toward white (dark) / 20% toward black (light), as `useAccent`.
Liked Songs' cover: `oklch(0.72 0.17 10)` → `oklch(0.58 0.22 350)` at 135° (`ui_pages.go likedPage`).
Lossless badge gold `#f5d58a` (`ui_nowplaying.go qualityBadge`). Now Playing base `#0b0b0d`.
The app follows the system light/dark setting (or the one chosen in Settings).

## Type (sizes in dp; weights; tracking)

From `ui_pages.go`, `ui_player.go`, `ui_nowplaying.go`: page heading 30/700 −0.6 (26 on a phone)
with a 12/600 +0.4 line above it; section 19/700 −0.3; playlist/album title 30/800 −0.6 (24 on a
phone); track row 14/500 (15 on a phone) over 12.5 artists; card name 13/500 ×1.35 over 12;
sidebar entry 13.5/500; player bar 13.5/600 over 12, times 10.5 tabular; pills 14/600; Now
Playing title 22/700 −0.3, artists 15, times 11 tabular, tabs 13/600; lyrics 30/800 ×1.25 −0.4
(24 on a phone), translations 17/600 at 70%. Fonts are the platform's (Roboto + Noto CJK on Android).

## Shape and spacing

Radii: card 10, header cover 14, row 10, row cover 6, queue row / lyric line 12, bar cover 8,
sidebar entry 8, popover 12, Now Playing cover 16, pills 999. Sidebar 232, player bar 84, track
row 54 (60 on a phone), header cover 212 (≈ half the width on a phone), grid gaps 20/28, card grid
columns of ≥ 156 (`ui_browse.go browseRows`). Shadows: card `0 2 8 −2 cardShade`; header cover
`0 18 40 −10`; Now Playing cover `0 30 60 −12 black .55`.

## Icons (`lib/ui/theme/icons.dart`)

MyGo's own icon set (`internal/app/icons.go`) copied verbatim as SVG and drawn by a small SVG
renderer (`path_parsing`): 24-grid, transport controls filled, the rest a 1.75 stroke with round
caps — Lucide-style. A few extra Lucide icons (history, shield, QR, archive, …) in the same style.

## Motion (`MgMotion`)

| what | value | source |
|---|---|---|
| hover/press fill | 120 ms | `ui_kit.go roundButton`, `navItem` |
| track row fill | 100 ms | `trackRow` |
| press scale | 0.88 (round buttons), 0.96 (pills), on a short spring | `roundButton`, `pillButton` (`ui.Snappy`) |
| artwork fade-in over placeholder | 320 ms | `artFade` |
| play ↔ pause glyph | spring 340 ms, bounce 0.3; scale 0.4→1 + fade | `playPause` |
| Now Playing open/close | spring 440 ms, no bounce, growing out of the player's cover; pull-to-close at 20% of the height or a 700 dp/s fling, scale 1−0.12·pull, corner 28·min(shift/120,1) | `npSpring`, `nowPlayingLayer`, `npCard` |
| Now Playing contents | rise one after another: `smoothstep(0.3+0.07n, 0.7+0.07n, t)`, 24 dp lift | `npRise` |
| backdrop | tint gradient (HSV v .35 → .24), cover at 10%, foot shade; new song fades in 700 ms ease-out-cubic | `backdrop.go` |
| cover breathing | 0.88 while paused, spring 600 ms bounce 0.25 | `ui_cover.go`, `npBreathe` |
| lyric line | scale 0.94→1 spring 600 ms bounce 0.1 (left anchored), opacity .28→1 over 380 ms, words 38%→100% as sung | `timedLines` |
| lyric scroll | critically damped spring ω = 10 to 30% down the pane; dragging stops it | `lyricGlide` |
| segmented capsule | spring 280 ms, bounce 0.08 | `segmented` |
| top scroll edge | 180 ms | `edgeShown` |
| page push (mobile) | 360 ms, `cubic-bezier(0.22, 1, 0.36, 1)` (website `--ease`), fade + 18% slide | website `styles.css` |
| hero covers | card → page header (`MaterialRectArcTween`) | mobile |

MyGo's `ui.Snappy` spring is defined in the MyGo framework, not in this repository, so its exact
parameters are unknown; a 240 ms / 0.15-bounce spring stands in for it.

## Mobile adaptations

- **Width classes** (`widthClassOf`): compact < 600 dp: tab bar (Home, Search, 我的) + a floating
  mini player card; Home shows the plugin's other pages as chips and the library tab lists them
  (the desktop sidebar's job). Medium 600–840: an icon rail + the desktop player bar. Expanded ≥ 840
  (tablets, foldables open, landscape): the desktop layout — 232 dp sidebar (source switcher,
  search, the plugin's navigation, 我的歌单, account / plugins / settings), content with card grids,
  the 84 dp player bar, Now Playing with cover and lyrics side by side.
- **Now Playing** on a phone: a pane switcher (歌词 / 播放队列 / 评论) at the top right; the cover pane
  by default (tap the cover for lyrics); with a pane open the cover shrinks into the title row.
- **Edge to edge**: everything draws under the status and navigation bars (transparent, no contrast
  scrim, cutout `shortEdges`); bars' icons are dark on the light theme, light on the dark theme and
  over Now Playing's artwork (chosen from the backdrop's luminance). Content is padded by
  `MediaQuery.viewPadding` plus the app's own bars, so the tab bar and mini player sit above the
  gesture bar or the 3-button bar, and landscape side insets are respected.
- **Performance**: nothing is blurred per frame. The backdrop is a gradient plus the cover decoded at
  48 px, inside a RepaintBoundary; the artwork tint is computed once per cover from a 24 px decode
  and cached (`ArtTint`); Now Playing's frames only move a clip, a transform and opacities.
- Dancing "now playing" bars: the phone has no audio levels, so they move on sums of sines while
  playing (desktop: real spectrum levels).
