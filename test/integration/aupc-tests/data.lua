--- A keybinding whose only job is to prove that synthetic input reaches the game.
--- Without it, a silent ctrl+z is indistinguishable from an undo that did nothing.
data:extend{
    {
        type = "custom-input",
        name = "aupc-tests-probe",
        key_sequence = "CONTROL + SHIFT + F9",
    },
}

--- Ordinary buildable ground that nominates a cover tile, which is the shape of the
--- modded planet tiles behind the "does nothing on Moshine dry swamp" report.
--- `default_cover_tile` records which tile to pave *with*, not that paving is needed,
--- and foundation is not even legal here: its tile_condition lists water, lava, oil
--- ocean and the like. Nothing in vanilla sets the field on buildable ground, so the
--- case only exists once a fixture builds it.
--- Sand's looks are borrowed by reference rather than copied; nothing here mutates
--- them, and table.deepcopy only exists in the data stage, not at runtime.
local sand = data.raw.tile["sand-1"]
data:extend{
    {
        type = "tile",
        name = "aupc-tests-covered-ground",
        -- ground_tile alone: a pipe collides with none of this, so it is buildable
        collision_mask = { layers = { ground_tile = true } },
        default_cover_tile = "foundation",
        layer = 250,
        subgroup = sand.subgroup,
        order = "z[aupc-tests]-a[covered-ground]",
        variants = sand.variants,
        transitions = sand.transitions,
        transitions_between_transitions = sand.transitions_between_transitions,
        walking_sound = sand.walking_sound,
        absorptions_per_second = sand.absorptions_per_second,
        map_color = { 138, 103, 58 },
    },
}

--- Warptorio's warp foundation, in the shape that crashed the mod: an ordinary
--- buildable foundation tile whose default_cover_tile names empty-space, which no
--- item places and which the engine refuses to make a tile ghost of at all --
--- "empty-space can not be part a tile ghost". Warptorio sets this on every tile it
--- makes destructible (its data.lua set_destructable), apparently to say what is left
--- behind when one is destroyed rather than what to pave it with.
local warp = {
    type = "tile",
    name = "aupc-tests-warp-foundation",
    collision_mask = { layers = { ground_tile = true } },
    default_cover_tile = "empty-space",
    is_foundation = true,
    max_health = 50,
    layer = 251,
    subgroup = sand.subgroup,
    order = "z[aupc-tests]-b[warp-foundation]",
    variants = sand.variants,
    transitions = sand.transitions,
    transitions_between_transitions = sand.transitions_between_transitions,
    walking_sound = sand.walking_sound,
    absorptions_per_second = sand.absorptions_per_second,
    map_color = { 90, 90, 140 },
}

--- The same unplaceable cover tile, but on ground a pipe cannot sit on, so the mod
--- has to go looking for a cover instead of skipping the question. Nothing in vanilla
--- combines the two, and that combination is the one that reaches the crash.
local unghostable = {
    type = "tile",
    name = "aupc-tests-unghostable-gap",
    -- ammoniacal ocean's shape: a pipe collides with water_tile
    collision_mask = { layers = { water_tile = true, item = true, player = true,
                                  doodad = true, floor = true } },
    default_cover_tile = "empty-space",
    layer = 252,
    subgroup = sand.subgroup,
    order = "z[aupc-tests]-c[unghostable]",
    variants = sand.variants,
    transitions = sand.transitions,
    transitions_between_transitions = sand.transitions_between_transitions,
    walking_sound = sand.walking_sound,
    absorptions_per_second = sand.absorptions_per_second,
    map_color = { 140, 90, 90 },
}

data:extend{ warp, unghostable }
