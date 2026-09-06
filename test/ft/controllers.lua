--- The same build, made by every kind of player the game has.
local world = require("test.ft.world")

local PIPE, UNDERGROUND = world.PIPE, world.UNDERGROUND
local SOUTH, NORTH = defines.direction.south, defines.direction.north

describe("the character controller", function()
    --- Freeplay's controller: a real body, a real inventory, and a build reach
    test("pays for the connector out of the character", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        local character = patch.surface.create_entity{
            name = "character", position = { x = patch.left + 9.5, y = patch.top + 5.5 },
            force = patch.player.force }
        assert(character ~= nil, "could not create a character to control")
        patch.player.set_controller{ type = defines.controllers.character, character = character }
        local stand = { x = patch.left + 9.5, y = patch.top + 5.5 }
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        assert(patch.count(PIPE) == 10, "the character has no usable main inventory")

        patch.build(UNDERGROUND, patch.a, SOUTH, stand)
        patch.build(UNDERGROUND, patch.b, NORTH, stand)

        assert(patch.pipe_at() ~= nil, "no connector was placed")
        assert(patch.ghost_at() == nil,
            "a ghost was placed instead of a real pipe, " .. tostring(patch.ghost_at()))
        assert(patch.count(PIPE) == 9,
            "expected one pipe consumed, character holds " .. patch.count(PIPE))
    end)
end)

describe("remote view", function()
    --- Map view: cannot move or change items, can only order ghosts
    test("orders a ghost connector and charges nothing", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        -- a body to be away from, and the inventory the mod would charge if it could
        local character = patch.surface.create_entity{
            name = "character", position = { x = patch.left + 9.5, y = patch.top + 9.5 },
            force = patch.player.force }
        assert(character ~= nil, "could not create a character to leave behind")
        patch.player.set_controller{ type = defines.controllers.character, character = character }
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        -- 2.1 remote view reports no main inventory even with a character, so hold onto
        -- the one we stocked; it is the character's and stays valid
        local stocked = patch.player.get_main_inventory()

        patch.player.set_controller{
            type = defines.controllers.remote, position = patch.b, surface = patch.surface }
        assert(patch.player.get_main_inventory() == nil,
            "remote view grew a main inventory; this test no longer proves what it thinks")

        -- Ordering ghosts is what remote view can actually do. build_from_cursor
        -- ignores the restriction and builds for real, which no player can, so it would
        -- test the API rather than the mod.
        patch.build_ghost(UNDERGROUND, patch.a, SOUTH, patch.a)
        patch.build_ghost(UNDERGROUND, patch.b, NORTH, patch.b)

        assert(patch.pipe_at() == nil, "a real pipe was built from remote view")
        assert(patch.ghost_at() == PIPE,
            "expected a ghost connector, found " .. tostring(patch.ghost_at()))
        assert(stocked.valid and stocked.get_item_count(PIPE) == 10,
            "the mod charged for a ghost, the character holds " ..
            tostring(stocked.valid and stocked.get_item_count(PIPE)))
    end)
end)

describe("the map editor", function()
    --- Nothing to pay with is not a reason to place a ghost when nothing is charged
    test("builds a real connector and a real cover with an empty inventory", function()
        local patch = world.patch()
        patch.player.set_controller{ type = defines.controllers.editor }
        -- the map editor pauses entity updates, which also stops the tick the framework
        -- needs to reach the next test
        game.tick_paused = false
        patch.paint("refined-concrete")
        patch.paint_at("ice-rough", patch.gap)
        local inventory = patch.player.get_main_inventory()
        if inventory then inventory.clear() end
        assert(patch.tile_at() == "ice-rough", "setup: the gap is " .. patch.tile_at() .. ", not ice")

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() ~= nil, "no connector was placed")
        assert(patch.ghost_at() == nil,
            "a ghost was placed for want of an item that costs nothing, " ..
            tostring(patch.ghost_at()))
        assert(world.same_tile(patch.tile_at(), "refined-concrete"),
            "the gap was not covered with a real tile, it is " .. patch.tile_at())
        assert(#patch.tile_ghosts_at() == 0,
            "a cover ghost was placed for want of an item that costs nothing")
    end)

    test("charges nothing even when the items are there to charge", function()
        local patch = world.patch()
        patch.player.set_controller{ type = defines.controllers.editor }
        game.tick_paused = false
        patch.paint("refined-concrete")
        patch.paint_at("ice-rough", patch.gap)
        local inventory = patch.player.get_main_inventory()
        assert(inventory ~= nil, "the editor controller has no main inventory")
        inventory.clear()
        inventory.insert{ name = PIPE, count = 10 }
        inventory.insert{ name = "refined-concrete", count = 10 }

        patch.build(UNDERGROUND, patch.a, SOUTH)
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() ~= nil, "no connector was placed in editor mode")
        assert(world.same_tile(patch.tile_at(), "refined-concrete"),
            "the gap was not covered, it is " .. patch.tile_at())
        -- the game does not charge for a build in editor mode, so neither should we
        assert(inventory.get_item_count(PIPE) == 10,
            "the mod charged for a pipe in editor mode, " ..
            inventory.get_item_count(PIPE) .. " left of 10")
        assert(inventory.get_item_count("refined-concrete") == 10,
            "the mod charged for a cover tile in editor mode, " ..
            inventory.get_item_count("refined-concrete") .. " left of 10")
    end)
end)
