--- Everything else that can be standing next to, or on top of, the gap.
local world = require("test.ft.world")

local PIPE, UNDERGROUND = world.PIPE, world.UNDERGROUND
local SOUTH, NORTH = defines.direction.south, defines.direction.north

--- An underground is not the only thing worth connecting to: the mod also joins one to
--- any entity whose fluidbox points at the gap. That entity goes down first, so the
--- underground is the second placement and the one that triggers it.
---@param entity_name string
---@param as_ghost boolean? place the neighbour as a ghost rather than a real entity
local function fluid_neighbour(entity_name, as_ghost)
    local patch = world.patch()
    patch.paint("refined-concrete")
    patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }

    -- raise_built fires script_raised_built, not on_built_entity, so putting this
    -- down does not itself wake the mod
    local neighbour = patch.surface.create_entity{
        name = as_ghost and "entity-ghost" or entity_name,
        inner_name = as_ghost and entity_name or nil,
        position = { x = patch.left + 6.5, y = patch.top + 3.5 },
        direction = SOUTH,
        force = patch.player.force,
        raise_built = true,
    }
    assert(neighbour ~= nil, "could not place a " .. entity_name)

    local connection = patch.reachable_connection(neighbour)
    assert(connection ~= nil, "no reachable fluid connection on the " .. entity_name)

    patch.build(UNDERGROUND, connection.spot, connection.facing)

    -- A ghost neighbour still gets a real pipe: only a ghost *underground* puts the
    -- mod into ghost mode. Recorded rather than judged; the point of the ghost case is
    -- that the neighbour is seen at all, which it was not in 2.0.
    assert(patch.pipe_at(connection.gap) ~= nil, "no connector was placed against the " ..
        (as_ghost and "ghost " or "") .. entity_name)
    assert(patch.ghost_at(connection.gap) == nil, "a ghost was placed instead of a real pipe")
    assert(patch.count(PIPE) == 9,
        "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
end

describe("an entity whose fluidbox points at the gap", function()
    test("a pump is connected to", function() fluid_neighbour("pump") end)
    test("a storage tank is connected to", function() fluid_neighbour("storage-tank") end)
    test("a ghost storage tank is connected to", function() fluid_neighbour("storage-tank", true) end)
end)

--- The occupancy guard used to refuse on anything sharing the tile. A character
--- standing on the gap is the case a player actually hits.
---@param blocker string entity to stand on the gap
---@param expect_connector boolean
---@param direction defines.direction?
local function gap_occupant(blocker, expect_connector, direction)
    local patch = world.patch()
    patch.paint("refined-concrete")
    patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }

    local blocking_entity = patch.surface.create_entity{
        name = blocker, position = patch.gap, direction = direction, force = patch.player.force }
    assert(blocking_entity ~= nil, "could not place a " .. blocker .. " on the gap")

    -- both ghosts, so the placement is a ghost and the occupancy guard is what
    -- decides. A real placement would go through can_place_entity instead.
    patch.build_ghost(UNDERGROUND, patch.a, SOUTH)
    patch.build_ghost(UNDERGROUND, patch.b, NORTH)

    local ghost = patch.ghost_at()
    if expect_connector then
        assert(ghost == PIPE,
            "the " .. blocker .. " blocked a ghost it should not have, found " .. tostring(ghost))
    else
        assert(ghost == nil,
            "a ghost was placed on top of a " .. blocker .. ", found " .. tostring(ghost))
    end
end

describe("something standing on the gap", function()
    test("a character does not block a ghost connector", function()
        gap_occupant("character", true)
    end)

    test("a real entity does block a ghost connector", function()
        gap_occupant("wooden-chest", false)
    end)

    --- An elevated rail passes overhead without touching the ground: its whole
    --- collision mask is the elevated_rail layer, which a pipe does not carry. The
    --- ghost case goes through the occupancy guard, the real one through
    --- can_place_entity.
    test("an elevated rail does not block a ghost connector", function()
        gap_occupant("elevated-straight-rail", true, defines.direction.east)
    end)

    test("a real connector goes in under an elevated rail", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        local rail = patch.surface.create_entity{
            name = "elevated-straight-rail", position = patch.gap,
            direction = defines.direction.east, force = patch.player.force }
        assert(rail ~= nil, "could not run an elevated rail over the gap")
        local overhead = false
        for _, entity in pairs(patch.surface.find_entities{ patch.gap, patch.gap }) do
            if entity == rail then overhead = true end
        end
        assert(overhead, "the rail does not actually overlap the gap, so this proves nothing")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() ~= nil, "no pipe was placed under the elevated rail")
        assert(patch.ghost_at() == nil, "a ghost was placed where a real pipe fits")
        assert(patch.count(PIPE) == 9,
            "expected one pipe consumed, inventory holds " .. patch.count(PIPE))
        assert(rail.valid, "the elevated rail was destroyed")
    end)
end)
