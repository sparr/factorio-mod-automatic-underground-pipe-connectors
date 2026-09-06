local support = require("test.support.factorio")
support.install_defines()

--- Modelled on the mods in the report. Pyanodons gives its niobium pipes a
--- connection category of their own, "niobium-pipe", but only when the startup
--- setting py-braided-pipes is on -- with it off the field is nil and everything
--- joins everything. Advanced Fluid Handling's tiered undergrounds list the plain
--- vanilla pipe as a component, so the recipe alone cannot tell them apart.
local function entity(categories, item)
    return {
        fluidbox_prototypes = { { pipe_connections = { { connection_category = categories } } } },
        items_to_place_this = item and { { name = item } } or nil,
    }
end

local VANILLA = { "default" }
local NIOBIUM = { "niobium-pipe" }

--- Installed per test: the spec files share one Lua state, and another spec's
--- install_prototypes would otherwise replace this table before these tests run.
local function install()
    _G.prototypes = {
        entity = {
            ["pipe"]                    = entity(VANILLA, "pipe"),
            ["pipe-to-ground"]          = entity(VANILLA, "pipe-to-ground"),
            ["niobium-pipe"]            = entity(NIOBIUM, "niobium-pipe"),
            ["niobium-pipe-to-ground"]  = entity(NIOBIUM, "niobium-pipe-to-ground"),
            -- what the bridge mod leaves behind: an AFH underground retiered onto niobium
            ["underground-i-t2-pipe"]   = entity(NIOBIUM, "underground-i-t2-pipe"),
            -- and the same underground with the category setting turned off
            ["plain-t2-underground"]    = entity(nil, "plain-t2-underground"),
            ["plain-pipe"]              = entity(nil, "plain-pipe"),
        },
        get_entity_filtered = function()
            return {
                ["pipe"] = _G.prototypes.entity["pipe"],
                ["niobium-pipe"] = _G.prototypes.entity["niobium-pipe"],
                ["plain-pipe"] = _G.prototypes.entity["plain-pipe"],
            }
        end,
    }
end

local pipes = require("lib.pipes")

local PIPE = { item = "pipe", entity = "pipe" }
local NIOBIUM_PIPE = { item = "niobium-pipe", entity = "niobium-pipe" }

describe("categories_compatible", function()
    before_each(install)
    it("matches when a category is shared", function()
        assert.is_true(pipes.categories_compatible({ ["niobium-pipe"] = true },
                                                   { ["niobium-pipe"] = true }))
    end)

    it("refuses when both declare categories and share none", function()
        assert.is_false(pipes.categories_compatible({ ["niobium-pipe"] = true },
                                                    { default = true }))
    end)

    it("stays permissive when either side declares none", function()
        assert.is_true(pipes.categories_compatible({}, { default = true }))
        assert.is_true(pipes.categories_compatible({ default = true }, {}))
        assert.is_true(pipes.categories_compatible({}, {}))
    end)
end)

describe("choose", function()
    before_each(install)
    it("takes the only candidate when there is one", function()
        assert.same(PIPE, pipes.choose("pipe-to-ground", { PIPE }))
    end)

    it("takes the first candidate when nothing rules it out", function()
        assert.same(PIPE, pipes.choose("plain-t2-underground", { PIPE, NIOBIUM_PIPE }))
    end)

    it("skips a candidate that could not join the underground", function()
        -- the AFH recipe lists the vanilla pipe first, and it cannot join niobium
        assert.same(NIOBIUM_PIPE, pipes.choose("underground-i-t2-pipe", { PIPE, NIOBIUM_PIPE }))
    end)

    -- AFH's recipes take a plain pipe and nothing else, so with the bridge mod
    -- retiering the underground there is no compatible candidate to be found in it
    it("looks beyond the recipe when no candidate could join", function()
        assert.same(NIOBIUM_PIPE, pipes.choose("underground-i-t2-pipe", { PIPE }))
    end)

    it("falls back to the first candidate when nothing in the game fits", function()
        _G.prototypes.entity["odd-underground"] = entity({ "nothing-matches-this" })
        assert.same(PIPE, pipes.choose("odd-underground", { PIPE }))
        _G.prototypes.entity["odd-underground"] = nil
    end)

    it("returns nothing when the recipe offered no pipe at all", function()
        assert.is_nil(pipes.choose("plain-t2-underground", {}))
    end)
end)
