local neighbor_lookup = {
    [defines.direction.north] = { neighbors={
            {pos={-1,-1},dir=defines.direction.east },
            {pos={ 0,-2},dir=defines.direction.south},
            {pos={ 1,-1},dir=defines.direction.west },
        }, connect={ 0,-1} },
    [defines.direction.east ] = { neighbors={
            {pos={ 1,-1},dir=defines.direction.south},
            {pos={ 2, 0},dir=defines.direction.west },
            {pos={ 1, 1},dir=defines.direction.north},
        }, connect={ 1, 0} },
    [defines.direction.south] = { neighbors={
            {pos={ 1, 1},dir=defines.direction.west },
            {pos={ 0, 2},dir=defines.direction.north},
            {pos={-1, 1},dir=defines.direction.east },
        }, connect={ 0, 1} },
    [defines.direction.west ] = { neighbors={
            {pos={-1, 1},dir=defines.direction.north},
            {pos={-2, 0},dir=defines.direction.east },
            {pos={-1,-1},dir=defines.direction.south},
        }, connect={-1, 0} },
}

function on_built_entity(event)
    local underground_entity = event.created_entity
    local underground_name = underground_entity.name
    local underground_direction = underground_entity.direction
    local underground_position = underground_entity.position

    -- bail out if there's already something where we would put a pipe
    local connect = neighbor_lookup[underground_direction].connect
    local blocking_entity = underground_entity.surface.find_entities(
        {{underground_position.x + connect[1] - 0.5, underground_position.y + connect[2] - 0.5},
         {underground_position.x + connect[1] + 0.5, underground_position.y + connect[2] + 0.5}}
    )
    if #blocking_entity > 0 then return end
    -- look at the three possible locations for another underground to connect to
    local neighbor_candidates = neighbor_lookup[underground_direction].neighbors
    for _, neighbor_candidate in pairs(neighbor_candidates) do
        local neighbor_entity = underground_entity.surface.find_entity(
            underground_name,
            {underground_position.x + neighbor_candidate.pos[1], underground_position.y + neighbor_candidate.pos[2]}
        )
        if neighbor_entity and neighbor_entity.direction == neighbor_candidate.dir then
            local lookup = global.pipe_lookup[underground_name]
            -- found one in the right place and direction
            if game.players[event.player_index].get_main_inventory().find_item_stack(lookup[1]) then
                -- we have a pipe in inventory, so spend it
                game.players[event.player_index].get_main_inventory().remove({name=lookup[1]})
                -- to place the pipe entity
                underground_entity.surface.create_entity{
                    name = lookup[2],
                    position = {underground_position.x + connect[1], underground_position.y + connect[2]}
                }
            end
            break
        end
    end
end

global.pipe_lookup = global.pipe_lookup or {}

-- Find recipes that produce underground pipes and try to figure out which pipe they belong with
function rebuild_index()
    local underground_recipe_prototypes = game.get_filtered_recipe_prototypes({{filter="has-product-item",elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe-to-ground"}}}}},{filter="has-ingredient-item",mode="and",elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe"}}}}}})
    for urp_name, urp_prototype in pairs(underground_recipe_prototypes) do
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