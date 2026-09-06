--- The core question: two undergrounds one apart, and what lands between them.
local world = require("test.ft.world")

local PIPE, UNDERGROUND = world.PIPE, world.UNDERGROUND
local SOUTH, NORTH = defines.direction.south, defines.direction.north

describe("a pair of undergrounds one apart", function()
    test("on ordinary ground gets a real pipe, paid for", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        assert.is_true(world.same_tile(patch.tile_at(), "refined-concrete"),
            "setup: the gap is " .. patch.tile_at() .. ", not refined concrete")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        assert.is_nil(patch.pipe_at(),
            "a pipe appeared before the second underground existed")
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert.is_not_nil(patch.pipe_at(), "no pipe was placed in the gap")
        assert.is_nil(patch.ghost_at(), "a ghost was placed instead of a real pipe")
        assert.equals(9, patch.count(PIPE),
            "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
        assert.equals(8, patch.count(UNDERGROUND),
            "both undergrounds should have been paid for too, inventory holds " ..
            patch.count(UNDERGROUND))
        assert.is_true(world.same_tile(patch.tile_at(), "refined-concrete"),
            "the ground was changed to " .. patch.tile_at())
        assert.equals(0, #patch.tile_ghosts_at(), "an unnecessary tile ghost was placed")
    end)

    test("with no pipe in inventory falls back to a ghost, free", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [UNDERGROUND] = 10 }
        assert.equals(0, patch.count(PIPE), "setup: the player should hold no pipes")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert.is_nil(patch.pipe_at(), "a real pipe was placed without one to pay with")
        assert.equals(PIPE, patch.ghost_at(),
            "expected a pipe ghost, found " .. tostring(patch.ghost_at()))
        assert.equals(0, patch.count(PIPE),
            "pipes appeared from nowhere, inventory holds " .. patch.count(PIPE))
        assert.equals(8, patch.count(UNDERGROUND),
            "both undergrounds should still have been paid for, inventory holds " ..
            patch.count(UNDERGROUND))
    end)
end)

describe("a lone underground", function()
    test("places nothing at all", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }

        patch.build(UNDERGROUND, patch.b, NORTH)

        assert.is_nil(patch.pipe_at(), "a pipe was placed with nothing to connect to")
        assert.is_nil(patch.ghost_at(), "a ghost was placed with nothing to connect to")
        assert.equals(10, patch.count(PIPE),
            "a pipe was consumed with nothing to connect to")
    end)
end)

describe("ghosts", function()
    --- A real underground next to a ghost one must not hand out a free pipe
    test("a real underground beside a ghost one gets a real pipe, paid for", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }

        patch.build_ghost(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        -- the neighbour being a ghost is irrelevant; the player placed a real
        -- underground, so they get a real pipe and are charged for it
        assert.is_not_nil(patch.pipe_at(), "no connector was placed")
        assert.is_nil(patch.ghost_at(),
            "the neighbour's ghostness leaked into the connector, found " ..
            tostring(patch.ghost_at()))
        assert.equals(9, patch.count(PIPE),
            "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
    end)

    --- The mirror of the case above: the placement is a ghost, so the connector is
    test("a ghost underground beside a real one gets a ghost, free", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build_ghost(UNDERGROUND, patch.b, NORTH)

        assert.is_nil(patch.pipe_at(), "a real pipe was placed for a ghost placement")
        assert.equals(PIPE, patch.ghost_at(),
            "expected a pipe ghost, found " .. tostring(patch.ghost_at()))
        assert.equals(10, patch.count(PIPE),
            "a ghost connector was charged for, inventory holds " .. patch.count(PIPE))
    end)
end)

describe("ground that names a cover tile", function()
    --- Buildable ground that merely names a cover tile. The mod used to read
    --- default_cover_tile as "this ground needs covering", try to place a cover tile
    --- ghost the game refuses, and bail out, so nothing appeared at all. Reported
    --- against Moshine dry swamp, which is ground_tile with default_cover_tile =
    --- foundation.
    test("is left alone and still gets a real pipe", function()
        local patch = world.patch()
        local TILE = "aupc-tests-covered-ground"
        patch.paint(TILE)
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        assert.equals(TILE, patch.tile_at(),
            "setup: the gap is " .. patch.tile_at() .. ", not " .. TILE)
        local cover = prototypes.tile[TILE].default_cover_tile
        assert.is_not_nil(cover,
            "setup: the test tile names no cover tile, so it proves nothing")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        assert.is_nil(patch.pipe_at(),
            "a pipe appeared before the second underground existed")
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert.is_not_nil(patch.pipe_at(), "no pipe was placed in the gap")
        assert.is_nil(patch.ghost_at(), "a ghost was placed instead of a real pipe")
        assert.equals(9, patch.count(PIPE),
            "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
        assert.equals(TILE, patch.tile_at(),
            "the ground was paved over, it is now " .. patch.tile_at())
        assert.equals(0, #patch.tile_ghosts_at(),
            "a cover tile ghost was placed on ground that did not need covering: " ..
            table.concat(patch.tile_ghosts_at(), "+"))
    end)

    --- Warptorio's warp foundation: buildable ground naming empty-space as its cover.
    --- The mod used to hand that straight to can_place_entity as a tile ghost and die
    --- on "empty-space can not be part a tile ghost".
    test("naming an unplaceable cover tile still gets a real pipe", function()
        local patch = world.patch()
        local TILE = "aupc-tests-warp-foundation"
        patch.paint(TILE)
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        assert.equals(TILE, patch.tile_at(),
            "setup: the gap is " .. patch.tile_at() .. ", not " .. TILE)
        local cover = prototypes.tile[TILE].default_cover_tile
        assert.is_true(cover ~= nil and cover.name == "empty-space",
            "setup: the test tile does not name empty-space as its cover")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert.is_not_nil(patch.pipe_at(), "no pipe was placed in the gap")
        assert.is_nil(patch.ghost_at(), "a ghost was placed instead of a real pipe")
        assert.equals(TILE, patch.tile_at(),
            "the ground was changed to " .. patch.tile_at())
        assert.equals(0, #patch.tile_ghosts_at(), "an unnecessary tile ghost was placed")
    end)

    --- The same unplaceable cover, but the gap is ground a pipe cannot sit on, so the
    --- mod genuinely goes looking for a cover tile. There is no answer here, and the
    --- only correct behaviour is to leave the gap alone rather than take the game down.
    test("with an unplaceable cover over unbuildable ground is refused, not crashed on", function()
        local patch = world.patch()
        local TILE = "aupc-tests-unghostable-gap"
        patch.paint("refined-concrete")
        patch.paint_at(TILE, patch.gap)
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10, ["refined-concrete"] = 10 }
        assert.equals(TILE, patch.tile_at(),
            "setup: the gap is " .. patch.tile_at() .. ", not " .. TILE)

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert.is_nil(patch.pipe_at(), "a pipe was placed on ground it cannot sit on")
        assert.equals(10, patch.count(PIPE),
            "a pipe was spent on a connector that could not be built")
        assert.equals(TILE, patch.tile_at(),
            "the ground was changed to " .. patch.tile_at())
    end)
end)
