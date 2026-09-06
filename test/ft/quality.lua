--- Quality: what the connector is made of, and whose stack pays for it.
---
--- The substitution setting used to need a whole second run of the suite, because a
--- mod may not write another mod's setting and the fixtures lived in a scenario. These
--- tests are registered by the mod that owns the setting, so they can simply set it.
local world = require("test.ft.world")

local PIPE, UNDERGROUND = world.PIPE, world.UNDERGROUND
local SOUTH, NORTH = defines.direction.south, defines.direction.north

describe("quality", function()
    test("uncommon undergrounds get an uncommon connector", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock({ [PIPE] = 10, [UNDERGROUND] = 10 }, "uncommon")
        assert.equals(10, patch.count(PIPE, "uncommon"),
            "setup: the uncommon pipes did not go in")

        patch.build(UNDERGROUND, patch.a, SOUTH, nil, "uncommon")
        assert.is_nil(patch.pipe_at(),
            "a pipe appeared before the second underground existed")
        patch.build(UNDERGROUND, patch.b, NORTH, nil, "uncommon")

        for label, position in pairs({ A = patch.a, B = patch.b }) do
            local built = patch.surface.find_entities_filtered{
                name = UNDERGROUND, position = position }[1]
            assert.is_not_nil(built, "setup: underground " .. label .. " was not built")
        end

        local pipe = patch.pipe_at()
        assert.is_not_nil(pipe, "no real pipe was placed in the gap")
        assert.is_nil(patch.ghost_at(), "a ghost was placed instead of a real pipe")
        assert.equals("uncommon", pipe.quality.name,
            "connector quality is " .. pipe.quality.name .. ", not uncommon")
        assert.equals(9, patch.count(PIPE, "uncommon"),
            "expected one uncommon pipe consumed, inventory holds " ..
            patch.count(PIPE, "uncommon"))
    end)

    --- Same again with nothing to pay with. The fallback ghost has to carry the quality
    --- the player placed, or reviving it later builds the wrong pipe.
    test("uncommon undergrounds with no pipes get an uncommon ghost", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock({ [UNDERGROUND] = 10 }, "uncommon")
        assert.is_true(patch.count(PIPE) == 0 and patch.count(PIPE, "uncommon") == 0,
            "setup: pipes in inventory would mask the fallback")

        patch.build(UNDERGROUND, patch.a, SOUTH, nil, "uncommon")
        patch.build(UNDERGROUND, patch.b, NORTH, nil, "uncommon")

        local ghost = patch.ghost_entity_at()
        assert.is_not_nil(ghost, "no ghost was placed in the gap")
        assert.equals(PIPE, ghost.ghost_name,
            "the ghost is " .. ghost.ghost_name .. ", not a pipe")
        assert.equals("uncommon", ghost.quality.name,
            "ghost quality is " .. ghost.quality.name .. ", not uncommon")
    end)
end)

--- Only the wrong quality on hand. Two candidates, so this also pins the choice when
--- substitution is allowed: rare is two levels from normal and three from legendary.
describe("substituting a quality the player did not ask for", function()
    local function build_rare_pair(patch)
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = { normal = 5, legendary = 5 }, [UNDERGROUND] = { rare = 10 } }
        assert.equals(0, patch.count(PIPE, "rare"),
            "setup: a rare pipe would make this prove nothing")
        patch.build(UNDERGROUND, patch.a, SOUTH, nil, "rare")
        patch.build(UNDERGROUND, patch.b, NORTH, nil, "rare")
    end

    test("spends the nearest quality when the setting allows it", function()
        local patch = world.patch()
        patch.substitute_quality(true)
        build_rare_pair(patch)

        local pipe = patch.pipe_at()
        assert.is_not_nil(pipe, "no real pipe was placed from the substitute stack")
        assert.equals("normal", pipe.quality.name,
            "connector is " .. pipe.quality.name .. ", not the nearest quality")
        assert.equals(4, patch.count(PIPE, "normal"),
            "expected one normal pipe spent, inventory holds " .. patch.count(PIPE, "normal"))
        assert.equals(5, patch.count(PIPE, "legendary"),
            "the legendary pipe was spent instead of the nearer normal one")
    end)

    test("falls back to a ghost of the right quality when the setting forbids it", function()
        local patch = world.patch()
        patch.substitute_quality(false)
        build_rare_pair(patch)

        assert.is_nil(patch.pipe_at(),
            "a pipe of the wrong quality was spent with the setting off")
        local ghost = patch.ghost_entity_at()
        assert.is_not_nil(ghost, "no ghost was placed in the gap")
        assert.equals("rare", ghost.quality.name,
            "ghost quality is " .. ghost.quality.name .. ", not rare")
        assert.is_true(patch.count(PIPE, "normal") == 5 and patch.count(PIPE, "legendary") == 5,
            "a pipe was spent with the setting off")
    end)

    --- The cover tile is bought under the same rule as the pipe.
    local function build_over_ice_with_uncommon_cover(patch)
        patch.paint("refined-concrete")
        patch.paint_at("ice-rough", patch.gap)
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10, ["refined-concrete"] = { uncommon = 10 } }
        assert.equals("ice-rough", patch.tile_at(),
            "setup: the gap is " .. patch.tile_at() .. ", not ice")
        assert.equals(0, patch.count("refined-concrete"),
            "setup: normal cover tiles would mask the rule")
        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)
    end

    test("covers a meltable gap with the wrong quality tile when the setting allows it", function()
        local patch = world.patch()
        patch.substitute_quality(true)
        build_over_ice_with_uncommon_cover(patch)

        assert.is_true(world.same_tile(patch.tile_at(), "refined-concrete"),
            "the meltable tile was not covered, it is still " .. patch.tile_at())
        assert.is_not_nil(patch.pipe_at(), "no pipe was placed on the covered ground")
        assert.is_nil(patch.ghost_at(), "a ghost was placed where a real pipe should fit")
        assert.equals(9, patch.count("refined-concrete", "uncommon"),
            "expected one uncommon cover tile spent, inventory holds " ..
            patch.count("refined-concrete", "uncommon"))
    end)

    test("leaves a meltable gap uncovered when the setting forbids it", function()
        local patch = world.patch()
        patch.substitute_quality(false)
        build_over_ice_with_uncommon_cover(patch)

        assert.equals("ice-rough", patch.tile_at(),
            "the ground was covered with a tile the player did not agree to spend")
        assert.is_nil(patch.pipe_at(), "a real pipe went down on uncovered meltable ground")
        assert.equals(PIPE, patch.ghost_at(), "no pipe ghost was placed in the gap")
        assert.equals(10, patch.count("refined-concrete", "uncommon"),
            "an uncommon cover tile was spent with the setting off")
    end)
end)
