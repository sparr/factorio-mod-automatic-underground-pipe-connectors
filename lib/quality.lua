--- Choosing which quality of an item to spend.
local quality = {}

--- The quality to fall back on when the player has none of the one they placed.
--- Nearest by quality level, and on a tie the lower one, so the player keeps their
--- better items back for something that needs them. Any remaining tie goes to the
--- lower name, which only two qualities sharing a level can produce, so that every
--- client in a multiplayer game picks the same stack.
---@param available table<string, uint32> quality name to count, as get_item_quality_counts gives
---@param target_level uint32 level of the quality the player actually placed
---@return string? quality_name nil when the player has none of the item at all
local function nearest_available(available, target_level)
    local best_name --[[@type string?]]
    local best_distance --[[@type uint32]]
    local best_level --[[@type uint32]]
    for quality_name, count in pairs(available) do
        if count > 0 then
            local level = prototypes.quality[quality_name].level
            local distance = math.abs(level - target_level)
            if not best_name
            or distance < best_distance
            or (distance == best_distance and level < best_level)
            or (distance == best_distance and level == best_level and quality_name < best_name) then
                best_name, best_distance, best_level = quality_name, distance, level
            end
        end
    end
    return best_name
end

--- A stack of `item_name` to spend on something placed at `placed_quality`.
--- The matching quality always wins when the player has one. Reaching for another
--- quality is the player's choice, so it only happens when `substitute` says so.
---@param inventory LuaInventory
---@param item_name string
---@param placed_quality LuaQualityPrototype
---@param substitute boolean whether the player allows spending a different quality
---@return LuaItemStack? stack nil when there is nothing the player is willing to spend
local function find_stack_to_spend(inventory, item_name, placed_quality, substitute)
    local stack = inventory.find_item_stack{ name = item_name, quality = placed_quality }
    if stack then return stack end
    if not substitute then return nil end
    local nearest = nearest_available(
        inventory.get_item_quality_counts(item_name), placed_quality.level)
    if not nearest then return nil end
    return inventory.find_item_stack{ name = item_name, quality = nearest }
end

quality.nearest_available = nearest_available
quality.find_stack_to_spend = find_stack_to_spend

return quality
