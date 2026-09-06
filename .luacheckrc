-- Globals taken from FMTK's generated Factorio library, by loading its stub
-- files in a sandbox and keeping whatever landed in the environment.
--   $Factorio 2.0.77   $Generator 2.0.14
-- Dropped from that set: util, sound_variations,
-- sound_variations_with_volume_variations and volume_multiplier, which are
-- core/lualib module locals the stubs leak rather than Factorio globals.
-- `util` in particular has to stay undeclared so that using it without
-- require("util") is still an error.

std = "lua52"

stds.factorio = {
    globals = {
        -- the only one a mod writes to
        "storage",
    },
    read_globals = {
        "commands", "data", "debug", "defines", "feature_flags", "game",
        "helpers", "localised_print", "log", "math", "mods", "package",
        "prototypes", "rcon", "remote", "rendering", "require", "script",
        "serpent", "settings", "table_size",
    },
}

exclude_files = { ".luarocks/**", "node_modules/**" }

files["control.lua"].std = "lua52+factorio"
files["settings.lua"].std = "lua52+factorio"
files["lib/*.lua"].std = "lua52+factorio"
files["test/spec/*.lua"] = {
    std = "lua52+factorio+busted",
    -- the stubs install the globals the mod only ever reads
    globals = { "defines", "game", "prototypes", "remote", "script", "storage" },
}
files["test/support/*.lua"] = {
    std = "lua52+factorio+busted",
    globals = { "defines", "game", "prototypes", "remote", "script", "storage" },
}

-- The integration tier runs inside the game, against factorio-test's own globals
stds.factorio_test = {
    read_globals = {
        "after_all", "after_each", "after_test", "after_ticks", "async", "describe",
        "done", "it", "on_tick", "test", "tags", "ticks_between_tests",
    },
}
files["test/ft/*.lua"] = {
    std = "lua52+factorio+factorio_test",
    -- a fixture drives the game rather than reading it: the pause, the cursor and the
    -- mod's own setting are all written from here
    globals = { "game", "settings" },
}
files["test/ft/aupc-tests/*.lua"].std = "lua52+factorio"
