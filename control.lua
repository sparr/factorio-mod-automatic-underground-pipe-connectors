-- underground pipe neighbor lookup table
-- keys are underground pipe directions
-- values describe the possible relative locations and directions of another to connect to
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

-- x and y offsets to move one step in the given direction
local direction_to_delta = {
    [defines.direction.north] = { 0, -1},
    [defines.direction.east ] = { 1,  0},
    [defines.direction.south] = { 0,  1},
    [defines.direction.west ] = {-1,  0},
}

function on_built_entity(event)
    -- locals for efficient repeat access
    local underground_entity = event.created_entity
    local underground_name = underground_entity.name
    local underground_direction = underground_entity.direction
    local underground_position = underground_entity.position
    local neighbor_info = direction_to_neighbors[underground_direction]
    local pipe_lookup = global.pipe_lookup[underground_name]
    local pipe_position = direction_to_delta[underground_direction]

    local pipe_entity_definition = {
        name = pipe_lookup[2],
        position = {underground_position.x + pipe_position[1], underground_position.y + pipe_position[2]},

        -- properties just for create_entity
        force = underground_entity.force,
        last_user = underground_entity.last_user,
        raise_built = true,
        create_build_effect_smoke = true,
        spawn_decorations = true,

        -- properties just for can_place_entity
        build_check_type = defines.build_check_type.manual,
    }

    -- bail out if we can't place a pipe, could be blocked or a fluid mixing violation
    if not underground_entity.surface.can_place_entity(pipe_entity_definition) then return end

    -- look at the three possible locations for another underground to connect to
    for _, neighbor_candidate in pairs(neighbor_info) do
        local neighbor_entity = underground_entity.surface.find_entity(
            underground_name,
            {underground_position.x + neighbor_candidate.pos[1], underground_position.y + neighbor_candidate.pos[2]}
        )
        if neighbor_entity and neighbor_entity.direction == neighbor_candidate.dir then
            -- found one in the right place and direction
            if game.players[event.player_index].get_main_inventory().find_item_stack(pipe_lookup[1]) then
                -- we have a pipe in inventory, so spend it
                game.players[event.player_index].get_main_inventory().remove({name=pipe_lookup[1]})
                -- to place the pipe entity
                underground_entity.surface.create_entity(pipe_entity_definition)
            end
            break
        end
    end
end

global.pipe_lookup = global.pipe_lookup or {}

-- Find recipes that produce underground pipes and try to figure out which pipe they belong with
function rebuild_index()
    local underground_recipe_prototypes = game.get_filtered_recipe_prototypes({{filter="has-product-item",elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe-to-ground"}}}}},{filter="has-ingredient-item",mode="and",elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe"}}}}}})
    for _, urp_prototype in pairs(underground_recipe_prototypes) do
        local underground_entity_name, pipe_item_name, pipe_entity_name
        for _, product in pairs(urp_prototype.products) do
            if game.entity_prototypes[game.item_prototypes[product.name].place_result.name].type == "pipe-to-ground" then
                underground_entity_name = game.item_prototypes[product.name].place_result.name
            end
        end
        for _, ingredient in pairs(urp_prototype.ingredients) do
            if game.item_prototypes[ingredient.name].place_result and game.entity_prototypes[game.item_prototypes[ingredient.name].place_result.name].type == "pipe" then
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

script.on_event(defines.events.on_built_entity, on_built_entity, {{filter="type",type="pipe-to-ground"}})