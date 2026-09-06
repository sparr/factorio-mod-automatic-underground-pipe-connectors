--- Choosing which pipe belongs with an underground pipe.
local neighbors = require("lib.neighbors")

local pipes = {}

--- Could a thing carrying these connection categories join one carrying those?
--- Permissive when either side declares none, the same way the neighbour search
--- treats them, so mods that never mention categories behave as they always did.
---@param categories table<string, true>
---@param other_categories table<string, true>
---@return boolean
local function categories_compatible(categories, other_categories)
    if not next(categories) or not next(other_categories) then return true end
    for category in pairs(categories) do
        if other_categories[category] then return true end
    end
    return false
end

--- Do these two actually name a category in common? Unlike categories_compatible,
--- declaring nothing is not a match here. Reaching past the recipe is a guess, and
--- only a category the underground actually names is evidence worth guessing on.
---@param categories table<string, true>
---@param other_categories table<string, true>
---@return boolean
local function shares_category(categories, other_categories)
    for category in pairs(categories) do
        if other_categories[category] then return true end
    end
    return false
end

--- Any pipe in the game that names one of this underground's categories, lowest name
--- first so every client agrees. Only worth asking when the recipe offers nothing that
--- fits, which means the underground named a category and no candidate answered it.
---@param underground_categories table<string, true>
---@return { item: string, entity: string }?
local function compatible_pipe_anywhere(underground_categories)
    local best
    for name, prototype in pairs(prototypes.get_entity_filtered{{ filter = "type", type = "pipe" }}) do
        local stack = prototype.items_to_place_this and prototype.items_to_place_this[1]
        if stack and (not best or name < best.entity)
        and shares_category(underground_categories, neighbors.pipe_connection_categories(name))
        then
            best = { item = stack.name, entity = name }
        end
    end
    return best
end

--- Pick the pipe to pair with an underground, given what its recipe offers in order.
---
--- The first pipe in the recipe is usually right, but not always: Advanced Fluid
--- Handling's tiered undergrounds take a plain vanilla pipe as a component, and under
--- Pyanodons a plain pipe cannot join them at all, because Py gives its niobium pipes
--- a connection category of their own. So prefer a candidate that could actually
--- connect, and when the recipe offers none, take any pipe in the game that could.
--- Falling back to the first candidate keeps every mod that says nothing about
--- categories exactly where it was.
---@param underground_entity_name string
---@param candidates { item: string, entity: string }[] in recipe order
---@return { item: string, entity: string }?
local function choose(underground_entity_name, candidates)
    -- no pipe in the recipe is no pipe: this is not the place to invent a pairing
    if #candidates == 0 then return nil end
    local underground_categories = neighbors.pipe_connection_categories(underground_entity_name)
    for _, candidate in ipairs(candidates) do
        if categories_compatible(
            underground_categories, neighbors.pipe_connection_categories(candidate.entity))
        then
            return candidate
        end
    end
    return compatible_pipe_anywhere(underground_categories) or candidates[1]
end

pipes.categories_compatible = categories_compatible
pipes.shares_category = shares_category
pipes.compatible_pipe_anywhere = compatible_pipe_anywhere
pipes.choose = choose

return pipes
