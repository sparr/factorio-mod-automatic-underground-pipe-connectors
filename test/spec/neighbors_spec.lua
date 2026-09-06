local support = require("test.support.factorio")
support.install_defines()
local neighbors = require("lib.neighbors")

local UNDERGROUND = "pipe-to-ground"
local PIPE = "pipe"
--- vanilla puts every connection in {"default"}
local VANILLA = { default = true }

-- find_connection_neighbor reads the pipe's own categories out of prototypes
_G.prototypes = {
    entity = {
        [PIPE] = { fluidbox_prototypes = {
            { pipe_connections = { { connection_category = { "default" } } } },
        } },
    },
}
-- an underground at 10.5,20.5 pointing north puts its pipe at 10.5,19.5, and looks
-- for a partner at 9.5,19.5 facing east, 10.5,18.5 facing south, or 11.5,19.5 facing west
local UNDERGROUND_POSITION = { x = 10.5, y = 20.5 }
local PIPE_POSITION = { 10.5, 19.5 }

--- Stands in for the underground that triggered the search. It opens onto the gap
--- like any of its neighbours would, so the search has to skip it by identity.
local PLACED = support.with_fluid_connections(
    { name = UNDERGROUND, type = UNDERGROUND, direction = defines.direction.north,
      position = UNDERGROUND_POSITION },
    { { { connection_type = "normal", target_position = { x = 10.5, y = 19.5 } } } })

local function look(entities, placed)
    return neighbors.find_connection_neighbor(
        support.surface{ entities = entities },
        PIPE_POSITION,
        UNDERGROUND,
        PIPE,
        placed or PLACED)
end

describe("entity_type_or_ghost_type", function()
    it("sees through a ghost", function()
        assert.equals("pipe", neighbors.entity_type_or_ghost_type{ type = "entity-ghost", ghost_type = "pipe" })
    end)

    it("passes a real entity's type straight through", function()
        assert.equals("pipe-to-ground", neighbors.entity_type_or_ghost_type{ type = "pipe-to-ground" })
    end)
end)

describe("opens_onto", function()
    local function entity_connecting_to(x, y)
        return support.fluid_entity{ { { target_position = { x = x, y = y } } } }
    end

    it("matches a connection aimed at the gap", function()
        assert.is_true(neighbors.opens_onto(
            entity_connecting_to(10.5, 19.5), PIPE_POSITION, VANILLA))
    end)

    it("snaps a slightly offset connection onto the gap", function()
        -- some mods place connections at offsets like .04 and .07
        assert.is_true(neighbors.opens_onto(
            entity_connecting_to(10.46, 19.54), PIPE_POSITION, VANILLA))
    end)

    it("ignores a buried connection reaching the same tile", function()
        local buried = support.fluid_entity{ {
            { connection_type = "underground", target_position = { x = 10.5, y = 19.5 } } } }
        assert.is_false(neighbors.opens_onto(buried, PIPE_POSITION, VANILLA))
    end)

    it("does not stretch to a connection aimed somewhere else", function()
        assert.is_false(neighbors.opens_onto(
            entity_connecting_to(10.2, 19.5), PIPE_POSITION, VANILLA))
        assert.is_false(neighbors.opens_onto(
            entity_connecting_to(11.5, 19.5), PIPE_POSITION, VANILLA))
    end)
end)

describe("connection categories", function()
    it("lets a connection through when both sides share a category", function()
        assert.is_true(neighbors.connection_categories_intersect({ default = true }, { "default" }))
    end)

    it("rejects a connection whose categories are disjoint", function()
        -- a tiered-fluid mod puts higher tiers in their own category, and a
        -- tier-1 pipe placed against one would join nothing
        assert.is_false(neighbors.connection_categories_intersect({ default = true }, { "ht-pipes" }))
    end)

    it("accepts when any one category matches", function()
        assert.is_true(neighbors.connection_categories_intersect(
            { default = true, ["ht-pipes"] = true }, { "niobium-pipe", "ht-pipes" }))
    end)

    it("stays permissive when the neighbour declares none", function()
        assert.is_true(neighbors.connection_categories_intersect({ default = true }, nil))
    end)

    it("stays permissive when the pipe declares none", function()
        assert.is_true(neighbors.connection_categories_intersect({}, { "ht-pipes" }))
    end)

    it("refuses a geometrically aligned connection in the wrong category", function()
        local entity = support.fluid_entity{
            { { target_position = { x = 10.5, y = 19.5 }, connection_category = { "ht-pipes" } } } }
        assert.is_false(neighbors.opens_onto(
            entity, PIPE_POSITION, VANILLA))
        -- and the same geometry with a matching category still connects
        local same_tier = support.fluid_entity{
            { { target_position = { x = 10.5, y = 19.5 }, connection_category = { "default" } } } }
        assert.is_true(neighbors.opens_onto(
            same_tier, PIPE_POSITION, VANILLA))
    end)
end)

--- A vanilla-shaped underground: one normal connection on the side it faces and an
--- underground one behind it. `opens` overrides where the normal one points, which is
--- how Pipe Plus's junctions differ.
local VECTORS = {
    [defines.direction.north] = { 0, -1 },
    [defines.direction.east]  = { 1, 0 },
    [defines.direction.south] = { 0, 1 },
    [defines.direction.west]  = { -1, 0 },
}

local function underground(fields, opens)
    local position, direction = fields.position, fields.direction
    local connections = {}
    for _, facing in ipairs(opens or { direction }) do
        local vector = VECTORS[facing]
        connections[#connections + 1] = { connection_type = "normal", target_position =
            { x = position.x + vector[1], y = position.y + vector[2] } }
    end
    -- the buried run, pointing back the way it came
    local back = VECTORS[(direction + 8) % 16]
    connections[#connections + 1] = { connection_type = "underground", target_position =
        { x = position.x + back[1] * 2, y = position.y + back[2] * 2 } }
    return support.with_fluid_connections(fields, { connections })
end

describe("openings", function()
    local function at(x, y) return { connection_type = "normal", target_position = { x = x, y = y } } end

    it("gives a vanilla underground the one tile it faces", function()
        local entity = support.fluid_entity{ { at(10.5, 19.5),
            { connection_type = "underground", target_position = { x = 10.5, y = 22.5 } } } }
        assert.same({ { 10.5, 19.5 } }, neighbors.openings(entity, VANILLA))
    end)

    -- the sideways arms are the point: without them a T or an X can only ever be
    -- joined straight ahead, which for the T is the one side it cannot use
    it("gives a junction every arm it opens onto", function()
        local entity = support.fluid_entity{ { at(11.5, 20.5), at(9.5, 20.5),
            { connection_type = "underground", target_position = { x = 10.5, y = 22.5 } } } }
        assert.same({ { 11.5, 20.5 }, { 9.5, 20.5 } }, neighbors.openings(entity, VANILLA))
    end)

    it("leaves out the buried run", function()
        local entity = support.fluid_entity{ {
            { connection_type = "underground", target_position = { x = 10.5, y = 19.5 } } } }
        assert.same({}, neighbors.openings(entity, VANILLA))
    end)

    it("leaves out an arm the pipe could not join", function()
        local entity = support.fluid_entity{ {
            { connection_type = "normal", target_position = { x = 11.5, y = 20.5 },
              connection_category = { "ht-pipes" } },
            at(9.5, 20.5),
        } }
        assert.same({ { 9.5, 20.5 } }, neighbors.openings(entity, VANILLA))
    end)

    it("reports a tile once even when two connections reach it", function()
        local entity = support.fluid_entity{ { at(10.5, 19.5) }, { at(10.5, 19.5) } }
        assert.same({ { 10.5, 19.5 } }, neighbors.openings(entity, VANILLA))
    end)
end)

describe("find_connection_neighbor", function()
    it("finds nothing in an empty area", function()
        local found = look{}
        assert.is_false(found)
    end)

    it("finds an underground two ahead facing back", function()
        local found = look{
            underground({ name = UNDERGROUND, type = UNDERGROUND,
              direction = defines.direction.south, position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_true(found)
    end)

    it("finds an underground around a corner", function()
        local found = look{
            underground({ name = UNDERGROUND, type = UNDERGROUND,
              direction = defines.direction.east, position = { x = 9.5, y = 19.5 } }),
        }
        assert.is_true(found)
    end)

    -- find_entity takes an EntityWithQualityID, where a bare name means normal, so
    -- the search used to skip every non-normal neighbour and place nothing at all
    it("finds an underground of a quality other than normal", function()
        local found = look{
            underground({ name = UNDERGROUND, type = UNDERGROUND, quality = "uncommon",
              direction = defines.direction.south, position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_true(found)
    end)

    it("finds a ghost partner of a quality other than normal", function()
        local found = look{
            underground({ name = "entity-ghost", type = "entity-ghost", ghost_name = UNDERGROUND,
              ghost_type = UNDERGROUND, quality = "legendary",
              direction = defines.direction.south, position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_true(found)
    end)

    it("still respects direction for a non-normal neighbour", function()
        local found = look{
            underground({ name = UNDERGROUND, type = UNDERGROUND, quality = "rare",
              direction = defines.direction.north, position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_false(found)
    end)

    it("ignores an underground in the right place facing the wrong way", function()
        local found = look{
            underground({ name = UNDERGROUND, type = UNDERGROUND,
              direction = defines.direction.north, position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_false(found)
    end)

    it("finds a ghost partner", function()
        local found = look{
            underground({ name = "entity-ghost", type = "entity-ghost", ghost_name = UNDERGROUND,
              ghost_type = UNDERGROUND, direction = defines.direction.south,
              position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_true(found)
    end)

    -- Pipe Plus, issue #15. Its T junction keeps the vanilla underground connection
    -- but opens east and west only, so the tile a vanilla underground would open onto
    -- is reached by the buried run alone. Its X junction adds the opening back.
    describe("junction undergrounds", function()
        local function junction(connections)
            return support.with_fluid_connections(
                { name = UNDERGROUND, type = UNDERGROUND,
                  direction = defines.direction.south, position = { x = 10.5, y = 18.5 } },
                { connections })
        end

        it("refuses a T junction, which only reaches the gap underground", function()
            assert.is_false(look{ junction{
                { connection_type = "normal", target_position = { x = 11.5, y = 18.5 } },
                { connection_type = "normal", target_position = { x = 9.5, y = 18.5 } },
                { connection_type = "underground", target_position = { x = 10.5, y = 19.5 } },
            } })
        end)

        -- the opening that matters is second in the list, not first
        it("accepts an X junction, which does open onto the gap", function()
            assert.is_true(look{ junction{
                { connection_type = "normal", target_position = { x = 11.5, y = 18.5 } },
                { connection_type = "normal", target_position = { x = 10.5, y = 19.5 } },
                { connection_type = "normal", target_position = { x = 9.5, y = 18.5 } },
                { connection_type = "underground", target_position = { x = 10.5, y = 17.5 } },
            } })
        end)

        it("scans every fluid storage, not just the first", function()
            local entity = support.with_fluid_connections(
                { name = UNDERGROUND, type = UNDERGROUND,
                  direction = defines.direction.south, position = { x = 10.5, y = 18.5 } },
                {
                    { { connection_type = "normal", target_position = { x = 11.5, y = 18.5 } } },
                    { { connection_type = "normal", target_position = { x = 10.5, y = 19.5 } } },
                })
            assert.is_true(look{ entity })
        end)
    end)

    it("does not mistake the underground that triggered it for a neighbour", function()
        -- it opens onto the gap as surely as any partner would
        assert.is_false(look{ PLACED })
    end)

    it("finds a partner reached sideways, not just straight ahead", function()
        -- the gap here is beside the junction rather than in front of it; nothing in
        -- the search knows or cares which way anything faces
        local partner = support.fluid_entity({ { { connection_type = "normal",
            target_position = { x = 10.5, y = 19.5 } } } },
            { name = UNDERGROUND, type = UNDERGROUND, position = { x = 9.5, y = 19.5 } })
        assert.is_true(look{ partner })
    end)

    it("connects to a non-pipe entity whose fluidbox points at the gap", function()
        local found = look{
            support.fluid_entity({ { { target_position = { x = 10.5, y = 19.5 } } } },
              { name = "storage-tank", type = "storage-tank", position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_true(found)
    end)

    it("skips fluid wagons, whose connections are for pumps", function()
        local found = look{
            support.fluid_entity({ { { target_position = { x = 10.5, y = 19.5 } } } },
              { name = "fluid-wagon", type = "fluid-wagon", position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_false(found)
    end)

    it("does not treat a stray pipe as a fluidbox neighbour", function()
        local found = look{
            support.fluid_entity({ { { target_position = { x = 10.5, y = 19.5 } } } },
              { name = "pipe", type = "pipe", position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_false(found)
    end)

    it("ignores an entity whose fluidbox points elsewhere", function()
        local found = look{
            support.fluid_entity({ { { target_position = { x = 10.5, y = 17.5 } } } },
              { name = "storage-tank", type = "storage-tank", position = { x = 10.5, y = 18.5 } }),
        }
        assert.is_false(found)
    end)
end)
