-- underground pipe neighbor lookup table
-- keys are underground pipe directions
-- values describe the possible relative locations and directions of another to connect to

---@type table<integer, { pos: Vector, dir: defines.direction }[]>
local direction_to_neighbors = {
    [defines.direction.north] = { -- for an underground pipe pointing north
        {pos={-1,-1}, dir=defines.direction.east }, -- one space ahead and left
        {pos={ 0,-2}, dir=defines.direction.south}, -- two spaces ahead
        {pos={ 1,-1}, dir=defines.direction.west }, -- one space ahead and right
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

--- x and y offsets to move one step in the given direction
---@type table<defines.direction, Vector>
local direction_to_delta = {
    [defines.direction.north] = { 0, -1},
    [defines.direction.east ] = { 1,  0},
    [defines.direction.south] = { 0,  1},
    [defines.direction.west ] = {-1,  0},
}

---@param event EventData.on_built_entity
local function on_built_entity(event)
    -- locals for efficient repeat access
    local underground_entity = event.created_entity
    local underground_name
    local ghost = false
    if underground_entity.type == "entity-ghost" then
        ghost = true
        underground_name = underground_entity.ghost_name
    else
        underground_name = underground_entity.name
    end
    local pipe_lookup = global.pipe_lookup[underground_name]
    if not pipe_lookup then return end -- we don't know what pipe goes with this underground pipe

    local underground_surface = underground_entity.surface
    local underground_direction = underground_entity.direction
    local underground_position = underground_entity.position
    local neighbor_info = direction_to_neighbors[underground_direction]
    local pipe_position = direction_to_delta[underground_direction]
    local pipe_item_name = pipe_lookup[1]
    local pipe_entity_name = pipe_lookup[2]

    -- if we don't have any regular pipes in our inventory we want to place a ghost instead
    if not ghost and not game.players[event.player_index].get_main_inventory().find_item_stack(pipe_item_name) then
        ghost = true;
    end

    ---@class EntityEtc: LuaEntity, LuaSurface.create_entity_param.base, LuaSurface.can_place_entity_param, LuaSurface.can_fast_replace_param
    ---@type EntityEtc
    local pipe_entity_definition = {
        name = ghost and "entity-ghost" or pipe_entity_name,
        position = {underground_position.x + pipe_position[1], underground_position.y + pipe_position[2]},

        -- properties just for create_entity
        force = underground_entity.force,
        last_user = underground_entity.last_user,
        raise_built = true,
        create_build_effect_smoke = true,
        spawn_decorations = true,

        -- properties just for can_place_entity
        build_check_type = ghost and defines.build_check_type.script_ghost or defines.build_check_type.manual,
    }
    if ghost then
        pipe_entity_definition.inner_name = pipe_entity_name
    end

    if not underground_surface.can_place_entity(pipe_entity_definition) then
        -- bail out because we can't place a pipe, could be blocked or a fluid mixing violation
        return
    end

    if ghost and #underground_surface.find_entities( {pipe_entity_definition.position,pipe_entity_definition.position} ) > 0 then
        -- bail out because there's already something where we'd place a ghost
        return
    end

    if underground_surface.can_fast_replace(pipe_entity_definition) then
        local ghost = underground_surface.find_entity("entity-ghost", pipe_entity_definition.position)
        if ghost and ghost.ghost_name == pipe_entity_name then
            -- don't bail out, matching ghost is ok to replace
        else
            -- bail out because there's something here our pipe would fast replace
            return
        end
    end

    -- look at the three possible locations for another underground to connect to
    for _, neighbor_candidate in pairs(neighbor_info) do
        local candidate_pos = {underground_position.x + neighbor_candidate.pos[1], underground_position.y + neighbor_candidate.pos[2]}
        local place = false
        -- first, check for a matching underground pipe
        local neighbor_entity = underground_surface.find_entity( underground_name, candidate_pos )
        if neighbor_entity and neighbor_entity.name == underground_name and neighbor_entity.direction == neighbor_candidate.dir then
            place = true
        end
        local neighbor_ghost
        if ghost and not place then
            -- check for a matching underground pipe ghost
            neighbor_ghost = underground_surface.find_entity( "entity-ghost", candidate_pos )
        end
        if neighbor_ghost and neighbor_ghost.ghost_name == underground_name and neighbor_ghost.direction == neighbor_candidate.dir then
            place = true
        end
        if not place then
            -- check for a matching other entity with a fluidbox connection
            local neighbor_entities = underground_surface.find_entities( { candidate_pos, candidate_pos } )
            for _,entity in pairs(neighbor_entities) do
                if entity.type ~= "pipe" and entity.type ~= "pipe-to-ground" and entity.fluidbox and #entity.fluidbox > 0 then
                    ---@type uint
                    for i = 1, #entity.fluidbox do
                        if entity.type == "fluid-wagon" or (entity.type == "fluid-turret" and i > 1) then
                            break
                        end
                        local prototypes = entity.fluidbox.get_prototype(i)
                        if #prototypes == 0 then
                            prototypes = {prototypes}
                        end
                        for _,prototype in pairs(prototypes) do
                            for _,pipe_connection in pairs(prototype.pipe_connections) do
                                local position = pipe_connection.positions[( entity.direction / 2 ) + 1]
                                if entity.position.x + position.x == pipe_entity_definition.position[1] and entity.position.y + position.y == pipe_entity_definition.position[2] then
                                    place = true
                                    goto bail_neighbor_entities
                                end
                            end
                        end
                    end
                end
            end
        end
        ::bail_neighbor_entities::
        if place then
            -- found something to connect to
            if ghost or game.players[event.player_index].get_main_inventory().find_item_stack(pipe_item_name) then
                -- we're placing a ghost or have a pipe in inventory
                if not ghost then
                    -- spend the pipe from inventory
                    game.players[event.player_index].get_main_inventory().remove({name=pipe_item_name})
                end
                -- to place the pipe or ghost entity
                underground_surface.create_entity(pipe_entity_definition)
            end
            break
        end
    end
end

---@type table<string, string[]>
global.pipe_lookup = global.pipe_lookup or {}

--- Find recipes that produce underground pipes, try to figure out which pipe they belong with, save results to global lookup table
local function rebuild_index()
    --TODO recursively search through ingredient recipes to find pipe->X->Y->Z->underground like SchallPipeScaling
    --TODO handle undergrounds with multiple recipes or multiple ingredients per recipe
    local underground_recipe_prototypes = game.get_filtered_recipe_prototypes(
        {
            {filter="has-product-item",elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe-to-ground"}}}}},
            {mode="and",filter="has-ingredient-item",elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe"}}}}}
        }
    )
    for _, urp_prototype in pairs(underground_recipe_prototypes) do
        local underground_entity_name, pipe_item_name, pipe_entity_name
        for _, product in pairs(urp_prototype.products) do
            if product.type == "item" and game.item_prototypes[product.name].place_result and game.entity_prototypes[game.item_prototypes[product.name].place_result.name].type == "pipe-to-ground" then
                underground_entity_name = game.item_prototypes[product.name].place_result.name
            end
        end
        for _, ingredient in pairs(urp_prototype.ingredients) do
            if ingredient.type == "item" and game.item_prototypes[ingredient.name].place_result and game.entity_prototypes[game.item_prototypes[ingredient.name].place_result.name].type == "pipe" then
                pipe_item_name = ingredient.name
                pipe_entity_name = game.item_prototypes[ingredient.name].place_result.name
            end
        end
        if underground_entity_name and pipe_item_name and pipe_entity_name then
            global.pipe_lookup[underground_entity_name] = {pipe_item_name, pipe_entity_name}
        end
    end
end

script.on_init(rebuild_index)
script.on_configuration_changed(rebuild_index)

script.on_event(defines.events.on_built_entity, on_built_entity, {{filter="type",type="pipe-to-ground"},{filter="ghost_type",type="pipe-to-ground"}})
