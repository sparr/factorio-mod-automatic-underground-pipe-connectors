local collision = require("lib.collision")

-- core/lualib/collision-mask-defaults.lua
local function mask(...)
    local layers = {}
    for _, layer in ipairs({ ... }) do layers[layer] = true end
    return { layers = layers }
end

-- building(), which is what a pipe gets
local PIPE = { collision_mask = mask("item", "meltable", "object", "player",
                                     "water_tile", "is_object", "is_lower_object") }
-- elevated_rail(), the whole mask for every elevated rail piece
local ELEVATED_RAIL = { collision_mask = mask("elevated_rail") }
-- containers use building_unheated, so no meltable, but they still take the ground
local CHEST = { collision_mask = mask("item", "object", "player", "water_tile",
                                      "is_object", "is_lower_object") }
-- rail supports do sit on the ground, unlike the rails they carry
local RAIL_SUPPORT = { collision_mask = mask("object", "rail", "rail_support",
                                             "is_lower_object", "is_object") }

describe("masks_intersect", function()
    it("finds nothing in common between a pipe and an elevated rail", function()
        assert.is_false(collision.masks_intersect(
            ELEVATED_RAIL.collision_mask, PIPE.collision_mask))
    end)

    it("sees a chest taking the same ground as the pipe", function()
        assert.is_true(collision.masks_intersect(CHEST.collision_mask, PIPE.collision_mask))
    end)

    it("sees a rail support taking the ground, unlike the rail above it", function()
        assert.is_true(collision.masks_intersect(RAIL_SUPPORT.collision_mask, PIPE.collision_mask))
    end)

    it("is symmetric", function()
        assert.is_true(collision.masks_intersect(PIPE.collision_mask, CHEST.collision_mask))
        assert.is_false(collision.masks_intersect(PIPE.collision_mask, ELEVATED_RAIL.collision_mask))
    end)

    it("treats an empty mask as colliding with nothing", function()
        assert.is_false(collision.masks_intersect(mask(), PIPE.collision_mask))
        assert.is_false(collision.masks_intersect(PIPE.collision_mask, mask()))
    end)
end)

describe("entity_blocks", function()
    it("lets the pipe through under an elevated rail", function()
        assert.is_false(collision.entity_blocks(
            { type = "elevated-straight-rail", prototype = ELEVATED_RAIL }, PIPE))
    end)

    -- the shape behind the Nullius wind turbine report: nothing a pipe collides with
    it("lets the pipe through under anything sharing no layer with it", function()
        local overhead = { collision_mask = mask("elevated_rail", "rail") }
        assert.is_false(collision.entity_blocks(
            { type = "nullius-wind-turbine", prototype = overhead }, PIPE))
    end)

    it("still refuses a chest on the gap", function()
        assert.is_true(collision.entity_blocks({ type = "container", prototype = CHEST }, PIPE))
    end)

    it("asks a ghost about the entity it would become", function()
        assert.is_false(collision.entity_blocks(
            { type = "entity-ghost", ghost_prototype = ELEVATED_RAIL, prototype = CHEST }, PIPE))
        assert.is_true(collision.entity_blocks(
            { type = "entity-ghost", ghost_prototype = CHEST, prototype = ELEVATED_RAIL }, PIPE))
    end)

    it("treats an unreadable prototype as being in the way", function()
        assert.is_true(collision.entity_blocks({ type = "mystery" }, PIPE))
        assert.is_true(collision.entity_blocks({ type = "mystery", prototype = {} }, PIPE))
    end)
end)
