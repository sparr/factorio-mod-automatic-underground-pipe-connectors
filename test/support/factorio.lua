--- Stand-ins for the parts of the Factorio API that lib/ touches.
--- Only enough to exercise the decisions; anything about what the engine really
--- does with a tile or a build check belongs in the integration tier instead.
local support = {}

-- Neither runtime-api.json nor FMTK's stubs carry the numeric values (both are
-- names only), so these are the documented 2.0 sixteen-direction layout.
local DIRECTIONS = {
    north = 0, northnortheast = 1, northeast = 2, eastnortheast = 3,
    east = 4, eastsoutheast = 5, southeast = 6, southsoutheast = 7,
    south = 8, southsouthwest = 9, southwest = 10, westsouthwest = 11,
    west = 12, westnorthwest = 13, northwest = 14, northnorthwest = 15,
}

--- Must run before requiring lib/neighbors, which reads defines at load time
function support.install_defines()
    _G.defines = {
        direction = DIRECTIONS,
        build_check_type = {
            script = 1, manual = 2, manual_ghost = 3,
            script_ghost = 4, blueprint_ghost = 5, ghost_revive = 6,
        },
        events = { on_built_entity = 1 },
    }
end

function support.install_storage()
    _G.storage = { pipe_lookup = {}, tile_lookup = {} }
end

--- Turn the compact data in test/support/vanilla into prototype-shaped tables
---@param spec table
function support.install_prototypes(spec)
    local tile_prototypes = {}
    for name, tile in pairs(spec.tiles) do
        tile_prototypes[name] = {
            name = name,
            collision_mask = { layers = tile.layers or {} },
            items_to_place_this = tile.item and { { name = tile.item, count = 1 } } or nil,
        }
    end
    for name, tile in pairs(spec.tiles) do
        if tile.default_cover then
            tile_prototypes[name].default_cover_tile = tile_prototypes[tile.default_cover]
        end
    end

    local item_prototypes = {}
    for name, item in pairs(spec.items or {}) do
        local tile_condition = {}
        for _, tile_name in ipairs(item.tile_condition or {}) do
            tile_condition[#tile_condition + 1] = tile_prototypes[tile_name]
        end
        item_prototypes[name] = {
            name = name,
            place_as_tile_result = item.result and {
                result = tile_prototypes[item.result],
                condition = { layers = item.condition or {} },
                tile_condition = tile_condition,
                invert = item.invert or false,
            } or nil,
        }
    end

    local entity_prototypes = {}
    for name, entity in pairs(spec.entities or {}) do
        entity_prototypes[name] = {
            name = name,
            collision_mask = { layers = entity.layers or {} },
        }
    end

    _G.prototypes = { tile = tile_prototypes, item = item_prototypes, entity = entity_prototypes }
    return tile_prototypes, item_prototypes, entity_prototypes
end

--- A tile, as LuaSurface.get_tile would hand one back
function support.tile(tile_prototype, position, hidden_tile)
    return {
        name = tile_prototype.name,
        prototype = tile_prototype,
        position = position or { x = 0, y = 0 },
        hidden_tile = hidden_tile,
        double_hidden_tile = nil,
    }
end

--- The fluid half of an entity. 2.1 removed LuaFluidBox, so this is a count and a
--- method on the entity rather than a separate object.
---@param connections_per_index table list of PipeConnection lists, one per storage
function support.with_fluid_connections(entity, connections_per_index)
    entity.fluids_count = #connections_per_index
    entity.get_fluid_box_pipe_connections = function(index)
        return connections_per_index[index] or {}
    end
    -- connection_category lives on the prototype definition, not the runtime
    -- connection, so a connection carrying one is mirrored over to this side
    entity.get_fluid_box_prototype = function(index)
        local connections = {}
        for i, connection in ipairs(connections_per_index[index] or {}) do
            connections[i] = { connection_category = connection.connection_category }
        end
        return { object_name = "LuaFluidBoxPrototype", pipe_connections = connections }
    end
    return entity
end

--- An entity whose only interesting feature is its fluid connections
function support.fluid_entity(connections_per_index, fields)
    local entity = fields or {}
    return support.with_fluid_connections(entity, connections_per_index)
end

--- opts.entities: list of { name, type, ghost_name, ghost_type, direction, position = {x,y}, fluidbox }
--- opts.cover_tiles: [tile name] = tile prototype, standing in for the per-force override
function support.surface(opts)
    opts = opts or {}
    local entities = opts.entities or {}
    local cover_tiles = opts.cover_tiles or {}
    local calls = { set_tiles = {}, set_hidden_tile = {}, set_double_hidden_tile = {} }

    -- positions arrive both ways: the mod builds arrays, the API hands back {x=,y=}
    local function xy(position)
        return position[1] or position.x, position[2] or position.y
    end

    local function entities_at(position)
        local x, y = xy(position)
        local found = {}
        for _, entity in ipairs(entities) do
            local entity_x, entity_y = xy(entity.position)
            if entity_x == x and entity_y == y then
                found[#found + 1] = entity
            end
        end
        return found
    end

    -- Quality is not part of an entity's name. Anywhere the API takes an
    -- EntityWithQualityID or ItemWithQualityID, a bare name means *normal*, not
    -- "any", so the stub reproduces that trap rather than smoothing it over.
    local function quality_of(entity)
        return entity.quality or "normal"
    end

    local function wanted_name(id)
        return type(id) == "table" and id.name or id
    end

    local function wanted_quality(id)
        return type(id) == "table" and (id.quality or "normal") or "normal"
    end

    return {
        calls = calls,
        get_default_cover_tile = function(_, tile)
            return cover_tiles[type(tile) == "table" and tile.name or tile]
        end,
        find_entity = function(entity_id, position)
            local name, quality = wanted_name(entity_id), wanted_quality(entity_id)
            for _, entity in ipairs(entities_at(position)) do
                if entity.name == name and quality_of(entity) == quality then return entity end
            end
            return nil
        end,
        -- here quality is a filter of its own, so leaving it out matches every quality
        find_entities_filtered = function(filter)
            local found = {}
            for _, entity in ipairs(entities_at(filter.position)) do
                local matches = true
                if filter.name and entity.name ~= filter.name then matches = false end
                if filter.ghost_name and entity.ghost_name ~= filter.ghost_name then matches = false end
                if filter.quality and quality_of(entity) ~= filter.quality then matches = false end
                if matches then found[#found + 1] = entity end
            end
            return found
        end,
        find_entities = function(area)
            return entities_at(area[1])
        end,
        set_tiles = function(tiles_to_set, ...)
            calls.set_tiles[#calls.set_tiles + 1] = { tiles = tiles_to_set, args = { ... } }
        end,
        set_hidden_tile = function(position, tile)
            calls.set_hidden_tile[#calls.set_hidden_tile + 1] = { position = position, tile = tile }
        end,
        set_double_hidden_tile = function(position, tile)
            calls.set_double_hidden_tile[#calls.set_double_hidden_tile + 1] =
                { position = position, tile = tile }
        end,
    }
end

function support.inventory(counts)
    counts = counts or {}
    return {
        counts = counts,
        get_item_count = function(name) return counts[name] or 0 end,
        find_item_stack = function(name)
            if (counts[name] or 0) > 0 then return { name = name } end
            return nil
        end,
        remove = function(stack) counts[stack.name] = (counts[stack.name] or 0) - (stack.count or 1) end,
        insert = function(stack) counts[stack.name] = (counts[stack.name] or 0) + (stack.count or 1) end,
    }
end

--- undo_items is ordered most recent first, matching LuaUndoRedoStack
function support.player(undo_items)
    undo_items = undo_items or {}
    return {
        undo_items = undo_items,
        undo_redo_stack = {
            get_undo_item_count = function() return #undo_items end,
            get_undo_item = function(index) return undo_items[index] end,
            remove_undo_item = function(index) table.remove(undo_items, index) end,
            remove_undo_action = function(item_index, action_index)
                table.remove(undo_items[item_index], action_index)
                if #undo_items[item_index] == 0 then table.remove(undo_items, item_index) end
            end,
        },
    }
end

return support
