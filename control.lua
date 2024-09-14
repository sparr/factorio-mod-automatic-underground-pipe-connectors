local util = require("util")

---@class (exact) Global
---@field pipe_lookup PipeLookup
---@type Global
global=global

--- Lookup table from underground pipe entity to the equivalent pipe entity and item, based on recipes
---@alias PipeLookup table<string, {item:string, entity:string}>
global.pipe_lookup = global.pipe_lookup or {}

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
---@param fluidbox_prototypes LuaFluidBoxPrototype[]
---@param pipe_entity_definition EntityEtc
---@return boolean place
local function should_place_based_on_neighbor_fluidbox_prototypes(entity, pipe_entity_definition, fluidbox_prototypes)
    for _,prototype in pairs(fluidbox_prototypes) do
        for _,pipe_connection in pairs(prototype.pipe_connections) do
            local position = pipe_connection.positions[( entity.direction / 2 ) + 1]
            if entity.position.x + position.x == pipe_entity_definition.position[1] and entity.position.y + position.y == pipe_entity_definition.position[2] then
                -- this neighbor has a fluidbox connection we can connect to
                return true
            end
        end
    end
    return false
end


---@param event EventData.on_built_entity
local function on_built_entity(event)
    local built_underground_entity = event.created_entity
    local underground_entity_name --[[@type string]]

    local placing_ghost --[[@type boolean]]
    if built_underground_entity.type == "entity-ghost" then
        placing_ghost = true
        underground_entity_name = built_underground_entity.ghost_name
    else
        placing_ghost = false
        underground_entity_name = built_underground_entity.name
    end

    local pipe_item_and_entity = global.pipe_lookup[underground_entity_name]
    if not pipe_item_and_entity then return end -- we don't know what pipe goes with this underground pipe, bail out

    local underground_surface = built_underground_entity.surface
    local underground_direction = built_underground_entity.direction
    local underground_position = built_underground_entity.position
    local neighbors_directions = directions_to_neighbors[underground_direction]
    local pipe_position_delta = util.direction_vectors[underground_direction]
    local pipe_item_name = pipe_item_and_entity.item
    local pipe_entity_name = pipe_item_and_entity.entity

    -- if we don't have any regular pipes in our inventory we want to place a ghost instead
    if not placing_ghost then
        placing_ghost = not game.players[event.player_index].get_main_inventory().find_item_stack(pipe_item_name)
    end

    ---@type EntityEtc
    local pipe_entity_definition = {
        name = placing_ghost and "entity-ghost" or pipe_entity_name,
        position = {underground_position.x + pipe_position_delta[1], underground_position.y + pipe_position_delta[2]},

        -- properties just for create_entity
        force = built_underground_entity.force,
        last_user = built_underground_entity.last_user,
        raise_built = true,
        create_build_effect_smoke = true,
        spawn_decorations = true,

        -- properties just for can_place_entity
        build_check_type = placing_ghost and defines.build_check_type.script_ghost or defines.build_check_type.manual,
    }
    if placing_ghost then
        pipe_entity_definition.inner_name = pipe_entity_name
    end

    if not underground_surface.can_place_entity(pipe_entity_definition --[[@as LuaSurface.can_place_entity_param]]) then
        -- bail out because we can't place a pipe, could be blocked or a fluid mixing violation
        return
    end

    if placing_ghost and #underground_surface.find_entities( {pipe_entity_definition.position,pipe_entity_definition.position} ) > 0 then
        -- bail out because there's already something where we'd place a ghost
        return
    end

    if underground_surface.can_fast_replace(pipe_entity_definition --[[@as LuaSurface.can_fast_replace_param]]) then
        local ghost = underground_surface.find_entity("entity-ghost", pipe_entity_definition.position)
        if ghost and ghost.ghost_name == pipe_entity_name then
            -- don't bail out, matching ghost is ok to replace
        else
            -- bail out because there's something here our pipe would fast replace
            return
        end
    end

    -- look at the three possible locations for another underground to connect to
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
            -- check for a matching other entity with a fluidbox connection
            local neighbor_entities = underground_surface.find_entities( { candidate_pos, candidate_pos } )
            for _,entity in pairs(neighbor_entities) do
                if entity.type == "fluid-wagon" or (entity.type == "entity-ghost" and entity.ghost_type == "fluid-wagon") then
                    goto continue_neighbor_entities
                end
                if entity.type == "entity-ghost" then
                    if entity.ghost_type ~= "pipe" and entity.ghost_type ~= "pipe-to-ground" and #entity.ghost_prototype.fluidbox_prototypes > 0 then
                        ---@type uint
                        for i = 1, #entity.ghost_prototype.fluidbox_prototypes do
                            if entity.ghost_type == "fluid-turret" and i > 1 then
                                break
                            end
                            local prototypes = {entity.ghost_prototype.fluidbox_prototypes[i]}
                            if should_place_based_on_neighbor_fluidbox_prototypes(entity, pipe_entity_definition, prototypes) then
                                place = true
                                goto bail_neighbor_entities
                            end
                        end
                    end
                else
                    if entity.type ~= "pipe" and entity.type ~= "pipe-to-ground" and entity.fluidbox and #entity.fluidbox > 0 then
                        ---@type uint
                        for i = 1, #entity.fluidbox do
                            if entity.type == "fluid-turret" and i > 1 then
                                break
                            end
                            local prototypes = entity.fluidbox.get_prototype(i)
                            if #prototypes == 0 then
                                prototypes = {prototypes}
                            end
                            if should_place_based_on_neighbor_fluidbox_prototypes(entity, pipe_entity_definition, prototypes) then
                                place = true
                                goto bail_neighbor_entities
                            end
                        end
                    end
                end
                ::continue_neighbor_entities::
            end
        end
        ::bail_neighbor_entities::
        if place then
            -- found something to connect to!
            if not placing_ghost then
                -- we ensured above that placing_ghost is true xor we have the necessary item to remove from inventory
                game.players[event.player_index].get_main_inventory().remove({name=pipe_item_name})
            end
            -- place the pipe or ghost entity
            underground_surface.create_entity(pipe_entity_definition --[[@as LuaSurface.create_entity_param]])
            -- no need to check other potential neighbors
            break
        end
    end
end

--- Find recipes that produce underground pipes to match them to pipes, save results to `global.pipe_lookup`
local function rebuild_index()
    -- TODO recursively search through ingredient recipes to find pipe->X->Y->Z->underground like SchallPipeScaling
    -- TODO handle undergrounds with multiple recipes or multiple ingredients per recipe
    local underground_recipe_prototypes = game.get_filtered_recipe_prototypes(
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
            if product.type == "item" and game.item_prototypes[product.name].place_result and game.entity_prototypes[game.item_prototypes[product.name].place_result.name].type == "pipe-to-ground" then
                underground_entity_name = game.item_prototypes[product.name].place_result.name
                break
            end
        end
        if underground_entity_name == nil then goto continue_underground_recipe_prototype end
        -- Find the entity and item for the first recipe ingredient that is a pipe
        for _, ingredient in pairs(underground_recipe_prototype.ingredients) do
            if ingredient.type == "item" and game.item_prototypes[ingredient.name].place_result and game.entity_prototypes[game.item_prototypes[ingredient.name].place_result.name].type == "pipe" then
                pipe_item_name = ingredient.name
                pipe_entity_name = game.item_prototypes[ingredient.name].place_result.name
                break
            end
        end
        if underground_entity_name and pipe_item_name and pipe_entity_name then
            -- Remember that when this underground entity is placed, this pipe item and entity are the ones to use
            global.pipe_lookup[underground_entity_name] = {item = pipe_item_name, entity = pipe_entity_name}
        end
        ::continue_underground_recipe_prototype::
    end
end

script.on_init(rebuild_index)
script.on_configuration_changed(rebuild_index)

script.on_event(defines.events.on_built_entity, on_built_entity, {{filter="type",type="pipe-to-ground"},{filter="ghost_type",type="pipe-to-ground"}})
