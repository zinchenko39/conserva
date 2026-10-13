# Contributing

Conserva is a Swift package with two targets: `ConservaCore` (the shelf model, storage, sorting of
what comes in, the jar's geometry; no AppKit, covered by tests) and `Conserva` (AppKit + SpriteKit).
Only the Command Line Tools are needed, not Xcode.

```sh
swift build                                  # debug build
swift test                                   # core tests (Swift Testing)
scripts/build-app.sh                         # universal release → build/Conserva.app
ARCHS=arm64 scripts/build-app.sh debug       # one architecture, for development
open build/Conserva.app
```

Everything in the repository is in English: code, comments, test fixtures, log messages. The only
non-English text is in `Sources/Conserva/Resources/*.lproj`.

## Checking the app from a terminal

Nothing on the shelf can be clicked from a terminal, so the app is checked by a scripted test
instance with a shelf of its own. Only a **debug** build answers to these variables; a release build
ignores them. Every action is listed at the top of `Sources/Conserva/Debug.swift`.

```sh
CONSERVA_HOME=/tmp/conserva-dev CONSERVA_DEBUG_SNAPSHOT=/tmp/conserva-shots \
CONSERVA_DEBUG_SEQ="reveal; wait 1.5; pull 0; wait 3.5; snap pulled; state; quit" \
build/Conserva.app/Contents/MacOS/Conserva
```

- `snap` writes the shelf over a light and a dark desktop, and the shelf alone as `<name>-alpha.png`.
- `state` writes `debug-state.json` into `CONSERVA_HOME`: per jar, its position and angle, things
  loose, waiting and out, the lid, whether the mouth is sealed, overlapping pairs, things standing on end.
- `probe <jar> <s>` watches a jar's contents frame by frame and logs kicks, bounces and when they last
  moved. Use it before and after any change to the content physics.
- `pointer`, `mousedown`, `extdrag`, `clickjar`, `keyv` and `clip` stand in for the real pointer, the
  mouse button, a drag from another app, a click, ⌘V / ⌃V and the clipboard.
- `CONSERVA_TRASH` names a folder that stands in for the Trash.

The test instance shows on the real screen while it runs and does not hide by itself. Quote what it
printed in a pull request; a build that compiles is not evidence that a change works.

## How it is built

**Jars.** Each jar is a rigid body under gravity (`JarRig.body`): it falls when let go, stands on the
screen's bottom edge or on another jar, and jars push each other. A held jar is pulled by a spring
with a force limit plus lift against gravity (`ShelfScene.drive`), never given a set speed. Grabbing
the neck (above `JarGeometry.tiltGripY`) tilts the jar; grabbing lower carries it. A free jar gets a
righting moment while tilted less than about 60°; past that it stays lying down until picked up. Where
a jar comes to rest is saved as a fraction of the screen (`Jar.place`).

**Contents.** Each jar's contents are simulated in a private box in the jar's own frame
(`JarRig.lab`), far from the visible scene; the sprites copy the proxies' poses. The jar's movement
reaches them as a change of effective gravity: gravity minus the jar's acceleration, turned into the
jar's frame, applied to each body every frame. The things are paper and card: no bounce, air drag,
chamfered corners, no continuous collision detection between them. While a jar is poured the things
collide only with the glass. At most `JarGeometry.maxLoose` things are simulated per jar; the rest
wait underneath, newest on top.

**Lid.** A swing top that never leaves the jar (`JarRig.Lid`). For the contents it is an edge across
the mouth, removed while the lever is released (`JarRig.sealed`). A thing whose centre rises past
`JarGeometry.escapeY` with the mouth unsealed has left the jar and lands in a row along the floor
(`ShelfScene.placeOut`).

**Geometry.** `JarGeometry` and the artwork in `JarArt` share one 300 × 430 design box drawn y-down;
`JarGeometry.local` converts to the y-up frame centred on the jar; the on-screen scale is
`ShelfScene.jarScale`. Each kind of thing has a size of its own (`JarGeometry.size(of:)`), checked by
the tests against the neck: change a size only with the tests.

**Who does what.** `ShelfModel` is the only thing that changes the shelf and saves it, and only through
the rules in `ShelfEditing`. `ShelfScene` owns all motion. `ShelfView` turns mouse, keys and drag and
drop into scene calls. `AppDelegate` shows and hides the shelf and owns the menu and the card.
`JarArt` draws every texture; colours come only from `Theme`.

## Rules for changes

- All text goes through `L("key")`; every key must exist in each of
  `Sources/Conserva/Resources/{en,ru,es}.lproj/Localizable.strings`.
- No code from other projects. The only third-party material is the Caveat font
  (`THIRD_PARTY_NOTICES.md`).
- Comment only where the code cannot say it: why this approach, a constraint not visible locally, a
  workaround and its reason.
- Data: an unreadable `shelf.json` is moved aside, never overwritten; a shelf saved by a newer
  Conserva is refused; stored files no item points to are moved to the Trash on launch. Keep it so.
