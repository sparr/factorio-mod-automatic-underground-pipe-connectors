--- The one thing the unit tier cannot check about itself.
---
--- test/support/vanilla.lua transcribes collision masks, cover tiles and tile-placing
--- items out of the shipped prototypes, and every spec that reasons about ground stands
--- on that transcription being true. Nothing in the unit tier can notice when the game
--- changes underneath it, because the stubs are the only game it sees.
---
--- So these tests read the same table and ask the real prototypes whether it still holds.
--- A failure here means the transcription has gone stale, not that the mod is broken:
--- fix test/support/vanilla.lua, then look at whatever the specs concluded from the old
--- values.
local vanilla = require("test.support.vanilla")

---@param names table
local function sorted_keys(names)
    local sorted = {}
    for name in pairs(names) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    return sorted
end

--- Collision masks are dictionaries of layer name to a meaningless `true`, so a sorted
--- list of the keys is the readable form of one.
---@param mask table? a CollisionMask or TileCollisionMask
local function layers_of(mask)
    return sorted_keys(mask and mask.layers or {})
end

--- Which of the claimed names are not in the list the game gave back
---@param claimed string[]
---@param actual string[]
local function missing_from(claimed, actual)
    local present = {}
    for _, name in ipairs(actual) do present[name] = true end
    local missing = {}
    for _, name in ipairs(claimed) do
        if not present[name] then missing[#missing + 1] = name end
    end
    return missing
end

---@param prototypes_list LuaTilePrototype[]?
local function names_of(prototypes_list)
    local names = {}
    for index, prototype in ipairs(prototypes_list or {}) do names[index] = prototype.name end
    return names
end

describe("the collision masks test/support/vanilla.lua transcribes", function()
    for _, name in ipairs(sorted_keys(vanilla.tiles)) do
        local claimed = vanilla.tiles[name]
        test("tile " .. name, function()
            local prototype = prototypes.tile[name]
            assert.is_not_nil(prototype, name .. " is not a tile prototype any more")
            assert.same(sorted_keys(claimed.layers or {}), layers_of(prototype.collision_mask),
                "the collision mask of " .. name .. " is not what the stubs claim")
        end)
    end

    for _, name in ipairs(sorted_keys(vanilla.entities)) do
        local claimed = vanilla.entities[name]
        test("entity " .. name, function()
            local prototype = prototypes.entity[name]
            assert.is_not_nil(prototype, name .. " is not an entity prototype any more")
            assert.same(sorted_keys(claimed.layers or {}), layers_of(prototype.collision_mask),
                "the collision mask of " .. name .. " is not what the stubs claim")
        end)
    end
end)

describe("the tile facts test/support/vanilla.lua transcribes", function()
    for _, name in ipairs(sorted_keys(vanilla.tiles)) do
        local claimed = vanilla.tiles[name]

        test("what places tile " .. name, function()
            local placed_by = names_of(prototypes.tile[name].items_to_place_this)
            if claimed.item then
                assert.equals(claimed.item, placed_by[1],
                    name .. " is placed by " .. tostring(placed_by[1]) ..
                    ", not by " .. claimed.item)
            else
                -- the stubs say no item places this one, which is what makes
                -- empty-space and the like unreachable for a cover tile
                assert.equals(0, #placed_by,
                    name .. " is placed by " .. table.concat(placed_by, ", ") ..
                    ", but the stubs say nothing places it")
            end
        end)

        test("the cover tile of " .. name, function()
            local cover = prototypes.tile[name].default_cover_tile
            if claimed.default_cover then
                assert.is_not_nil(cover, name .. " no longer names a cover tile at all")
                assert.equals(claimed.default_cover, cover.name,
                    name .. " names " .. cover.name .. " as its cover tile, not " ..
                    claimed.default_cover)
            else
                assert.is_nil(cover,
                    name .. " has gained a cover tile the stubs do not know about: " ..
                    tostring(cover and cover.name))
            end
        end)
    end
end)

describe("the tile-placing items test/support/vanilla.lua transcribes", function()
    for _, name in ipairs(sorted_keys(vanilla.items)) do
        local claimed = vanilla.items[name]
        test(name, function()
            local prototype = prototypes.item[name]
            assert.is_not_nil(prototype, name .. " is not an item prototype any more")
            local result = prototype.place_as_tile_result
            assert.is_not_nil(result, name .. " no longer places a tile at all")
            assert.equals(claimed.result, result.result.name,
                name .. " places " .. result.result.name .. ", not " .. claimed.result)
            -- `condition` is an exclusion mask: the target tile must have none of these
            assert.same(sorted_keys(claimed.condition or {}), layers_of(result.condition),
                "the tiles " .. name .. " refuses to go on are not what the stubs claim")
            -- A subset check, unlike the masks above: the stubs carry only the tiles a
            -- spec actually names, where landfill's real list runs to sixteen of them.
            -- Everything claimed still has to be true; the game may know more.
            local actual = names_of(result.tile_condition)
            assert.same({}, missing_from(claimed.tile_condition or {}, actual),
                "the tiles " .. name .. " may go on no longer include everything the " ..
                "stubs claim; the game says " .. table.concat(actual, ", "))
            assert.equals(claimed.invert or false, result.invert,
                "the inversion of " .. name .. "'s tile condition is not what the stubs claim")
        end)
    end
end)
