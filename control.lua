local util = require("util")

---@class (exact) Storage
---@field pipe_lookup PipeLookup
---@field index_rebuilt_tick integer
---@type Storage
storage=storage

--- List of underground creation events this tick
---@type EventData.on_built_entity[]
local new_underground_events = {}

--- Track the item used for triggering end of tick processing
---@type integer
local temp_item_reg_num

--- Lookup table from underground pipe entity to the equivalent pipe entity and item, based on recipes
---@alias PipeLookup table<string, {item:string, entity:string}>
storage.pipe_lookup = storage.pipe_lookup or {}

---Map from underground pipe direction to the locations and directions of neighbors it might connect to by adding a single pipe
---@type { [defines.direction]: { pos: Vector, dir: defines.direction }[] }
local directions_to_neighbors = {
    [defines.direction.north] = { -- for an underground pipe pointing north
        {pos={-1,-1}, dir=defines.direction.east }, -- one space ahead and left, a pipe pointing east would trigger a connection
        {pos={ 0,-2}, dir=defines.direction.south}, -- two spaces ahead, pointing south
        {pos={ 1,-1}, dir=defines.direction.west }, -- one space ahead and right, pointing west
    },
    [defines.direction.east ] = {
        {pos={ 1,-1}, dir=defines.direction.south},
        {pos={ 2, 0}, dir=defines.direction.west },
        {pos={ 1, 1}, dir=defines.direction.north},
    },
    [defines.direction.south] = {
        {pos={ 1, 1}, dir=defines.direction.west },
        {pos={ 0, 2}, dir=defines.direction.north},
        {pos={-1, 1}, dir=defines.direction.east },
    },
    [defines.direction.west ] = {
        {pos={-1, 1}, dir=defines.direction.north},
        {pos={-2, 0}, dir=defines.direction.east },
        {pos={-1,-1}, dir=defines.direction.south},
    },
}

---
---@alias EntityEtc LuaEntity|LuaSurface.create_entity_param.base|LuaSurface.can_place_entity_param|LuaSurface.can_fast_replace_param

---@param entity LuaEntity
---@param position MapPosition
---@return boolean place
local function should_place_based_on_neighbor_fluidbox_prototypes(entity, position)
    local fluidbox = entity.fluidbox
    for i = 1, #fluidbox do
        for _, pipe_connection in pairs( fluidbox.get_pipe_connections(i) ) do
            -- floor operation rounds to nearest 0.5 to mimic pipe connection snapping behavior
            if position[1] == math.floor( ( pipe_connection.target_position.x + 0.25 ) * 2 ) / 2 and
               position[2] == math.floor( ( pipe_connection.target_position.y + 0.25 ) * 2 ) / 2 then
                return true
            end
        end
    end
    return false
end


---@param event EventData.on_built_entity
local function on_built_entity(event)
    if #new_underground_events == 0 then
        -- thanks to boskid, justarandomgeek, PennyJim, Osmo, Quezler, lukā for this trick to postpone processing to the end of the tick
        temp_object = rendering.draw_line{surface=game.players[event.player_index].surface,color={0,0,0},width=0,from={0,0},to={0,0}}
        temp_item_reg_num = script.register_on_object_destroyed(temp_object)
        temp_object.destroy()
    end
    new_underground_events[#new_underground_events+1] = event
end

---@param event EventData.on_built_entity
local function process_built_entity(event)
    local built_underground_entity = event.entity

    if not built_underground_entity then return end
    if not built_underground_entity.valid then return end

    local underground_entity_name --[[@type string]]

    local placing_ghost --[[@type boolean]]
    if built_underground_entity.type == "entity-ghost" then
        placing_ghost = true
        underground_entity_name = built_underground_entity.ghost_name
    else
        placing_ghost = false
        underground_entity_name = built_underground_entity.name
    end

    local pipe_item_and_entity = storage.pipe_lookup[underground_entity_name]
    if not pipe_item_and_entity then return end -- we don't know what pipe goes with this underground pipe, bail out

    local underground_surface = built_underground_entity.surface
    local underground_direction = built_underground_entity.direction
    local underground_position = built_underground_entity.position
    local neighbors_directions = directions_to_neighbors[underground_direction]
    local pipe_position_delta = util.direction_vectors[underground_direction]
    local pipe_item_name = pipe_item_and_entity.item
    local pipe_entity_name = pipe_item_and_entity.entity
    local pipe_position = {
        underground_position.x + pipe_position_delta[1],
        underground_position.y + pipe_position_delta[2]
    }
    if underground_surface.entity_prototype_collides(pipe_entity_name, pipe_position, false) then return end
    local player = game.players[event.player_index]
    local inventory = player.get_main_inventory()
    local pipe_stack

    -- if we don't have any regular pipes in our inventory we want to place a ghost instead
    if not placing_ghost then
        if inventory then
            pipe_stack = inventory.find_item_stack(pipe_item_name)
            placing_ghost = not pipe_stack
        else
            placing_ghost = true
        end
    end

    -- look at the three possible locations for another underground or entity to connect to
    for _, neighbor_candidate in pairs(neighbors_directions) do
        local candidate_pos = {underground_position.x + neighbor_candidate.pos[1], underground_position.y + neighbor_candidate.pos[2]}
        local place = false
        -- first, check for a matching underground pipe
        local neighbor_entity = underground_surface.find_entity( underground_entity_name, candidate_pos )
        if neighbor_entity and neighbor_entity.name == underground_entity_name and neighbor_entity.direction == neighbor_candidate.dir then
            place = true
        end
        if not place then
            -- check for a matching underground pipe ghost
            local neighbor_ghost = underground_surface.find_entity( "entity-ghost", candidate_pos )
            if neighbor_ghost and neighbor_ghost.ghost_name == underground_entity_name and neighbor_ghost.direction == neighbor_candidate.dir then
                place = true
                placing_ghost = true
            end
        end
        if not place then
            -- check for a matching non-pipe entity with a fluidbox connection
            local neighbor_entities = underground_surface.find_entities( { candidate_pos, candidate_pos } )
            for _,entity in pairs(neighbor_entities) do
                if entity.type == "fluid-wagon" or (entity.type == "entity-ghost" and entity.ghost_type == "fluid-wagon") then
                    -- these have fluidbox connections for pumps, but not for pipes
                    goto continue_neighbor_entities
                end
                if  (
                        (
                            entity.type == "entity-ghost" and
                            entity.ghost_type ~= "pipe" and
                            entity.ghost_type ~= "pipe-to-ground"
                        ) or (
                            entity.type ~= "entity-ghost" and
                            entity.type ~= "pipe" and
                            entity.type ~= "pipe-to-ground"
                        )
                    ) and (
                        entity.fluidbox and
                        #entity.fluidbox > 0
                    )
                then
                    if should_place_based_on_neighbor_fluidbox_prototypes(entity, pipe_position) then
                        place = true
                        goto bail_neighbor_entities
                    end
                end
                ::continue_neighbor_entities::
            end
        end
        ::bail_neighbor_entities::
        if place then
            -- found something to connect to!
            -- temporary inventories for swapping with the cursor for placement
            local empty_inv, ghost_inv
            empty_inv = game.create_inventory(1)
            -- this stack will hold the previous cursor contents
            -- swapping straight to main inventory would require manually handling cursor_stack_temporary
            temp_stack = empty_inv[1]
            if placing_ghost then
                ghost_inv = game.create_inventory(1)
                ghost_inv.insert{name=pipe_item_name, count=1}
                pipe_stack = ghost_inv[1]
            end
            temp_stack_temp = player.cursor_stack_temporary
            local hand_location = player.hand_location
            player.cursor_stack.swap_stack(temp_stack)
            player.cursor_stack.swap_stack(pipe_stack)
            if not placing_ghost and player.can_build_from_cursor{position=pipe_position} then
                player.build_from_cursor{position=pipe_position}
            else
                player.build_from_cursor{position=pipe_position, build_mode=defines.build_mode.forced}
            end
            player.cursor_stack.swap_stack(pipe_stack)
            player.cursor_stack.swap_stack(temp_stack)
            player.hand_location = hand_location
            player.cursor_stack_temporary = temp_stack_temp
            empty_inv.destroy()
            if ghost_inv then ghost_inv.destroy() end
            -- no need to check other potential neighbors
            break
        end
    end
end

--- Find recipes that produce underground pipes to match them to pipes, save results to `global.pipe_lookup`
local function rebuild_index()
    -- TODO recursively search through ingredient recipes to find pipe->X->Y->Z->underground like SchallPipeScaling
    -- TODO handle undergrounds with multiple recipes or multiple ingredients per recipe
    if storage.index_rebuilt_tick == game.tick then
        return
    end
    storage.index_rebuilt_tick = game.tick
    local underground_recipe_prototypes = prototypes.get_recipe_filtered(
        {
            {filter="has-product-item",elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe-to-ground"}}}}},
            {mode="and",filter="has-ingredient-item",elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe"}}}}}
        }
    )
    for _, underground_recipe_prototype in pairs(underground_recipe_prototypes) do
        local underground_entity_name --[[@type string]]
        local pipe_item_name --[[@type string]]
        local pipe_entity_name --[[@type string]]
        -- Find the entity for the first recipe product that is a pipe-to-ground
        for _, product in pairs(underground_recipe_prototype.products) do
            local result = product.type == "item" and prototypes.item[product.name].place_result
            if result and prototypes.entity[result.name].type == "pipe-to-ground" then
                underground_entity_name = result.name
                break
            end
        end
        if underground_entity_name == nil then goto continue_underground_recipe_prototype end
        -- Find the entity and item for the first recipe ingredient that is a pipe
        for _, ingredient in pairs(underground_recipe_prototype.ingredients) do
            local result = ingredient.type == "item" and prototypes.item[ingredient.name].place_result
            if result and prototypes.entity[result.name].type == "pipe" then
                pipe_item_name = ingredient.name
                pipe_entity_name = result.name
                break
            end
        end
        if underground_entity_name and pipe_item_name and pipe_entity_name then
            -- Remember that when this underground entity is placed, this pipe item and entity are the ones to use
            storage.pipe_lookup[underground_entity_name] = {item = pipe_item_name, entity = pipe_entity_name}
        end
        ::continue_underground_recipe_prototype::
    end
end

---@param event EventData.on_object_destroyed
local function on_object_destroyed(event)
    if event.registration_number == temp_item_reg_num then
        for i,e in pairs(new_underground_events) do
            process_built_entity(e)
        end
        new_underground_events = {}
    end
end

script.on_init(rebuild_index)
script.on_configuration_changed(rebuild_index)

--- Filters out extra fields in the item_pipe and makes sure the references are valid entities and item
---@param underground string
---@param item_pipe {item:string, entity:string}
---@return {item:string, entity:string} item_pipe Has been filtered of extra fields
local function validate_connector(underground, item_pipe)
    -- Filter out the extra fields
    item_pipe = {item = item_pipe.item, entity = item_pipe.entity}
    local underground_prototype = prototypes.entity[underground]
    local pipe_prototype = prototypes.entity[item_pipe.entity]

    ---@type table<string, true>
    local pipe_items = {}
    for _, stack in pairs(pipe_prototype.items_to_place_this) do
        pipe_items[stack.name] = true
    end

    if not pipe_items[item_pipe.item] -- The item needs to be able to place the pipe
    or not prototypes.item[item_pipe.item] -- The item needs to exist (theoretically we can skip this since it was in an items_to_place_this)
    or not pipe_prototype or pipe_prototype.type ~= "pipe" -- The pipe needs to be an actual pipe
    or not underground_prototype or underground_prototype.type ~= "pipe-to-ground" then -- The underground needs to be an actual underground
        error("Given underground and pipe are not valid: "..underground.." -> "..serpent.line(item_pipe))
    end

    return item_pipe
end

remote.add_interface("automatic-underground-pipe-connectors", {
    --- Allows mods to see what undergrounds are considered
    ---@return PipeLookup
    get_undergrounds = function()
        return storage.pipe_lookup
    end,
    --- Allows mods to completely overwrite undergrounds
    ---@param new_lookup PipeLookup
    set_undergrounds = function(new_lookup)
        -- To make sure the new lookup is valid
        for underground, item_pipe in pairs(new_lookup) do
            new_lookup[underground] = validate_connector(underground, item_pipe)
        end

        storage.pipe_lookup = new_lookup
    end,
    --- Allows mods to add underground and pipe connections for when they don't follow the expected recipe pattern.
    ---@param new_undergrounds PipeLookup
    add_undergrounds = function(new_undergrounds)
        for underground, item_pipe in pairs(new_undergrounds) do
            storage.pipe_lookup[underground] = validate_connector(underground, item_pipe)
        end
    end,
    --- Allows mods to remove undergrounds just in case
    ---@param old_undergrounds string[]
    remove_undergrounds = function(old_undergrounds)
        for _, underground in pairs(old_undergrounds) do
            if storage.pipe_lookup[underground] then
                log("Removing the pipe for '"..underground.."'")
                storage.pipe_lookup[underground] = nil
            end
        end
    end,
})

script.on_event(defines.events.on_built_entity, on_built_entity, {{filter="type",type="pipe-to-ground"},{filter="ghost_type",type="pipe-to-ground"}})
script.on_event(defines.events.on_object_destroyed, on_object_destroyed)
