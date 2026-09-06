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

local function look(entities)
    return neighbors.find_connection_neighbor(
        support.surface{ entities = entities },
        UNDERGROUND_POSITION,
        neighbors.directions_to_neighbors[defines.direction.north],
        UNDERGROUND,
        PIPE_POSITION,
        PIPE)
end

describe("entity_type_or_ghost_type", function()
    it("sees through a ghost", function()
        assert.equals("pipe", neighbors.entity_type_or_ghost_type{ type = "entity-ghost", ghost_type = "pipe" })
    end)

    it("passes a real entity's type straight through", function()
        assert.equals("pipe-to-ground", neighbors.entity_type_or_ghost_type{ type = "pipe-to-ground" })
    end)
end)

describe("should_place_based_on_neighbor_fluidbox_prototypes", function()
    local function entity_connecting_to(x, y)
        return support.fluid_entity{ { { target_position = { x = x, y = y } } } }
    end

    it("matches a connection aimed at the gap", function()
        assert.is_true(neighbors.should_place_based_on_neighbor_fluidbox_prototypes(
            entity_connecting_to(10.5, 19.5), PIPE_POSITION, VANILLA))
    end)

    it("snaps a slightly offset connection onto the gap", function()
        -- some mods place connections at offsets like .04 and .07
        assert.is_true(neighbors.should_place_based_on_neighbor_fluidbox_prototypes(
            entity_connecting_to(10.46, 19.54), PIPE_POSITION, VANILLA))
    end)

    it("does not stretch to a connection aimed somewhere else", function()
        assert.is_false(neighbors.should_place_based_on_neighbor_fluidbox_prototypes(
            entity_connecting_to(10.2, 19.5), PIPE_POSITION, VANILLA))
        assert.is_false(neighbors.should_place_based_on_neighbor_fluidbox_prototypes(
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
        assert.is_false(neighbors.should_place_based_on_neighbor_fluidbox_prototypes(
            entity, PIPE_POSITION, VANILLA))
        -- and the same geometry with a matching category still connects
        local same_tier = support.fluid_entity{
            { { target_position = { x = 10.5, y = 19.5 }, connection_category = { "default" } } } }
        assert.is_true(neighbors.should_place_based_on_neighbor_fluidbox_prototypes(
            same_tier, PIPE_POSITION, VANILLA))
    end)
end)

describe("find_connection_neighbor", function()
    it("finds nothing in an empty area", function()
        local found = look{}
        assert.is_false(found)
    end)

    it("finds an underground two ahead facing back", function()
        local found = look{
            { name = UNDERGROUND, type = UNDERGROUND,
              direction = defines.direction.south, position = { x = 10.5, y = 18.5 } },
        }
        assert.is_true(found)
    end)

    it("finds an underground around a corner", function()
        local found = look{
            { name = UNDERGROUND, type = UNDERGROUND,
              direction = defines.direction.east, position = { x = 9.5, y = 19.5 } },
        }
        assert.is_true(found)
    end)

    it("ignores an underground in the right place facing the wrong way", function()
        local found = look{
            { name = UNDERGROUND, type = UNDERGROUND,
              direction = defines.direction.north, position = { x = 10.5, y = 18.5 } },
        }
        assert.is_false(found)
    end)

    it("finds a ghost partner", function()
        local found = look{
            { name = "entity-ghost", type = "entity-ghost", ghost_name = UNDERGROUND,
              ghost_type = UNDERGROUND, direction = defines.direction.south,
              position = { x = 10.5, y = 18.5 } },
        }
        assert.is_true(found)
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
