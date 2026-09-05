local support = require("test.support.factorio")
support.install_defines()
local undo = require("lib.undo")

--- An undo item is a list of actions; index 1 is the most recent item
local function queue(...)
    local items = {}
    for _, action_count in ipairs({ ... }) do
        local actions = {}
        for i = 1, action_count do actions[i] = { kind = "action", index = i } end
        items[#items + 1] = actions
    end
    return items
end

local function shape(player)
    local counts = {}
    for index, item in ipairs(player.undo_items) do counts[index] = #item end
    return counts
end

describe("save_undo_state", function()
    it("reports zeroes for an empty queue", function()
        assert.same({ item_count = 0, action_count = 0 }, undo.save_undo_state(support.player()))
    end)

    it("counts the items and the actions in the most recent one", function()
        local player = support.player(queue(3, 7))
        assert.same({ item_count = 2, action_count = 3 }, undo.save_undo_state(player))
    end)
end)

describe("restore_undo_state", function()
    it("does nothing when nothing was added", function()
        local player = support.player(queue(2, 5))
        local state = undo.save_undo_state(player)
        undo.restore_undo_state(player, state)
        assert.same({ 2, 5 }, shape(player))
    end)

    it("removes an item the write created", function()
        local player = support.player(queue(2, 5))
        local state = undo.save_undo_state(player)
        table.insert(player.undo_items, 1, queue(1)[1]) -- our tile became its own undo item
        undo.restore_undo_state(player, state)
        assert.same({ 2, 5 }, shape(player))
    end)

    it("removes actions the write appended to the existing item", function()
        local player = support.player(queue(2, 5))
        local state = undo.save_undo_state(player)
        table.insert(player.undo_items[1], { kind = "our tile" })
        undo.restore_undo_state(player, state)
        assert.same({ 2, 5 }, shape(player))
    end)

    it("clears the queue when it started empty", function()
        local player = support.player()
        local state = undo.save_undo_state(player)
        table.insert(player.undo_items, 1, queue(3)[1])
        table.insert(player.undo_items, 1, queue(1)[1])
        undo.restore_undo_state(player, state)
        assert.same({}, shape(player))
    end)

    it("never removes an item's last action, which would take the item with it", function()
        -- a pre-existing item of one action, with two of ours appended
        local player = support.player(queue(1, 4))
        local state = { item_count = 2, action_count = 1 }
        table.insert(player.undo_items[1], { kind = "ours" })
        table.insert(player.undo_items[1], { kind = "ours" })
        undo.restore_undo_state(player, state)
        assert.same({ 1, 4 }, shape(player))
    end)
end)
