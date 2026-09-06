--- The core question: two undergrounds one apart, and what lands between them.
local world = require("test.ft.world")

local PIPE, UNDERGROUND = world.PIPE, world.UNDERGROUND
local SOUTH, NORTH = defines.direction.south, defines.direction.north

describe("a pair of undergrounds one apart", function()
    test("on ordinary ground gets a real pipe, paid for", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        assert(world.same_tile(patch.tile_at(), "refined-concrete"),
            "setup: the gap is " .. patch.tile_at() .. ", not refined concrete")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        assert(patch.pipe_at() == nil, "a pipe appeared before the second underground existed")
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() ~= nil, "no pipe was placed in the gap")
        assert(patch.ghost_at() == nil, "a ghost was placed instead of a real pipe")
        assert(patch.count(PIPE) == 9,
            "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
        assert(patch.count(UNDERGROUND) == 8,
            "both undergrounds should have been paid for too, inventory holds " ..
            patch.count(UNDERGROUND))
        assert(world.same_tile(patch.tile_at(), "refined-concrete"),
            "the ground was changed to " .. patch.tile_at())
        assert(#patch.tile_ghosts_at() == 0, "an unnecessary tile ghost was placed")
    end)

    test("with no pipe in inventory falls back to a ghost, free", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [UNDERGROUND] = 10 }
        assert(patch.count(PIPE) == 0, "setup: the player should hold no pipes")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() == nil, "a real pipe was placed without one to pay with")
        assert(patch.ghost_at() == PIPE,
            "expected a pipe ghost, found " .. tostring(patch.ghost_at()))
        assert(patch.count(PIPE) == 0,
            "pipes appeared from nowhere, inventory holds " .. patch.count(PIPE))
        assert(patch.count(UNDERGROUND) == 8,
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

        assert(patch.pipe_at() == nil, "a pipe was placed with nothing to connect to")
        assert(patch.ghost_at() == nil, "a ghost was placed with nothing to connect to")
        assert(patch.count(PIPE) == 10, "a pipe was consumed with nothing to connect to")
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
        assert(patch.pipe_at() ~= nil, "no connector was placed")
        assert(patch.ghost_at() == nil,
            "the neighbour's ghostness leaked into the connector, found " ..
            tostring(patch.ghost_at()))
        assert(patch.count(PIPE) == 9,
            "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
    end)

    --- The mirror of the case above: the placement is a ghost, so the connector is
    test("a ghost underground beside a real one gets a ghost, free", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build_ghost(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() == nil, "a real pipe was placed for a ghost placement")
        assert(patch.ghost_at() == PIPE,
            "expected a pipe ghost, found " .. tostring(patch.ghost_at()))
        assert(patch.count(PIPE) == 10,
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
        assert(patch.tile_at() == TILE, "setup: the gap is " .. patch.tile_at() .. ", not " .. TILE)
        local cover = prototypes.tile[TILE].default_cover_tile
        assert(cover ~= nil, "setup: the test tile names no cover tile, so it proves nothing")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        assert(patch.pipe_at() == nil, "a pipe appeared before the second underground existed")
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() ~= nil, "no pipe was placed in the gap")
        assert(patch.ghost_at() == nil, "a ghost was placed instead of a real pipe")
        assert(patch.count(PIPE) == 9,
            "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
        assert(patch.tile_at() == TILE, "the ground was paved over, it is now " .. patch.tile_at())
        assert(#patch.tile_ghosts_at() == 0,
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
        assert(patch.tile_at() == TILE, "setup: the gap is " .. patch.tile_at() .. ", not " .. TILE)
        local cover = prototypes.tile[TILE].default_cover_tile
        assert(cover ~= nil and cover.name == "empty-space",
            "setup: the test tile does not name empty-space as its cover")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() ~= nil, "no pipe was placed in the gap")
        assert(patch.ghost_at() == nil, "a ghost was placed instead of a real pipe")
        assert(patch.tile_at() == TILE, "the ground was changed to " .. patch.tile_at())
        assert(#patch.tile_ghosts_at() == 0, "an unnecessary tile ghost was placed")
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
        assert(patch.tile_at() == TILE, "setup: the gap is " .. patch.tile_at() .. ", not " .. TILE)

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() == nil, "a pipe was placed on ground it cannot sit on")
        assert(patch.count(PIPE) == 10, "a pipe was spent on a connector that could not be built")
        assert(patch.tile_at() == TILE, "the ground was changed to " .. patch.tile_at())
    end)
end)
