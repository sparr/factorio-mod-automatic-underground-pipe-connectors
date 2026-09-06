local blueprint = require("lib.blueprint")
local collision = require("lib.collision")
local neighbors = require("lib.neighbors")
local pipes = require("lib.pipes")
local quality = require("lib.quality")
local tiles = require("lib.tiles")
local undo = require("lib.undo")

---@class (exact) Storage
---@field pipe_lookup PipeLookup
---@field tile_lookup TileLookup
---@field index_rebuilt_tick integer
---@type Storage
storage=storage

--- Lookup table from underground pipe entity to the equivalent pipe entity and item, based on recipes
---@alias PipeLookupEntry { item:string, entity:string }
storage.pipe_lookup = storage.pipe_lookup or {}

--- Lookup table from underground pipe entity to the equivalent pipe entity and item, based on recipes
---@alias PipeLookup table<string, PipeLookupEntry>
storage.pipe_lookup = storage.pipe_lookup or {}

--- Lookup table from tile name to the item name that places it, or `false` if no item does
---@alias TileLookup table<string, string|false>
storage.tile_lookup = storage.tile_lookup or {}

---
---@alias EntityEtc
---| LuaEntity
---| LuaSurface.create_entity_param.base
---| LuaSurface.can_place_entity_param
---| LuaSurface.can_fast_replace_param

--- Entity types that share a tile without stopping a ghost being placed on it,
--- *despite* colliding with the pipe. The build check types the engine offers are no
--- help here: script_ghost ignores entities altogether, while manual_ghost and
--- blueprint_ghost bring along the rest of their build rules and refuse placements
--- that plainly do work. So this is a list, and it errs towards letting the connector
--- through: a character standing on the gap is the case players hit, and markers and
--- debris never obstruct anything.
---
--- Anything that does not collide with the pipe at all is handled by the mask test
--- below and does not belong here. A list alone kept turning away entities you can
--- freely build under -- elevated rails, and modded ones like Nullius wind turbines --
--- because they were not names anybody had thought to add.
local ghost_transparent_types = {
    ["character"] = true,
    ["tile-ghost"] = true,
    ["item-entity"] = true,
    ["item-request-proxy"] = true,
    ["deconstructible-tile-proxy"] = true,
    ["corpse"] = true,
    ["rail-remnants"] = true,
    ["highlight-box"] = true,
    ["flying-text"] = true,
    ["smoke"] = true,
    ["particle-source"] = true,
    ["resource"] = true,
}

---@param event EventData.on_built_entity
local function on_built_entity(event)
    local entity = event.entity
    if not entity then return end
    if not entity.valid then return end

    local underground_entity_name --[[@type string]]

    local placed_as_ghost --[[@type boolean]]
    if entity.type == "entity-ghost" then
        placed_as_ghost = true
        underground_entity_name = entity.ghost_name
    else
        placed_as_ghost = false
        underground_entity_name = entity.name
    end

    -- Quality is not part of an entity's name, and every API that takes a bare
    -- name defaults it to normal: find_entity, find_item_stack, create_entity. The
    -- connector matches the underground the player placed, for the same reason its
    -- ghostness does.
    local placed_quality = entity.quality

    local lookup_entry = storage.pipe_lookup[underground_entity_name]
    if not lookup_entry then return end -- we don't know what pipe goes with this underground pipe, bail out
    local pipe_prototype = prototypes.entity[lookup_entry.entity]

    local player = game.players[event.player_index]
    -- A blueprint is a drawing of exactly what the player wants, so whatever gaps it
    -- leaves are deliberate and filling them in overrides the drawing. This covers
    -- the machines a stamp puts down beside an underground as much as the
    -- undergrounds themselves, since the blueprint stays in the cursor throughout.
    if blueprint.is_stamping(player) then return end

    local underground_surface = entity.surface
    local underground_position = entity.position
    local pipe_item_name = lookup_entry.item
    local pipe_entity_name = lookup_entry.entity

    -- Where a connector could go: every tile this underground opens onto above ground.
    -- A vanilla one offers the single tile it faces, which is what the mod used to
    -- work out from its direction. A junction offers its sideways arms as well, and
    -- each of them is a place a pipe could join something.
    local openings = neighbors.openings(
        entity, neighbors.pipe_connection_categories(pipe_entity_name))
    if #openings == 0 then
        -- bail out because what was just placed opens onto nothing we could use
        return
    end

    local inventory = player.get_main_inventory()
    -- The map editor does not charge for a build, so a connector placed alongside
    -- one should not be charged for either, and there is nothing to run out of
    -- that would justify downgrading it to a ghost.
    local free_build = player.controller_type == defines.controllers.editor
    -- Spending a quality the player did not ask for is their call, not ours
    local substitute_quality = player.mod_settings["aupc-substitute-pipe-quality"].value
    --- Try to put a connector on one tile this underground opens onto. Returning
    --- early just abandons this tile; the others are still worth trying, and each
    --- pays for itself separately, so running out of pipes part way leaves ghosts.
    ---
    --- What the neighbour is does not decide the ghostness. The connector matches what
    --- the player just placed: a ghost underground gets a ghost, a real one gets a real
    --- pipe they pay for, whether the thing it connects to is built yet or not.
    ---@param pipe_position MapPosition
    local function place_connector(pipe_position)
    local placing_ghost = placed_as_ghost
    -- What we place is whatever we end up spending, which is normally the
    -- underground's own quality and only differs when they let it
    local connector_quality = placed_quality
    local pipe_stack --[[@type LuaItemStack?]]

    -- if we don't have any regular pipes in our inventory we want to place a ghost instead
    if not placing_ghost and not free_build then
        if inventory then
            pipe_stack = quality.find_stack_to_spend(
                inventory, pipe_item_name, placed_quality, substitute_quality)
            if pipe_stack then connector_quality = pipe_stack.quality end
            placing_ghost = not pipe_stack
        else
            placing_ghost = true
        end
    end

    local existing_tile = underground_surface.get_tile( pipe_position[ 1 ], pipe_position[ 2 ] );
    local existing_tile_state = tiles.save_tile_state( existing_tile )
    -- Only ground the pipe cannot sit on needs covering. A tile that merely names a
    -- default cover tile is not asking to be paved over: that field is the player's
    -- choice of paving material, and modded planets set it on ordinary buildable
    -- ground. Covering those is both wrong and usually impossible, and the failed
    -- check used to take the whole connector down with it.
    ---@type LuaTilePrototype?
    local cover_tile_proto
    if tiles.tile_blocks_entity( existing_tile.prototype, pipe_prototype ) then
        cover_tile_proto = tiles.cover_tile_for( underground_surface, entity.force, existing_tile.prototype )
    end
    ---@type EntityEtc?
    local tile_ghost_definition
    -- tile ghosts stack, eg a concrete ghost over an ice platform ghost over ammoniacal ocean,
    -- and what matters is whichever one ends up on top
    ---@type LuaTilePrototype?
    local ghosted_tile_prototype
    local existing_tile_ghosts = underground_surface.find_entities_filtered{
        name = "tile-ghost", position = pipe_position }
    for _, existing_tile_ghost in pairs(existing_tile_ghosts) do
        local existing_ghost_tile_prototype = existing_tile_ghost.ghost_prototype --[[@as LuaTilePrototype]]
        if not ghosted_tile_prototype or not existing_ghost_tile_prototype.collision_mask.layers.meltable then
            ghosted_tile_prototype = existing_ghost_tile_prototype
        end
    end
    if cover_tile_proto then
        placing_ghost = true;
        if #existing_tile_ghosts == 0 then
            tile_ghost_definition = {
                name = "tile-ghost",
                position = pipe_position,
                inner_name = cover_tile_proto.name,
                -- properties just for create_entity
                force = entity.force,
                player = event.player_index,
                raise_built = true,
                create_build_effect_smoke = true,
                spawn_decorations = true,
                -- properties just for can_place_entity
                build_check_type = defines.build_check_type.script_ghost,
            }
            if not underground_surface.can_place_entity(
                tile_ghost_definition --[[@as LuaSurface.can_place_entity_param]] )
            then
                -- bail out because we can't place the tile ghost
                return
            end
        end
    end

    local tile_proto_to_check_for_melt = existing_tile.prototype
    if ghosted_tile_prototype then
        tile_proto_to_check_for_melt = ghosted_tile_prototype
    elseif cover_tile_proto then
        tile_proto_to_check_for_melt = cover_tile_proto
    end

    -- a pipe collides with the meltable layer, so a meltable tile needs a cover tile of its own
    ---@type EntityEtc?
    local melt_tile_ghost_definition
    ---@type Tile?
    local melt_tile
    ---@type string?
    local melt_tile_item_name
    ---@type LuaQualityPrototype?
    local melt_tile_item_quality
    if tile_proto_to_check_for_melt.collision_mask.layers.meltable then
        local underground_tile = underground_surface.get_tile( underground_position.x, underground_position.y )
        local melt_cover_tile_proto = tiles.find_melt_cover_tile(
            underground_surface, entity.force, tile_proto_to_check_for_melt, underground_tile, inventory )
        if not melt_cover_tile_proto then
            -- bail out because we don't know what to cover the meltable tile with
            return
        end
        -- a real cover tile only makes sense under a real pipe, and only if we have the item to pay for it
        local cover_ghost = placing_ghost
        if not cover_ghost and not free_build then
            local cover_item_name = tiles.tile_item_name( melt_cover_tile_proto.name )
            local cover_stack = cover_item_name and inventory and quality.find_stack_to_spend(
                inventory, cover_item_name, placed_quality, substitute_quality)
            if cover_stack then
                melt_tile_item_name = cover_item_name
                melt_tile_item_quality = cover_stack.quality
            else
                -- without the item the cover has to be a ghost, and a pipe can't sit on an uncovered meltable tile
                cover_ghost = true
                placing_ghost = true
            end
        end
        if cover_ghost then
            melt_tile_ghost_definition = {
                name = "tile-ghost",
                position = pipe_position,
                inner_name = melt_cover_tile_proto.name,
                -- properties just for create_entity
                force = entity.force,
                player = event.player_index,
                raise_built = true,
                create_build_effect_smoke = true,
                spawn_decorations = true,
                -- properties just for can_place_entity
                build_check_type = defines.build_check_type.script_ghost,
            }
            -- only worth asking when the ground we picked this tile for is the ground that is there
            -- now. with another cover tile going underneath first the answer would be about the wrong
            -- tile, eg concrete refused over ammoniacal ocean when an ice platform ghost is going
            -- between them, so leave it to create_entity once the tile below it exists
            if tile_proto_to_check_for_melt.name == existing_tile.name
            and not underground_surface.can_place_entity(
                melt_tile_ghost_definition --[[@as LuaSurface.can_place_entity_param]] ) then
                -- bail out because we can't place the cover tile ghost
                return
            end
        else
            melt_tile = { name = melt_cover_tile_proto.name, position = existing_tile.position }
        end
    end

    ---@type EntityEtc
    local pipe_entity_definition = {
        name = placing_ghost and "entity-ghost" or pipe_entity_name,
        position = pipe_position,
        quality = connector_quality,
        -- properties just for create_entity
        force = entity.force,
        player = event.player_index,
        raise_built = true,
        create_build_effect_smoke = true,
        spawn_decorations = true,

        -- properties just for can_place_entity
        build_check_type = placing_ghost and defines.build_check_type.script_ghost or defines.build_check_type.manual,
    }
    if placing_ghost then
        pipe_entity_definition.inner_name = pipe_entity_name
    end

    -- a pipe collides with the meltable layer, so on a meltable tile the build check would fail on ground
    -- we are about to cover. lay the cover tile down for the check and put it straight back, so the check
    -- still catches everything else it is here for, fluid mixing included
    local can_place --[[@type boolean]]
    if melt_tile then
        underground_surface.set_tiles( { melt_tile }, false, false, false, false )
        can_place = underground_surface.can_place_entity(
            pipe_entity_definition --[[@as LuaSurface.can_place_entity_param]] )
        tiles.restore_tile_state( underground_surface, existing_tile_state, false )
    else
        can_place = underground_surface.can_place_entity(
            pipe_entity_definition --[[@as LuaSurface.can_place_entity_param]] )
    end
    if not can_place then
        -- bail out because we can't place a pipe, could be blocked or a fluid mixing violation
        return
    end

    if placing_ghost then
        local found_entities = underground_surface.find_entities(
            { pipe_entity_definition.position, pipe_entity_definition.position } )
        for _,found_entity in pairs(found_entities) do
            if not ghost_transparent_types[found_entity.type]
            and collision.entity_blocks(found_entity, pipe_prototype) then
                -- bail out because there's already something where we'd place a ghost
                return
            end
        end
    end

    if underground_surface.can_fast_replace( pipe_entity_definition --[[@as LuaSurface.can_fast_replace_param]] ) then
        -- a matching ghost is ok to replace, so only bail out for anything else.
        -- any quality of it: find_entity would only ever have found a normal one
        local ghosts = underground_surface.find_entities_filtered{
            ghost_name = pipe_entity_name, position = pipe_entity_definition.position }
        if not ghosts[1] then
            -- bail out because there's something here our pipe would fast replace
            return
        end
    end

    -- found something to connect to! everything below this point actually changes the world,
    -- so anything that fails has to put back whatever the steps before it managed to place
    ---@type LuaEntity[]
    local placed_tile_ghosts = {}
    local placed_melt_tile = false
    ---@type UndoState?
    local undo_state_before_melt_tile

    --- Undo whatever we placed, so a failure part way through leaves no trace
    local function rollback()
        for _, tile_ghost in pairs(placed_tile_ghosts) do
            if tile_ghost.valid then
                tile_ghost.destroy()
            end
        end
        if placed_melt_tile then
            tiles.restore_tile_state( underground_surface, existing_tile_state, true )
            if undo_state_before_melt_tile then
                -- the tile is gone again, so the player shouldn't be offered an undo for it
                undo.restore_undo_state( player, undo_state_before_melt_tile )
            end
            if melt_tile_item_name and inventory then
                inventory.insert({name=melt_tile_item_name, count=1, quality=melt_tile_item_quality})
            end
        end
    end

    if tile_ghost_definition then
        local tile_ghost = underground_surface.create_entity(
            tile_ghost_definition --[[@as LuaSurface.create_entity_param]] )
        if not tile_ghost then
            -- bail out because we couldn't place the cover tile ghost the pipe needs
            return
        end
        placed_tile_ghosts[#placed_tile_ghosts+1] = tile_ghost
    end

    if melt_tile_ghost_definition then
        local tile_ghost = underground_surface.create_entity(
            melt_tile_ghost_definition --[[@as LuaSurface.create_entity_param]] )
        if not tile_ghost then
            rollback()
            -- bail out because we couldn't place the cover tile ghost the pipe needs
            return
        end
        placed_tile_ghosts[#placed_tile_ghosts+1] = tile_ghost
    end

    if melt_tile then
        -- the trial run above proved the pipe fits once this tile is down.
        -- passing the player puts the tile in their undo queue, alongside the underground they just placed
        undo_state_before_melt_tile = undo.save_undo_state( player )
        underground_surface.set_tiles( {melt_tile}, true, false, true, true, player )
        placed_melt_tile = true
        if melt_tile_item_name and inventory then
            -- we only chose a real tile over a ghost because this item was in inventory
            inventory.remove({name=melt_tile_item_name, count=1, quality=melt_tile_item_quality})
        end
    end

    if not placing_ghost and not free_build then
        -- we ensured above that placing_ghost is true xor we have the necessary item to remove from inventory
        if inventory then
            inventory.remove({name=pipe_item_name, count=1, quality=connector_quality})
        else
            player.print("Placed a pipe for free. This shouldn't happen. Please report a bug on "
                .. "the Automatic Underground Pipe Connectors mod discussion page or github issue "
                .. "tracker, including your game save.")
        end
    end

    -- place the pipe or ghost entity
    if not underground_surface.create_entity(pipe_entity_definition --[[@as LuaSurface.create_entity_param]]) then
        -- the world changed under us between the checks above and now
        rollback()
        if not placing_ghost and not free_build and inventory then
            inventory.insert({name=pipe_item_name, count=1, quality=connector_quality})
        end
    end
    end

    for _, pipe_position in ipairs(openings) do
        if neighbors.find_connection_neighbor(
            underground_surface, pipe_position, underground_entity_name,
            pipe_entity_name, entity )
        then
            place_connector(pipe_position)
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
    -- tile prototypes and the items that place them can change with the mod list
    storage.tile_lookup = {}
    local underground_recipe_prototypes = prototypes.get_recipe_filtered(
        {
            {
                filter="has-product-item",
                elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe-to-ground"}}}}
            },
            {
                mode="and",filter="has-ingredient-item",
                elem_filters={{filter="place-result",elem_filters={{filter="type",type="pipe"}}}}
            }
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
        -- Collect every recipe ingredient that places a pipe, in order, and let
        -- lib.pipes decide between them. A recipe can list more than one, and the
        -- first is not always the one that can join this underground.
        local candidates = {}
        for _, ingredient in pairs(underground_recipe_prototype.ingredients) do
            local result = ingredient.type == "item" and prototypes.item[ingredient.name].place_result
            if result and prototypes.entity[result.name].type == "pipe" then
                candidates[#candidates + 1] = { item = ingredient.name, entity = result.name }
            end
        end
        local chosen = pipes.choose(underground_entity_name, candidates)
        if chosen then
            pipe_item_name = chosen.item
            pipe_entity_name = chosen.entity
        end
        if underground_entity_name and pipe_item_name and pipe_entity_name then
            -- Remember that when this underground entity is placed, this pipe item and entity are the ones to use
            -- Also remember which item places the underground entity
            storage.pipe_lookup[underground_entity_name] = {item = pipe_item_name, entity = pipe_entity_name }
        end
        ::continue_underground_recipe_prototype::
    end
end

script.on_init(rebuild_index)
script.on_configuration_changed(rebuild_index)

--- Filters out extra fields in the item_pipe and makes sure the references are valid entities and item
---@param underground_entity string
---@param lookup_entry PipeLookupEntry
---@return PipeLookupEntry lookup_entry Has been filtered of extra fields
local function validate_lookup(underground_entity, lookup_entry)
    -- Filter out the extra fields
    lookup_entry = { item = lookup_entry.item, entity = lookup_entry.entity }
    local underground_prototype = prototypes.entity[underground_entity]
    local pipe_prototype = prototypes.entity[lookup_entry.entity]

    ---@type table<string, true>
    local pipe_items = {}
    for _, stack in pairs(pipe_prototype.items_to_place_this) do
        pipe_items[stack.name] = true
    end

    -- The item needs to be able to place the pipe
    if not pipe_items[lookup_entry.item]
    -- The item needs to exist (theoretically we can skip this since it was in an items_to_place_this)
    or not prototypes.item[lookup_entry.item]
    -- The pipe needs to be an actual pipe
    or not pipe_prototype or pipe_prototype.type ~= "pipe"
    -- The underground needs to be an actual underground
    or not underground_prototype or underground_prototype.type ~= "pipe-to-ground" then
        error("Given underground lookup entry is not valid: "..underground_entity.." -> "..serpent.line(lookup_entry))
    end

    return lookup_entry
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
        for underground, lookup_entry in pairs(new_lookup) do
            new_lookup[underground] = validate_lookup(underground, lookup_entry)
        end

        storage.pipe_lookup = new_lookup
    end,
    --- Allows mods to add underground and pipe connections for when they don't follow the expected recipe pattern.
    ---@param new_undergrounds PipeLookup
    add_undergrounds = function(new_undergrounds)
        for underground, lookup_entry in pairs(new_undergrounds) do
            storage.pipe_lookup[underground] = validate_lookup(underground, lookup_entry)
        end
    end,
    --- Allows mods to remove undergrounds just in case
    ---@param old_undergrounds string[]
    remove_undergrounds = function(old_undergrounds)
        for _, underground in pairs(old_undergrounds) do
            if storage.pipe_lookup[underground] then
                log("Removing the lookup entry for '"..underground.."'")
                storage.pipe_lookup[underground] = nil
            end
        end
    end,
})

script.on_event(
    defines.events.on_built_entity,
    on_built_entity,
    {{filter="type",type="pipe-to-ground"},{filter="ghost_type",type="pipe-to-ground"}}
)

--- The integration tier, which runs inside a live game rather than against stubs.
--- Registered here rather than from the test mod because only the owning mod may write
--- its own runtime-per-user setting, which the quality fixtures need to do.
--- aupc-tests is never published, so this can never fire on a player's machine -- which
--- matters, because info.json keeps test/ out of the package.
if script.active_mods["factorio-test"] and script.active_mods["aupc-tests"] then
    require("__factorio-test__/init")({
        "test.ft.prototypes",
        "test.ft.basics",
        "test.ft.quality",
        "test.ft.junctions",
        "test.ft.tiles",
        "test.ft.neighbours",
        "test.ft.blueprints",
        "test.ft.controllers",
        "test.ft.undo",
    }, {
        load_luassert = true,
        game_speed = 100,
    })
end
