--- The ground, the player and the little helpers every fixture runs against.
---
--- Each test claims its own 12x12 patch of Aquilo and works in the middle of it, so
--- nothing a test leaves behind can reach the next one. Aquilo rather than a lab-tile
--- surface because the meltable-ground fixtures need real ice, and because a tile laid
--- there freezes on contact, which is a difference the mod has to survive.
local world = {}

world.PIPE = "pipe"
world.UNDERGROUND = "pipe-to-ground"

local PATCH = 12
--- patches per row, so a run stays inside a small block of generated chunks
local COLUMNS = 10

local prepared = false
local patch_index = -1

--- Aquilo freezes a placed tile on contact. The frozen variant is placeable by the
--- same item (frozen_concrete sets placeable_by in tiles-aquilo.lua), so either name
--- is a correct answer to "did we get refined concrete".
---@param actual string
---@param expected string
function world.same_tile(actual, expected)
    if actual == expected then return true end
    local prototype = prototypes.tile[expected]
    local frozen = prototype and prototype.frozen_variant
    return frozen ~= nil and frozen.name == actual
end

---@param dx integer
---@param dy integer
---@return defines.direction?
function world.direction_of(dx, dy)
    if dx == 0 and dy == -1 then return defines.direction.north end
    if dx == 1 and dy == 0 then return defines.direction.east end
    if dx == 0 and dy == 1 then return defines.direction.south end
    if dx == -1 and dy == 0 then return defines.direction.west end
    return nil
end

--- The tile an entity points into, which is exactly where a connector would go
local DIRECTION_VECTORS = {
    [defines.direction.north] = { 0, -1 },
    [defines.direction.east]  = { 1, 0 },
    [defines.direction.south] = { 0, 1 },
    [defines.direction.west]  = { -1, 0 },
}

---@param entity LuaEntity
function world.in_front_of(entity)
    local vector = DIRECTION_VECTORS[entity.direction]
    if not vector then return nil end
    return { x = entity.position.x + vector[1], y = entity.position.y + vector[2] }
end

local function prepare()
    if prepared then return end
    local aquilo = game.planets and game.planets["aquilo"]
    if not aquilo then error("no aquilo planet; is space-age enabled?") end
    local surface = aquilo.surface or aquilo.create_surface()
    -- Painting only works on generated chunks, so the grid has to exist before the
    -- first patch is claimed. Centred on the grid rather than on the origin: chunk
    -- generation is the most expensive thing this tier does, and a request centred at
    -- 0,0 spends three quarters of it on quadrants no fixture ever visits.
    local span = COLUMNS * PATCH
    surface.request_to_generate_chunks({ x = span / 2, y = span / 2 }, math.ceil(span / 32))
    surface.force_generate_chunk_requests()
    world.surface = surface
    prepared = true
end

--- Claim the next patch and hand back everything a fixture needs to work in it.
---
--- Also puts the player back the way a fixture expects to find them: god controller,
--- empty cursor, standing on the new patch, with the mod's own setting at its default.
--- A fixture that wants something else says so for itself.
function world.patch()
    prepare()
    local player = game.players[1]
    local surface = world.surface

    patch_index = patch_index + 1
    -- the generated block is square, so the grid runs out of rows at the same count
    assert(patch_index < COLUMNS * COLUMNS,
        "more fixtures than the generated patch grid holds; widen it in test/ft/world.lua")
    local left = (patch_index % COLUMNS) * PATCH
    local top = math.floor(patch_index / COLUMNS) * PATCH

    -- the map editor pauses entity updates, which also stops the tick the framework
    -- needs to reach the next test
    if game.tick_paused then game.tick_paused = false end
    if player.controller_type ~= defines.controllers.god then
        player.set_controller{ type = defines.controllers.god }
    end
    if player.cursor_stack and player.cursor_stack.valid then player.cursor_stack.clear() end
    player.cursor_ghost = nil
    settings.get_player_settings(player)["aupc-substitute-pipe-quality"] = { value = false }

    -- Aquilo generates its own entities, lithium icebergs among them, and one sitting
    -- on a gap makes the mod correctly refuse to build there. Painting tiles does not
    -- remove them, so a patch has to be cleared before use or fixtures fail at
    -- whatever rate the map seed puts a rock in the way.
    local area = { { left, top }, { left + PATCH, top + PATCH } }
    for _, entity in pairs(surface.find_entities(area)) do
        if entity.valid then entity.destroy() end
    end
    surface.destroy_decoratives{ area = area }

    player.teleport({ x = left + 6.5, y = top + 5.5 }, surface)

    local patch = {
        surface = surface,
        player = player,
        left = left,
        top = top,
        area = area,
        -- B faces north into the gap, A faces south into it from two tiles away
        a = { x = left + 6.5, y = top + 4.5 },
        b = { x = left + 6.5, y = top + 6.5 },
        gap = { x = left + 6.5, y = top + 5.5 },
        --- somewhere inside the patch to stand while building in the middle of it
        stand = { x = left + 1.5, y = top + 1.5 },
    }

    ---@param tile_name string
    ---@param bounds table? { left, top, width, height }, defaulting to the whole patch
    function patch.paint(tile_name, bounds)
        local tiles = {}
        local from_x = bounds and bounds.left or left
        local from_y = bounds and bounds.top or top
        local width = bounds and bounds.width or PATCH
        local height = bounds and bounds.height or PATCH
        for x = from_x, from_x + width - 1 do
            for y = from_y, from_y + height - 1 do
                tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
            end
        end
        surface.set_tiles(tiles, true, false, false, false)
    end

    --- Paint the single tile a position falls on
    function patch.paint_at(tile_name, position)
        patch.paint(tile_name, { left = math.floor(position.x), top = math.floor(position.y),
                                 width = 1, height = 1 })
    end

    --- `quality` is optional and applies to every item in the table
    function patch.stock(items, quality)
        local inventory = player.get_main_inventory()
        if not inventory then error("the controller has no main inventory to stock") end
        inventory.clear()
        for name, count in pairs(items) do
            if type(count) == "table" then
                for quality_name, n in pairs(count) do
                    inventory.insert{ name = name, count = n, quality = quality_name }
                end
            else
                inventory.insert{ name = name, count = count, quality = quality }
            end
        end
    end

    --- A bare item name means normal quality to the API, not "any quality", so a
    --- fixture asking about uncommon items has to say so.
    function patch.count(item_name, quality)
        local inventory = player.get_main_inventory()
        if not inventory then return 0 end
        if quality then return inventory.get_item_count{ name = item_name, quality = quality } end
        return inventory.get_item_count(item_name)
    end

    --- Take the item out of the player's own inventory rather than conjuring it into
    --- the cursor. Otherwise the fixture builds the undergrounds for free and then
    --- watches the mod pay for the connector, which is not a situation any player is
    --- ever in. Editor and remote have nothing to draw from, and the game charges
    --- nothing in either, so those fall back to a stack from thin air.
    function patch.build(name, position, direction, stand_at, quality)
        -- Only move for a caller that asks: a character has to stand clear of its own
        -- build site, but moving for every placement drags the camera off the patch.
        if stand_at then player.teleport(stand_at, surface) end
        local inventory = player.get_main_inventory()
        local stack = inventory and inventory.find_item_stack(
            quality and { name = name, quality = quality } or name)
        if stack then
            player.cursor_stack.swap_stack(stack)
        else
            player.cursor_stack.set_stack{ name = name, count = 1, quality = quality }
        end
        player.build_from_cursor{ position = position, direction = direction }
        if inventory and player.cursor_stack.valid_for_read then
            inventory.insert(player.cursor_stack)
        end
        player.cursor_stack.clear()
    end

    --- Shift-placing is what a player does when they have no item to spend, and that is
    --- exactly the state cursor_ghost describes: an item ghost in the cursor rather than
    --- a stack. A one-entity blueprint used to stand in here, but the mod now tells a
    --- blueprint stamp apart from a hand placement, so a blueprint no longer stands in
    --- for one.
    function patch.build_ghost(name, position, direction, stand_at)
        if stand_at then player.teleport(stand_at, surface) end
        player.cursor_stack.clear()
        player.cursor_ghost = name
        player.build_from_cursor{ position = position, direction = direction }
        player.cursor_ghost = nil
    end

    --- find_entity would only ever see a normal-quality one: a bare name is an
    --- EntityWithQualityID, and that means normal, not any.
    function patch.pipe_at(position)
        return surface.find_entities_filtered{ name = world.PIPE, position = position or patch.gap }[1]
    end

    ---@return string? the ghosted entity's name
    function patch.ghost_at(position)
        local ghost = surface.find_entities_filtered{
            name = "entity-ghost", position = position or patch.gap }[1]
        return ghost and ghost.ghost_name or nil
    end

    ---@return LuaEntity?
    function patch.ghost_entity_at(position)
        return surface.find_entities_filtered{
            name = "entity-ghost", position = position or patch.gap }[1]
    end

    function patch.tile_ghosts_at(position)
        local names = {}
        for _, ghost in pairs(surface.find_entities_filtered{
            name = "tile-ghost", position = position or patch.gap
        }) do
            names[#names + 1] = ghost.ghost_prototype.name
        end
        table.sort(names)
        return names
    end

    function patch.tile_at(position)
        position = position or patch.gap
        return surface.get_tile(position.x, position.y).name
    end

    --- What is standing on a spot, named for a failure message
    function patch.occupants(position)
        local names = {}
        for _, entity in pairs(surface.find_entities{ position, position }) do
            names[#names + 1] = entity.name ..
                (entity.name == "entity-ghost" and ("/" .. entity.ghost_name) or "")
        end
        table.sort(names)
        return names
    end

    --- The runtime-per-user setting deciding whether a quality the player did not ask
    --- for may be spent. Only the owning mod may write it, and these tests are the
    --- owning mod, so both answers are reachable in one run.
    function patch.substitute_quality(value)
        settings.get_player_settings(player)["aupc-substitute-pipe-quality"] = { value = value }
    end

    --- Aim an underground at one of an entity's fluid connections.
    ---@param neighbour LuaEntity
    ---@param downward_only boolean? only accept a connection below the neighbour
    ---@return table? { gap = position, spot = position, facing = direction }
    function patch.reachable_connection(neighbour, downward_only)
        -- 2.1 removed LuaFluidBox; the entity carries the count and the connections
        for index = 1, neighbour.fluids_count do
            for _, connection in pairs(neighbour.get_fluid_box_pipe_connections(index)) do
                local target = connection.target_position
                local dx = target.x - connection.position.x
                local dy = target.y - connection.position.y
                dx = dx > 0.25 and 1 or (dx < -0.25 and -1 or 0)
                dy = dy > 0.25 and 1 or (dy < -0.25 and -1 or 0)
                -- one tile further along, facing back, so the gap is exactly the target
                local facing = world.direction_of(-dx, -dy)
                local spot = { x = target.x + dx, y = target.y + dy }
                local clear = #surface.find_entities{
                    { spot.x - 0.4, spot.y - 0.4 }, { spot.x + 0.4, spot.y + 0.4 } } == 0
                if facing and clear and (not downward_only or dy > 0) then
                    return { gap = target, spot = spot, facing = facing }
                end
            end
        end
        return nil
    end

    --- Snapshot an area into a blueprint, clear it, then stamp it back. Capturing an
    --- arrangement the other fixtures already prove works is the only way to be sure the
    --- geometry is right, rather than hand-computing relative positions.
    ---@return integer entities the blueprint captured
    function patch.restamp(bounds)
        player.cursor_stack.set_stack{ name = "blueprint" }
        player.cursor_stack.create_blueprint{
            surface = surface, force = player.force, area = bounds }
        local entries = player.cursor_stack.get_blueprint_entities() or {}

        local placed, sum_x, sum_y = {}, 0, 0
        for _, entity in pairs(surface.find_entities(bounds)) do
            if entity.valid and entity.type ~= "character" then
                placed[#placed + 1] = entity
                sum_x, sum_y = sum_x + entity.position.x, sum_y + entity.position.y
            end
        end
        -- Roughly where it came from is enough. Exactly where a stamp lands depends on
        -- the blueprint's own bounding box and grid snapping, so the checks that follow
        -- find the stamped entities and work from those rather than trusting this.
        local centre = #placed > 0 and { x = sum_x / #placed, y = sum_y / #placed }

        for _, entity in ipairs(placed) do if entity.valid then entity.destroy() end end
        if centre then player.build_from_cursor{ position = centre } end
        player.cursor_stack.clear()
        return #entries
    end

    --- The same stamp, but driven straight from the API with the cursor empty.
    --- build_blueprint fires on_built_entity whenever by_player is given, so the mod
    --- hears about it exactly as it hears about a hand placement, while nothing is in
    --- the cursor to say a blueprint is involved.
    function patch.restamp_via_api(bounds)
        local inventory = game.create_inventory(1)
        inventory[1].set_stack{ name = "blueprint" }
        inventory[1].create_blueprint{ surface = surface, force = player.force, area = bounds }
        local entries = inventory[1].get_blueprint_entities() or {}

        local placed, sum_x, sum_y = {}, 0, 0
        for _, entity in pairs(surface.find_entities(bounds)) do
            if entity.valid and entity.type ~= "character" then
                placed[#placed + 1] = entity
                sum_x, sum_y = sum_x + entity.position.x, sum_y + entity.position.y
            end
        end
        local centre = #placed > 0 and { x = sum_x / #placed, y = sum_y / #placed }
        for _, entity in ipairs(placed) do if entity.valid then entity.destroy() end end

        if centre then
            inventory[1].build_blueprint{
                surface = surface, force = player.force, position = centre, by_player = player }
        end
        inventory.destroy()
        return #entries
    end

    return patch
end

return world
