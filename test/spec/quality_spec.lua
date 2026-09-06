local support = require("test.support.factorio")
support.install_defines()

-- vanilla's five, whose levels are 0 through 5 with epic at 3 and legendary at 5
_G.prototypes = { quality = {
    normal    = { name = "normal",    level = 0 },
    uncommon  = { name = "uncommon",  level = 1 },
    rare      = { name = "rare",      level = 2 },
    epic      = { name = "epic",      level = 3 },
    legendary = { name = "legendary", level = 5 },
} }
local quality = require("lib.quality")

local function level_of(name) return prototypes.quality[name].level end

describe("nearest_available", function()
    it("finds nothing when the player carries nothing", function()
        assert.is_nil(quality.nearest_available({}, level_of("rare")))
    end)

    it("ignores an entry that has run down to zero", function()
        assert.is_nil(quality.nearest_available({ normal = 0 }, level_of("rare")))
    end)

    it("takes the only quality on offer, above or below", function()
        assert.equals("legendary", quality.nearest_available({ legendary = 1 }, level_of("normal")))
        assert.equals("normal", quality.nearest_available({ normal = 1 }, level_of("legendary")))
    end)

    it("takes the nearest by level", function()
        -- from rare: normal is 2 away, legendary 3
        assert.equals("normal",
            quality.nearest_available({ normal = 1, legendary = 1 }, level_of("rare")))
        -- from normal: uncommon is 1 away, epic 3
        assert.equals("uncommon",
            quality.nearest_available({ epic = 1, uncommon = 1 }, level_of("normal")))
    end)

    it("breaks a tie towards the lower quality", function()
        -- from uncommon, normal and rare are both one level away
        assert.equals("normal",
            quality.nearest_available({ normal = 1, rare = 1 }, level_of("uncommon")))
        -- from epic, rare and legendary are both two away
        assert.equals("rare",
            quality.nearest_available({ rare = 1, legendary = 1 }, level_of("epic")))
    end)

    it("breaks a tie between qualities sharing a level by name, so clients agree", function()
        prototypes.quality["odd"] = { name = "odd", level = 2 }
        assert.equals("odd", quality.nearest_available({ odd = 1, rare = 1 }, level_of("epic")))
        prototypes.quality["odd"] = nil
    end)
end)

describe("find_stack_to_spend", function()
    local placed = prototypes.quality["rare"]

    it("always uses the matching quality when there is one", function()
        local inventory = support.inventory{ pipe = { normal = 5, rare = 1, legendary = 5 } }
        for _, substitute in ipairs({ true, false }) do
            local stack = quality.find_stack_to_spend(inventory, "pipe", placed, substitute)
            assert.equals("rare", stack.quality.name)
        end
    end)

    it("refuses another quality when the setting is off", function()
        local inventory = support.inventory{ pipe = { normal = 5 } }
        assert.is_nil(quality.find_stack_to_spend(inventory, "pipe", placed, false))
    end)

    it("reaches for the nearest other quality when the setting is on", function()
        local inventory = support.inventory{ pipe = { normal = 5, legendary = 5 } }
        local stack = quality.find_stack_to_spend(inventory, "pipe", placed, true)
        assert.equals("normal", stack.quality.name)
    end)

    it("finds nothing when the player has none of the item, setting or not", function()
        local inventory = support.inventory{}
        assert.is_nil(quality.find_stack_to_spend(inventory, "pipe", placed, true))
        assert.is_nil(quality.find_stack_to_spend(inventory, "pipe", placed, false))
    end)
end)
