--- Whether two things can share a space, asked of their collision masks.
local collision = {}

--- Do these masks share a layer? Two things collide only where their layers meet,
--- so no shared layer means they can occupy the same tile.
---@param mask CollisionMask
---@param other_mask CollisionMask
---@return boolean
local function masks_intersect(mask, other_mask)
    local other_layers = other_mask.layers
    for layer in pairs(mask.layers) do
        if other_layers[layer] then return true end
    end
    return false
end

--- Is this entity in the way of something we want to build here? A ghost answers for
--- the entity it would become, since that is what would eventually share the space.
--- Anything we cannot read a mask off is treated as being in the way, so an unknown
--- makes the guard more cautious rather than less.
---@param found_entity LuaEntity
---@param entity_prototype LuaEntityPrototype what we are trying to put here
---@return boolean
local function entity_blocks(found_entity, entity_prototype)
    local prototype = found_entity.type == "entity-ghost"
        and found_entity.ghost_prototype or found_entity.prototype
    if not prototype or not prototype.collision_mask then return true end
    return masks_intersect(prototype.collision_mask, entity_prototype.collision_mask)
end

collision.masks_intersect = masks_intersect
collision.entity_blocks = entity_blocks

return collision
