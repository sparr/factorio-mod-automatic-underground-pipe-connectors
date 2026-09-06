--- Ground a pipe cannot sit on, and what the mod lays down to make it fit.
local world = require("test.ft.world")

local PIPE, UNDERGROUND = world.PIPE, world.UNDERGROUND
local SOUTH, NORTH = defines.direction.south, defines.direction.north

describe("a meltable gap", function()
    --- The gap is meltable, the player is carrying something that can cover it
    test("gets a real cover tile when the item is held", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.paint_at("ice-rough", patch.gap)
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10, ["refined-concrete"] = 10 }
        assert.equals("ice-rough", patch.tile_at(),
            "setup: the gap is " .. patch.tile_at() .. ", not ice")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        local override = patch.surface.get_default_cover_tile(patch.player.force, "ice-rough")
        print("get_default_cover_tile(ice-rough) = " .. tostring(override and override.name))
        print("gap tile: " .. patch.tile_at() ..
              ", at the gap: " .. table.concat(patch.occupants(patch.gap), "+"))

        assert.is_true(world.same_tile(patch.tile_at(), "refined-concrete"),
            "the meltable tile was not covered, it is still " .. patch.tile_at())
        assert.is_not_nil(patch.pipe_at(), "no pipe was placed on the covered ground")
        assert.is_nil(patch.ghost_at(), "a ghost was placed where a real pipe should fit")
        assert.equals(9, patch.count(PIPE),
            "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
        assert.equals(9, patch.count("refined-concrete"),
            "expected one cover tile consumed, inventory holds " ..
            patch.count("refined-concrete"))
    end)

    --- Same gap, nothing to pay for the cover with
    test("falls back to ghosts with no cover item", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.paint_at("ice-rough", patch.gap)
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        assert.equals("ice-rough", patch.tile_at(),
            "setup: the gap is " .. patch.tile_at() .. ", not ice")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert.equals("ice-rough", patch.tile_at(),
            "the ground was changed without paying for it")
        assert.is_nil(patch.pipe_at(),
            "a real pipe was placed on uncovered meltable ground")
        assert.equals(PIPE, patch.ghost_at(),
            "expected a pipe ghost, found " .. tostring(patch.ghost_at()))
        local covers = patch.tile_ghosts_at()
        assert.equals(1, #covers, "expected one cover tile ghost, found " .. #covers)
        assert.is_true(world.same_tile(covers[1], "refined-concrete"),
            "expected the foundation the undergrounds stand on, found " .. tostring(covers[1]))
        assert.equals(10, patch.count(PIPE), "a pipe was consumed for a ghost")
    end)
end)

--- Ammoniacal ocean needs an ice platform to exist at all and then something
--- non-meltable on top of that, so the gap wants two stacked tile ghosts
describe("an ammoniacal ocean gap between ice platforms", function()
    test("gets a pipe ghost over two stacked cover ghosts", function()
        local patch = world.patch()
        -- Ocean only in the gap: that one tile is what drives the whole tile logic.
        -- The two undergrounds get real concrete to stand on, because an underground
        -- collides with the meltable layer and cannot be shift-placed onto bare ice
        -- any more than it can be built there. What they stand on is incidental here.
        patch.paint("ice-platform")
        patch.paint_at("ammoniacal-ocean", patch.gap)
        patch.paint_at("concrete", patch.a)
        patch.paint_at("concrete", patch.b)
        patch.stock{}
        assert.equals("ammoniacal-ocean", patch.tile_at(),
            "setup: the gap is " .. patch.tile_at() .. ", not ocean")

        patch.build_ghost(UNDERGROUND, patch.a, SOUTH)
        patch.build_ghost(UNDERGROUND, patch.b, NORTH)

        for label, position in pairs({ A = patch.a, B = patch.b }) do
            print(label .. ": " .. table.concat(patch.occupants(position), "+") ..
                  " on " .. patch.tile_at(position))
        end

        assert.equals(PIPE, patch.ghost_at(),
            "expected a pipe ghost, found " .. tostring(patch.ghost_at()))
        local covers = patch.tile_ghosts_at()
        assert.equals(2, #covers,
            "expected an ice platform ghost and a cover on top of it, found " ..
            #covers .. " (" .. table.concat(covers, ", ") .. ")")
    end)
end)
