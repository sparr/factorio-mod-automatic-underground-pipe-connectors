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

--- Pipe Plus's junction undergrounds, copied from its own prototypes (issue #15): the
--- T and X from pipe.lua, the elbow from extra-pipes.lua. All three keep the vanilla
--- underground connection facing south. The T opens east and west above ground and
--- nowhere else, the X adds north, and the elbow opens east alone.
---
--- North is the whole problem. A vanilla underground opens on the side it faces, so
--- "the tile ahead" and "the tile it opens onto" are the same tile, and the mod has
--- always taken the first as a stand-in for the second. For the T they are different
--- tiles: ahead is a side it does not open onto at all. The X still opens there, so it
--- must keep connecting -- that is what stops the fix from being "ignore junctions".
local util = require("util")

local function junction(name, connections)
    local entity = util.table.deepcopy(data.raw["pipe-to-ground"]["pipe-to-ground"])
    entity.name = name
    entity.minable = { mining_time = 0.1, result = name }
    entity.next_upgrade = nil
    entity.fast_replaceable_group = nil
    entity.fluid_box.pipe_connections = connections
    return entity,
        {
            type = "item",
            name = name,
            icon = "__base__/graphics/icons/pipe-to-ground.png",
            subgroup = "energy-pipe-distribution",
            order = "z[aupc-tests]-" .. name,
            place_result = name,
            stack_size = 50,
        },
        -- the mod pairs an underground with a pipe by reading recipes, so it needs one
        {
            type = "recipe",
            name = name,
            enabled = true,
            ingredients = { { type = "item", name = "pipe", amount = 5 } },
            results = { { type = "item", name = name, amount = 2 } },
        }
end

local UNDERGROUND_SOUTH = {
    connection_type = "underground",
    direction = defines.direction.south,
    position = { 0, 0 },
    max_underground_distance = 10,
}

data:extend{ junction("aupc-tests-t-junction", {
    { direction = defines.direction.east, position = { 0, 0 } },
    UNDERGROUND_SOUTH,
    { direction = defines.direction.west, position = { 0, 0 } },
}) }

data:extend{ junction("aupc-tests-x-junction", {
    { direction = defines.direction.north, position = { 0, 0 } },
    UNDERGROUND_SOUTH,
    { direction = defines.direction.east, position = { 0, 0 } },
    { direction = defines.direction.west, position = { 0, 0 } },
}) }

--- And its elbow, from extra-pipes.lua: the four "rotatable" variants keep the vanilla
--- underground connection and point the single above-ground one at a fixed direction.
--- The sharpest of the three shapes -- one opening, and never the one straight ahead,
--- so an elbow can only ever be joined along an arm.
data:extend{ junction("aupc-tests-elbow", {
    { direction = defines.direction.east, position = { 0, 0 } },
    UNDERGROUND_SOUTH,
}) }

--- The fourth rotatable variant is a u-turn: the above-ground connection points the
--- same way as the buried one. Both ends of it face the same side, so the tile it
--- opens onto is also the tile its underground run sets off through -- which is the
--- one place the "normal" filter has to do real work, or the same tile would be
--- reported twice for two quite different reasons.
data:extend{ junction("aupc-tests-u-turn", {
    { direction = defines.direction.south, position = { 0, 0 } },
    UNDERGROUND_SOUTH,
}) }
