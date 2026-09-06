# The integration tier

41 fixtures that drive a real Factorio and check what it actually did, on top of
[factorio-test](https://mods.factorio.com/mod/factorio-test). Headless, no display, no
synthetic input, about five seconds end to end.

```bash
npm install                          # once: fetches factorio-test-cli
test/ft/run.sh                       # the whole suite
test/ft/run.sh -v                    # with the game's own log lines
test/ft/run.sh "quality"             # only tests matching a Lua pattern
test/ft/run.sh -g --no-auto-start    # open a window and pick tests by hand
test/ft/run.sh -g --game-speed 1 "ice gap"   # watch one test at normal speed
test/ft/run.sh -b                    # stop at the first failure
```

`AUPC_FACTORIO` points at the game binary, `AUPC_FT_DATA` at the throwaway data
directory the run happens in (`~/.cache/aupc-factorio-test` by default, deliberately
outside the repo — the runner symlinks the mod under test into that directory's mods
folder, so a data directory inside the repo would make the repo contain itself). Two
runs cannot share one data directory: the runner writes mod settings there to tell the
game what to do, so a second run started alongside the first breaks both. Give the
second one its own `AUPC_FT_DATA`.

Graphics mode wants a real GPU: the suite runs at `game_speed` 100, and software
rendering on a virtual display grinds through that at a few ticks a second.

The unit tier is separate and unchanged: `test/run.sh` runs the busted specs in
`test/spec` against the stubs in `test/support`, in milliseconds, with no game at all.
Pure decisions belong there. Anything about what the engine really does belongs here.

## How it fits together

- `control.lua` registers the fixtures with factorio-test, guarded on both
  `factorio-test` and `aupc-tests` being loaded. `aupc-tests` is never published, so the
  hook can never fire on a player's machine — which matters, because `info.json` keeps
  `test/` out of the package.
- Registering from *this* mod rather than from `aupc-tests` is what lets the quality
  fixtures write `aupc-substitute-pipe-quality`: a mod may only change its own settings,
  and these tests are the owning mod. Both values of that setting are covered in one
  run, where the old harness needed the suite run twice with a hand-written
  `mod-settings.dat`.
- `test/ft/aupc-tests` is a data-only mod holding prototypes no vanilla install has:
  Pipe Plus's junction undergrounds (issue #15), Warptorio's warp foundation, ground
  whose cover tile the engine refuses to place. It is not on the mod portal, so
  `run.sh` symlinks it into the runner's mods directory before every run; the CLI then
  leaves it alone rather than trying to download it.
- `test/ft/world.lua` holds the shared ground: `world.patch()` claims a fresh 12x12
  patch of Aquilo, clears whatever the map generator put there, resets the player to a
  god controller with an empty cursor and the mod's setting at its default, and hands
  back the patch with `paint`, `stock`, `build`, `build_ghost` and the inspection
  helpers on it. factorio-test does not reset the world between tests, so a test that
  wants clean ground asks for a patch.
- Aquilo rather than a lab-tile surface because the meltable-ground fixtures need real
  ice, and because a tile laid there freezes on contact — `world.same_tile` accepts
  either name.

## Adding a fixture

```lua
local world = require("test.ft.world")

test("a real pair one apart gets a real pipe", function()
    local patch = world.patch()
    patch.paint("refined-concrete")
    patch.stock{ [world.PIPE] = 10, [world.UNDERGROUND] = 10 }
    patch.build(world.UNDERGROUND, patch.a, defines.direction.south)
    patch.build(world.UNDERGROUND, patch.b, defines.direction.north)
    assert(patch.pipe_at() ~= nil, "no pipe was placed in the gap")
end)
```

New files go in the list at the end of `control.lua`. `print` output is captured and
shown with a failing test, so it is the place for the context a failure needs.

Fixtures run straight through rather than one action per tick: the mod acts
synchronously in `on_built_entity`, so a tick boundary between placements changes
nothing. `async(timeout)` with `after_ticks` is there for anything that does need one.

## What this tier does not cover

Two things the old scenario harness could do did not survive the move. Both are gaps in
factorio-test rather than in the fixtures, and both are worth a PR upstream.

**Applying an undo.** No runtime API performs one — `LuaUndoRedoStack` reads, tags and
removes entries but cannot apply one — and the headless runner is `factorio --benchmark`,
which has no window to send a keypress to. `test/ft/undo.lua` therefore checks that what
the mod placed joined the player's own undo item, and that a gap the mod declines leaves
no entry behind. What is no longer checked is the engine's half: that ctrl+z then really
does queue the cover tile for deconstruction (the `deconstructible-tile-proxy` and
`to_be_deconstructed()` assertions), and that an editor-mode undo reverts the tile on the
spot. *Upstream:* a way to deliver input to a test — either synthetic key events in
graphics mode, or a hook for the engine's undo action.

**The narrated walkthrough.** The old `walkthrough.sh` stepped through fixtures in a live
window with a Next / Skip fixture / Run the rest / Stop panel, and stopped before each
step to say what was about to happen. factorio-test's in-game GUI can run a single test
and let you watch it, which covers some of that, but there is no per-step pause and no
narration. *Upstream:* a step/breakpoint mode — a test could yield with a caption and the
GUI would show it with a continue button, which is roughly what `async`/`done` already
does internally.

Two smaller differences, neither worth a PR:

- A failing fixture used to collect every failed check and report them together; a test
  now stops at the first failed `assert`. Fixtures print their context first, so a
  failure still says what the world looked like.
- The old harness could run the packaged zip instead of the working tree
  (`AUPC_FROM_ZIP`) to prove packaging left nothing out. The runner takes a directory,
  and the package deliberately leaves `test/` out, so the same check is now two steps:

  ```bash
  npx fmtk package --outdir /tmp/aupc && (cd /tmp/aupc && unzip -q *.zip)
  cp -r test /tmp/aupc/automatic-underground-pipe-connectors_*/
  AUPC_FT_DATA=/tmp/aupc-data test/ft/run.sh --mod-path /tmp/aupc/automatic-underground-pipe-connectors_*
  ```
