--- Finding the thing a newly placed underground pipe ought to connect to.
local neighbors = {}

---Map from underground pipe direction to the locations and directions of neighbors
---it might connect to by adding a single pipe
---@type { [defines.direction]: { pos: Vector, dir: defines.direction }[] }
local directions_to_neighbors = {
    [defines.direction.north] = { -- for an underground pipe pointing north
        -- a pipe at one of these positions and directions would trigger a connection
        {pos={-1,-1}, dir=defines.direction.east }, -- one space ahead and left, pointing east
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

---@param entity LuaEntity
local function entity_type_or_ghost_type(entity)
    return entity.type == "entity-ghost" and entity.ghost_type or entity.type
end

--- 2.1 removed LuaFluidBox entirely. The count now comes from
--- LuaEntity.fluids_count and the connections from
--- LuaEntity.get_fluid_box_pipe_connections(index).
---
--- fluids_count counts every fluid storage, including ones that are not
--- fluidboxes at all: a fluid turret's internal buffer is the example the docs
--- give, and a turret is exactly what crashed this mod once before. Asking such
--- an index for pipe connections can fail, so both calls are guarded.
---@param entity LuaEntity
---@return integer
local function fluid_storage_count(entity)
    local ok, count = pcall(function() return entity.fluids_count end)
    if ok and type(count) == "number" then return count end
    return 0
end

---@param entity LuaEntity
---@param index integer
---@return PipeConnection[]
local function fluid_box_pipe_connections(entity, index)
    local ok, connections = pcall(entity.get_fluid_box_pipe_connections, index)
    if ok and type(connections) == "table" then return connections end
    return {}
end

--- The categories the pipe we would place can join on. Derived from prototypes, so
--- it cannot change within a session; cached per pipe and rebuilt on load.
---@type table<string, table<string, true>>
local pipe_categories_cache = {}

---@param pipe_entity_name string
---@return table<string, true> categories
local function pipe_connection_categories(pipe_entity_name)
    local cached = pipe_categories_cache[pipe_entity_name]
    if cached then return cached end
    local categories = {}
    local fluidbox_prototypes = prototypes.entity[pipe_entity_name].fluidbox_prototypes
    for i = 1, fluidbox_prototypes and #fluidbox_prototypes or 0 do
        local pipe_connections = fluidbox_prototypes[i].pipe_connections
        for j = 1, pipe_connections and #pipe_connections or 0 do
            for _, category in pairs(pipe_connections[j].connection_category or {}) do
                categories[category] = true
            end
        end
    end
    pipe_categories_cache[pipe_entity_name] = categories
    return categories
end

--- Whether the pipe we would place could actually join this connection. Permissive
--- when either side declares nothing, so entities without categories behave as they
--- always did.
---@param pipe_categories table<string, true>
---@param neighbor_categories string[]?
---@return boolean
local function connection_categories_intersect(pipe_categories, neighbor_categories)
    if not neighbor_categories or not next(pipe_categories) then return true end
    for i = 1, #neighbor_categories do
        if pipe_categories[neighbor_categories[i]] then return true end
    end
    return false
end

--- The runtime PipeConnection carries no connection_category; only the prototype
--- definition does, so the category for a matched connection is read from there.
---@param entity LuaEntity
---@param index integer fluid storage index
---@param connection_index integer
---@return string[]?
local function connection_category_of(entity, index, connection_index)
    local ok, prototype = pcall(entity.get_fluid_box_prototype, index)
    -- a crafting machine's recipe-merged fluidbox answers with a list of prototypes
    -- rather than one, and there is no single connection list to consult; stay
    -- permissive rather than guess
    if not ok or type(prototype) ~= "table" or prototype.object_name ~= "LuaFluidBoxPrototype" then
        return nil
    end
    local connections = prototype.pipe_connections
    local connection = connections and connections[connection_index]
    return connection and connection.connection_category or nil
end

---@param entity LuaEntity
---@param position MapPosition
---@param pipe_categories table<string, true> categories of the pipe that would be placed
---@return boolean place
local function should_place_based_on_neighbor_fluidbox_prototypes(entity, position, pipe_categories)
    for index = 1, fluid_storage_count(entity) do
        local connections = fluid_box_pipe_connections(entity, index)
        for j = 1, #connections do
            local pipe_connection = connections[j]
            -- floor operation rounds to nearest 0.5 to mimic pipe connection snapping behavior
            if position[1] == math.floor( ( pipe_connection.target_position.x + 0.25 ) * 2 ) / 2 and
               position[2] == math.floor( ( pipe_connection.target_position.y + 0.25 ) * 2 ) / 2 then
                -- the geometry lines up; only connect if the categories say it could
                if connection_categories_intersect(
                    pipe_categories, connection_category_of(entity, index, j))
                then
                    return true
                end
            end
        end
    end
    return false
end

--- Look at the three possible locations for another underground or entity to connect to
---@param surface LuaSurface
---@param underground_position MapPosition
---@param neighbors_directions { pos: Vector, dir: defines.direction }[]
---@param underground_entity_name string
---@param pipe_position MapPosition
---@param pipe_entity_name string the pipe we would place, for its connection categories
---@return boolean place Found something worth connecting to
local function find_connection_neighbor(
    surface, underground_position, neighbors_directions, underground_entity_name, pipe_position,
    pipe_entity_name)
    for _, neighbor_candidate in pairs(neighbors_directions) do
        local candidate_pos = {
            underground_position.x + neighbor_candidate.pos[1],
            underground_position.y + neighbor_candidate.pos[2],
        }
        -- first, check for a matching underground pipe, of any quality. find_entity
        -- takes an EntityWithQualityID, and a bare name there means normal quality
        -- rather than any, so it cannot see an uncommon neighbour at all. In the
        -- filtered search quality is a filter of its own, and omitting it matches
        -- everything, which is what we want: quality has no bearing on whether two
        -- pipes can join.
        for _, neighbor_entity in pairs(surface.find_entities_filtered{
            name = underground_entity_name, position = candidate_pos })
        do
            if neighbor_entity.direction == neighbor_candidate.dir then
                return true
            end
        end
        -- check for a matching underground pipe ghost, likewise of any quality
        for _, neighbor_ghost in pairs(surface.find_entities_filtered{
            ghost_name = underground_entity_name, position = candidate_pos })
        do
            if neighbor_ghost.direction == neighbor_candidate.dir then
                return true
            end
        end
        -- check for a matching non-pipe entity with a fluidbox connection
        local neighbor_entities = surface.find_entities( { candidate_pos, candidate_pos } )
        for _,candidate_entity in pairs(neighbor_entities) do
            local entity_type = entity_type_or_ghost_type(candidate_entity)
            if entity_type == "fluid-wagon" then
                -- these have fluidbox connections for pumps, but not for pipes
                goto continue_neighbor_entities
            end
            if  ( entity_type ~= "pipe" and entity_type ~= "pipe-to-ground"
                ) and fluid_storage_count(candidate_entity) > 0
            then
                if should_place_based_on_neighbor_fluidbox_prototypes(
                    candidate_entity, pipe_position,
                    pipe_connection_categories(pipe_entity_name))
                then
                    return true
                end
            end
            ::continue_neighbor_entities::
        end
    end
    return false
end

neighbors.directions_to_neighbors = directions_to_neighbors
neighbors.entity_type_or_ghost_type = entity_type_or_ghost_type
neighbors.should_place_based_on_neighbor_fluidbox_prototypes = should_place_based_on_neighbor_fluidbox_prototypes
neighbors.pipe_connection_categories = pipe_connection_categories
neighbors.connection_categories_intersect = connection_categories_intersect
neighbors.find_connection_neighbor = find_connection_neighbor

return neighbors
