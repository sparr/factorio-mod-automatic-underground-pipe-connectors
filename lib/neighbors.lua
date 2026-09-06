--- Finding the thing a newly placed underground pipe ought to connect to.
local neighbors = {}

--- The four tiles touching a given one. Anything that opens onto a tile has to cover
--- one of these, because a connection's target is always one step from the entity, so
--- there is nowhere else worth looking.
---@type Vector[]
local adjacent_offsets = { {0,-1}, {1,0}, {0,1}, {-1,0} }

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

--- Pipe connections land on half tiles, and some mods place them a hair off, so every
--- comparison goes through the same rounding.
---@param position MapPosition
---@return number, number
local function snapped(position)
    return math.floor( ( position.x + 0.25 ) * 2 ) / 2,
           math.floor( ( position.y + 0.25 ) * 2 ) / 2
end

--- Does this entity have an above-ground connection reaching for `position`, of a
--- kind the pipe we would place could join? Every connection of every fluid storage
--- is asked, not just the first: a junction underground carries several, and the one
--- that matters is rarely the one at the front of the list.
---
--- Only "normal" connections count. An underground pipe also carries an "underground"
--- one, whose target is the far end of the buried run -- and for Pipe Plus's T
--- junction that target is the very tile in question, so counting it would agree that
--- a pipe belongs on a side the entity does not open onto.
---@param entity LuaEntity
---@param position MapPosition
---@param pipe_categories table<string, true> categories of the pipe that would be placed
---@return boolean place
local function opens_onto(entity, position, pipe_categories)
    for index = 1, fluid_storage_count(entity) do
        local connections = fluid_box_pipe_connections(entity, index)
        for j = 1, #connections do
            local pipe_connection = connections[j]
            local x, y = snapped(pipe_connection.target_position)
            if pipe_connection.connection_type == "normal"
            and position[1] == x and position[2] == y then
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

--- Every tile this entity opens onto above ground that the pipe we would place could
--- join, in prototype order and without repeats. A vanilla underground offers one, the
--- tile it faces. A junction offers several, and each is somewhere a connector could go
--- -- which is the only reason the sideways arms of a T or an X are reachable at all.
---@param entity LuaEntity
---@param pipe_categories table<string, true>
---@return MapPosition[]
local function openings(entity, pipe_categories)
    local found, seen = {}, {}
    for index = 1, fluid_storage_count(entity) do
        local connections = fluid_box_pipe_connections(entity, index)
        for j = 1, #connections do
            local pipe_connection = connections[j]
            if pipe_connection.connection_type == "normal"
            and connection_categories_intersect(
                pipe_categories, connection_category_of(entity, index, j))
            then
                local x, y = snapped(pipe_connection.target_position)
                local key = x .. "," .. y
                if not seen[key] then
                    seen[key] = true
                    found[#found + 1] = { x, y }
                end
            end
        end
    end
    return found
end

--- Is there anything on the far side of this tile worth joining to?
---
--- The tile is somewhere the underground just placed opens onto, so a pipe there would
--- join it to whatever else opens onto the same tile. Only the four tiles around it are
--- searched, because that is the whole of what could reach it, and every candidate is
--- judged by its own connections. Nothing here knows which way anything faces, so
--- junctions and oversized pipes answer for themselves.
---
--- The underground that triggered all this opens onto the tile too, so it is skipped --
--- by identity, since a large entity covers more than one tile.
---@param surface LuaSurface
---@param pipe_position MapPosition tile a connector would go on
---@param underground_entity_name string
---@param pipe_entity_name string the pipe we would place, for its connection categories
---@param placed_entity LuaEntity the underground that triggered this
---@return boolean place Found something worth connecting to
local function find_connection_neighbor(
    surface, pipe_position, underground_entity_name, pipe_entity_name, placed_entity)
    local pipe_categories = pipe_connection_categories(pipe_entity_name)
    for _, offset in ipairs(adjacent_offsets) do
        local candidate_pos = { pipe_position[1] + offset[1], pipe_position[2] + offset[2] }
        for _, candidate_entity in pairs(surface.find_entities{ candidate_pos, candidate_pos }) do
            local entity_type = entity_type_or_ghost_type(candidate_entity)
            local candidate_name = candidate_entity.type == "entity-ghost"
                and candidate_entity.ghost_name or candidate_entity.name
            local worth_asking
            if candidate_entity == placed_entity or entity_type == "fluid-wagon" then
                -- a fluid wagon has fluidbox connections for pumps, but not for pipes
                worth_asking = false
            elseif entity_type == "pipe-to-ground" then
                worth_asking = candidate_name == underground_entity_name
            else
                worth_asking = entity_type ~= "pipe" and fluid_storage_count(candidate_entity) > 0
            end
            if worth_asking and opens_onto(candidate_entity, pipe_position, pipe_categories) then
                return true
            end
        end
    end
    return false
end

neighbors.entity_type_or_ghost_type = entity_type_or_ghost_type
neighbors.opens_onto = opens_onto
neighbors.openings = openings
neighbors.pipe_connection_categories = pipe_connection_categories
neighbors.connection_categories_intersect = connection_categories_intersect
neighbors.find_connection_neighbor = find_connection_neighbor

return neighbors
