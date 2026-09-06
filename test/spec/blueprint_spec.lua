local blueprint = require("lib.blueprint")

local function player_holding(cursor)
    return { cursor_stack = cursor }
end

describe("is_stamping", function()
    it("says no for an empty cursor", function()
        assert.is_false(blueprint.is_stamping(player_holding{ valid_for_read = false }))
    end)

    it("says no when the controller has no cursor at all", function()
        assert.is_false(blueprint.is_stamping(player_holding(nil)))
    end)

    it("says no for an ordinary item, which is what a shift-place holds", function()
        assert.is_false(blueprint.is_stamping(player_holding{
            valid_for_read = true, is_blueprint = false, is_blueprint_book = false }))
    end)

    it("says yes for a blueprint", function()
        assert.is_true(blueprint.is_stamping(player_holding{
            valid_for_read = true, is_blueprint = true, is_blueprint_book = false }))
    end)

    it("says yes for a blueprint book, which stamps its active blueprint", function()
        assert.is_true(blueprint.is_stamping(player_holding{
            valid_for_read = true, is_blueprint = false, is_blueprint_book = true }))
    end)
end)
