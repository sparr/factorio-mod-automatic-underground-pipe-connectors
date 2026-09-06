--- What ctrl+z will take back, asked of the undo stack rather than of the world.
---
--- Nothing in the runtime API performs an undo: LuaUndoRedoStack can read, tag and
--- remove entries but never apply one, and the headless runner has no window to send a
--- keypress to. So these check that what the mod placed joined the player's own undo
--- item, which is the mod's half of the bargain. The engine's half -- that ctrl+z then
--- really does queue the tile for deconstruction, and reverts it on the spot in the
--- editor -- is not covered here. See test/ft/README.md.
local world = require("test.ft.world")

local PIPE, UNDERGROUND = world.PIPE, world.UNDERGROUND
local SOUTH, NORTH = defines.direction.south, defines.direction.north

---@return string[] the action types of the player's newest undo item
local function newest_undo_actions(player)
    local stack = player.undo_redo_stack
    if stack.get_undo_item_count() == 0 then return {} end
    local kinds = {}
    for _, action in pairs(stack.get_undo_item(1)) do
        kinds[#kinds + 1] = tostring(action.type)
    end
    return kinds
end

local function count_of(kinds, wanted)
    local found = 0
    for _, kind in ipairs(kinds) do
        if kind == wanted then found = found + 1 end
    end
    return found
end

--- Build a pair over a meltable gap and hand back what the undo stack made of it
local function build_over_ice(patch)
    patch.paint("refined-concrete")
    patch.paint_at("ice-rough", patch.gap)
    patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10, ["refined-concrete"] = 10 }
    assert(patch.tile_at() == "ice-rough", "setup: the gap is " .. patch.tile_at() .. ", not ice")

    patch.build(UNDERGROUND, patch.a, SOUTH)
    local items_before = patch.player.undo_redo_stack.get_undo_item_count()
    patch.build(UNDERGROUND, patch.b, NORTH)

    local kinds = newest_undo_actions(patch.player)
    print("undo item after the connecting build: " .. table.concat(kinds, ", "))
    return items_before, kinds
end

describe("the undo stack", function()
    test("takes the cover tile and the connector into the player's own undo item", function()
        local patch = world.patch()
        local items_before, kinds = build_over_ice(patch)

        assert(world.same_tile(patch.tile_at(), "refined-concrete"),
            "setup: the gap was never covered, it is " .. patch.tile_at())
        assert(patch.count("refined-concrete") == 9,
            "setup: the cover tile was not paid for, inventory holds " ..
            patch.count("refined-concrete"))

        local items_after = patch.player.undo_redo_stack.get_undo_item_count()
        assert(items_after == items_before + 1,
            "the build should have added exactly one undo item, it added " ..
            (items_after - items_before) .. "; the mod's own placements have to join " ..
            "the player's item rather than making items of their own")
        assert(count_of(kinds, "built-tile") == 1,
            "the cover tile is not in the undo item: " .. table.concat(kinds, ", "))
        -- the underground the player placed, and the connector the mod placed alongside
        -- it: create_entity has no undo parameter, so the engine is attributing the
        -- connector to the player action that triggered it
        assert(count_of(kinds, "built-entity") == 2,
            "expected the underground and the connector in the undo item, got: " ..
            table.concat(kinds, ", "))
    end)

    --- Editor mode is the other half: placements are free, and an undo there takes
    --- effect on the spot rather than queueing deconstruction for bots.
    test("records the same item for a free editor build", function()
        local patch = world.patch()
        patch.player.set_controller{ type = defines.controllers.editor }
        -- the map editor pauses entity updates, which also stops the tick the framework
        -- needs to reach the next test
        game.tick_paused = false
        local items_before, kinds = build_over_ice(patch)

        assert(patch.pipe_at() ~= nil, "setup: no connector was placed in editor mode")
        local items_after = patch.player.undo_redo_stack.get_undo_item_count()
        assert(items_after == items_before + 1,
            "the editor build should have added exactly one undo item, it added " ..
            (items_after - items_before))
        assert(count_of(kinds, "built-tile") == 1,
            "the cover tile is not in the editor undo item: " .. table.concat(kinds, ", "))
        assert(count_of(kinds, "built-entity") == 2,
            "expected the underground and the connector in the editor undo item, got: " ..
            table.concat(kinds, ", "))
    end)

    --- The gap the mod declines is the one worth checking for leftovers: it lays a
    --- cover tile down to try the pipe against, takes it back when the pipe still does
    --- not fit, and must take the undo entry back with it.
    test("is left alone when the mod declines the gap", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.paint_at("aupc-tests-unghostable-gap", patch.gap)
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10, ["refined-concrete"] = 10 }

        patch.build(UNDERGROUND, patch.a, SOUTH)
        local items_before = patch.player.undo_redo_stack.get_undo_item_count()
        patch.build(UNDERGROUND, patch.b, NORTH)

        assert(patch.pipe_at() == nil, "setup: a pipe was placed on ground it cannot sit on")
        local kinds = newest_undo_actions(patch.player)
        print("undo item after the declined build: " .. table.concat(kinds, ", "))
        local items_after = patch.player.undo_redo_stack.get_undo_item_count()
        assert(items_after == items_before + 1,
            "the declined build should have added exactly the player's own undo item, " ..
            "it added " .. (items_after - items_before))
        assert(count_of(kinds, "built-tile") == 0,
            "a cover tile the mod took back again is still offered for undo: " ..
            table.concat(kinds, ", "))
        assert(count_of(kinds, "built-entity") == 1,
            "expected only the underground the player placed, got: " ..
            table.concat(kinds, ", "))
    end)
end)
