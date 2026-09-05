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

exclude_files = { ".luarocks/**" }

files["control.lua"].std = "lua52+factorio"
files["lib/*.lua"].std = "lua52+factorio"
files["test/**/*.lua"] = {
    std = "lua52+factorio+busted",
    -- the stubs install the globals the mod only ever reads
    globals = { "defines", "game", "prototypes", "remote", "script", "storage" },
}
