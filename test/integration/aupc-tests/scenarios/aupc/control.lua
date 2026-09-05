--- Integration fixtures for Automatic Underground Pipe Connectors.
---
--- Every fixture gets its own patch of ground and runs one action per tick, so
--- nothing lands in the same tick as anything else. Results go to
--- script-output/aupc-results.lua and the run prints a sentinel when it is done.
local RESULTS_FILE = "aupc-results.lua"
local SENTINEL = "AUPC-TESTS-COMPLETE"
local UNDERGROUND = "pipe-to-ground"
local PIPE = "pipe"
local PATCH = 12
--- How long a step may wait on synthetic input before giving up, in ticks
local WAIT_TICKS = 600

local report = { fixtures = {} }
local steps = {}
local step_index = 1
local finished = false
local probe_seen = false
local current
local world = {}

--------------------------------------------------------------------------- plumbing

local function step(fn) steps[#steps + 1] = fn end

--- Context printed alongside a failure, to say what the world looked like
local function note(message)
    current.notes = current.notes or {}
    current.notes[#current.notes + 1] = message
end

local function check(condition, message)
    if not condition then
        current.failures[#current.failures + 1] = message
    end
    return condition
end

--- Claim a patch and start recording against a new fixture
local function begin(name)
    step(function()
        current = { name = name, failures = {} }
        report.fixtures[#report.fixtures + 1] = current
        world.patch = world.patch + 1
        local left = (world.patch - 1) * PATCH
        -- B faces north into the gap, A faces south into it from two tiles away
        world.b = { x = left + 6.5, y = 6.5 }
        world.a = { x = left + 6.5, y = 4.5 }
        world.gap = { x = left + 6.5, y = 5.5 }
        world.left = left

        -- Aquilo generates its own entities, lithium icebergs among them, and one
        -- sitting on a gap makes the mod correctly refuse to build there. Painting
        -- tiles does not remove them, so a patch has to be cleared before use or
        -- fixtures fail at whatever rate the map seed puts a rock in the way.
        local area = { { left, 0 }, { left + PATCH, PATCH } }
        for _, entity in pairs(world.surface.find_entities(area)) do
            if entity.valid and entity.type ~= "character" then entity.destroy() end
        end
        world.surface.destroy_decoratives{ area = area }
    end)
end

local function paint(tile_name, area)
    local tiles = {}
    local left = area and area.left or world.left
    local top = area and area.top or 0
    local width = area and area.width or PATCH
    local height = area and area.height or PATCH
    for x = left, left + width - 1 do
        for y = top, top + height - 1 do
            tiles[#tiles + 1] = { name = tile_name, position = { x, y } }
        end
    end
    world.surface.set_tiles(tiles, true, false, false, false)
end

local function stock(items)
    local inventory = world.player.get_main_inventory()
    if not inventory then return end
    inventory.clear()
    for name, count in pairs(items) do
        inventory.insert{ name = name, count = count }
    end
end

local function count(item_name)
    local inventory = world.player.get_main_inventory()
    return inventory and inventory.get_item_count(item_name) or 0
end

local function build_real(name, position, direction, stand_at)
    world.player.teleport(stand_at or position, world.surface)
    world.player.cursor_stack.set_stack{ name = name, count = 10 }
    world.player.build_from_cursor{ position = position, direction = direction }
    world.player.cursor_stack.clear()
end

--- The API has no shift-click equivalent, so a one-entity blueprint stands in.
--- It still reaches the mod as a real on_built_entity with a player index.
local function build_ghost(name, position, direction)
    world.player.teleport(position, world.surface)
    world.player.cursor_stack.set_stack{ name = "blueprint" }
    world.player.cursor_stack.set_blueprint_entities{
        { entity_number = 1, name = name, position = { 0, 0 }, direction = direction },
    }
    world.player.build_from_cursor{ position = position }
    world.player.cursor_stack.clear()
end

--------------------------------------------------------------------------- inspection

local function pipe_at_gap()
    return world.surface.find_entity(PIPE, world.gap)
end

local function ghost_at_gap()
    local ghost = world.surface.find_entity("entity-ghost", world.gap)
    return ghost and ghost.ghost_name or nil
end

local function tile_ghosts_at_gap()
    local names = {}
    for _, ghost in pairs(world.surface.find_entities_filtered{
        name = "tile-ghost", position = world.gap
    }) do
        names[#names + 1] = ghost.ghost_prototype.name
    end
    table.sort(names)
    return names
end

local function tile_at_gap()
    return world.surface.get_tile(world.gap.x, world.gap.y).name
end

--- Aquilo freezes a placed tile on contact. The frozen variant is placeable by
--- the same item (frozen_concrete sets placeable_by in tiles-aquilo.lua), so
--- either name is a correct answer to "did we get refined concrete".
local function same_tile(actual, expected)
    if actual == expected then return true end
    local prototype = prototypes.tile[expected]
    local frozen = prototype and prototype.frozen_variant
    return frozen ~= nil and frozen.name == actual
end

--------------------------------------------------------------------------- fixtures

--- Two undergrounds one apart on ordinary buildable ground, pipe in inventory
local function fixture_plain_ground()
    begin("real pair on refined concrete gets a real pipe")
    step(function()
        paint("refined-concrete")
        stock{ [PIPE] = 10 }
        check(same_tile(tile_at_gap(), "refined-concrete"),
            "setup: the gap is " .. tile_at_gap() .. ", not refined concrete")
    end)
    step(function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step(function()
        check(pipe_at_gap() == nil, "a pipe appeared before the second underground existed")
        build_real(UNDERGROUND, world.b, defines.direction.north)
    end)
    step(function()
        check(pipe_at_gap() ~= nil, "no pipe was placed in the gap")
        check(ghost_at_gap() == nil, "a ghost was placed instead of a real pipe")
        check(count(PIPE) == 9, "expected one pipe consumed, inventory holds " .. count(PIPE))
        check(same_tile(tile_at_gap(), "refined-concrete"),
            "the ground was changed to " .. tile_at_gap())
        check(#tile_ghosts_at_gap() == 0, "an unnecessary tile ghost was placed")
    end)
end

--- The gap is meltable, the player is carrying something that can cover it
local function fixture_ice_gap_with_cover()
    begin("meltable gap gets a real cover tile when the item is held")
    step(function()
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        stock{ [PIPE] = 10, ["refined-concrete"] = 10 }
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step(function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step(function()
        -- the state the mod will actually see, captured before it runs
        note("at build time, under A: " .. world.surface.get_tile(world.a.x, world.a.y).name)
        note("at build time, under B: " .. world.surface.get_tile(world.b.x, world.b.y).name)
        note("at build time, gap: " .. tile_at_gap())
        build_real(UNDERGROUND, world.b, defines.direction.north)
    end)
    step(function()
        note("tile under B: " .. world.surface.get_tile(world.b.x, world.b.y).name)
        local override = world.surface.get_default_cover_tile(world.player.force, "ice-rough")
        note("get_default_cover_tile(ice-rough) = " .. tostring(override and override.name))
        note("gap tile: " .. tile_at_gap())

        -- The mod lays the cover tile down for the pipe's build check and takes it
        -- straight back. Replay that here: if the pipe does not fit even on covered
        -- ground, the mod was right to bail and the question is why it does not fit.
        local occupants = {}
        for _, entity in pairs(world.surface.find_entities{
            { world.gap.x - 0.4, world.gap.y - 0.4 }, { world.gap.x + 0.4, world.gap.y + 0.4 }
        }) do
            occupants[#occupants + 1] = entity.name
        end
        note("at the gap: " .. (#occupants > 0 and table.concat(occupants, "+") or "nothing"))

        check(same_tile(tile_at_gap(), "refined-concrete"),
            "the meltable tile was not covered, it is still " .. tile_at_gap())
        check(pipe_at_gap() ~= nil, "no pipe was placed on the covered ground")
        check(ghost_at_gap() == nil, "a ghost was placed where a real pipe should fit")
        check(count(PIPE) == 9, "expected one pipe consumed, inventory holds " .. count(PIPE))
        check(count("refined-concrete") == 9,
            "expected one cover tile consumed, inventory holds " .. count("refined-concrete"))
    end)
end

--- Same gap, nothing to pay for the cover with
local function fixture_ice_gap_without_cover()
    begin("meltable gap falls back to ghosts with no cover item")
    step(function()
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        stock{ [PIPE] = 10 }
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step(function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step(function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step(function()
        check(tile_at_gap() == "ice-rough", "the ground was changed without paying for it")
        check(pipe_at_gap() == nil, "a real pipe was placed on uncovered meltable ground")
        check(ghost_at_gap() == PIPE, "expected a pipe ghost, found " .. tostring(ghost_at_gap()))
        local covers = tile_ghosts_at_gap()
        check(#covers == 1, "expected one cover tile ghost, found " .. #covers)
        check(same_tile(covers[1], "refined-concrete"),
            "expected the foundation the undergrounds stand on, found " .. tostring(covers[1]))
        check(count(PIPE) == 10, "a pipe was consumed for a ghost")
    end)
end

--- A real underground next to a ghost one must not hand out a free pipe
local function fixture_ghost_neighbour()
    begin("ghost neighbour gets a ghost pipe and costs nothing")
    step(function()
        paint("refined-concrete")
        stock{ [PIPE] = 10 }
    end)
    step(function() build_ghost(UNDERGROUND, world.a, defines.direction.south) end)
    step(function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step(function()
        check(pipe_at_gap() == nil, "a real pipe was placed next to a ghost underground")
        check(ghost_at_gap() == PIPE, "expected a pipe ghost, found " .. tostring(ghost_at_gap()))
        check(count(PIPE) == 10,
            "the pipe was placed for free or charged wrongly, inventory holds " .. count(PIPE))
    end)
end

--- One underground on its own should do nothing at all
local function fixture_no_neighbour()
    begin("a lone underground places nothing")
    step(function()
        paint("refined-concrete")
        stock{ [PIPE] = 10 }
    end)
    step(function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step(function()
        check(pipe_at_gap() == nil, "a pipe was placed with nothing to connect to")
        check(ghost_at_gap() == nil, "a ghost was placed with nothing to connect to")
        check(count(PIPE) == 10, "a pipe was consumed with nothing to connect to")
    end)
end

--- Ammoniacal ocean needs an ice platform to exist at all and then something
--- non-meltable on top of that, so the gap wants two stacked tile ghosts
local function fixture_ocean_ghosts()
    begin("ocean gap between ice platforms gets stacked cover ghosts")
    step(function()
        -- ice platform everywhere the undergrounds stand, ocean only in the gap.
        -- A blueprint will not put entity ghosts on open water, so the pair needs
        -- ground of its own; the gap is what drives the tile logic either way.
        paint("ice-platform")
        paint("ammoniacal-ocean", { left = world.left + 6, top = 5, width = 1, height = 1 })
        stock{}
        check(tile_at_gap() == "ammoniacal-ocean",
            "setup: the gap is " .. tile_at_gap() .. ", not ocean")
    end)
    step(function()
        -- An underground collides with the meltable layer, so it cannot be
        -- blueprinted onto bare ice any more than it can be built there. The game
        -- adds a cover ghost itself when a player shift-places; do the same here.
        for _, position in ipairs({ world.a, world.b }) do
            world.surface.create_entity{
                name = "tile-ghost", inner_name = "concrete", position = position,
                force = world.player.force, player = world.player,
            }
        end
    end)
    step(function() build_ghost(UNDERGROUND, world.a, defines.direction.south) end)
    step(function() build_ghost(UNDERGROUND, world.b, defines.direction.north) end)
    step(function()
        -- did the two undergrounds we are connecting actually get placed?
        local function describe(position, label)
            local ghost = world.surface.find_entity("entity-ghost", position)
            note(label .. " ghost: " .. tostring(ghost and ghost.ghost_name) ..
                 " dir " .. tostring(ghost and ghost.direction))
            local tile_ghosts = {}
            for _, tile_ghost in pairs(world.surface.find_entities_filtered{
                name = "tile-ghost", position = position
            }) do
                tile_ghosts[#tile_ghosts + 1] = tile_ghost.ghost_prototype.name
            end
            note(label .. " tile " .. world.surface.get_tile(position.x, position.y).name ..
                 ", tile ghosts: " .. (#tile_ghosts > 0 and table.concat(tile_ghosts, "+") or "none"))
        end
        describe(world.a, "A")
        describe(world.b, "B")
        note("gap tile " .. tile_at_gap())

        check(ghost_at_gap() == PIPE, "expected a pipe ghost, found " .. tostring(ghost_at_gap()))
        local covers = tile_ghosts_at_gap()
        check(#covers == 2,
            "expected an ice platform ghost and a cover on top of it, found " ..
            #covers .. " (" .. table.concat(covers, ", ") .. ")")
    end)
end

--- Undo is the one thing Lua cannot reach: LuaUndoRedoStack can read, tag and
--- remove entries but never perform one. Only a real ctrl+z proves that the tile
--- the mod registered actually comes back out.
local function fixture_undo()
    begin("ctrl+z queues the cover tile for removal with the underground")
    step(function()
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        stock{ [PIPE] = 10, ["refined-concrete"] = 10 }
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step(function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step(function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step(function()
        -- the state we are about to undo has to be the state we think it is
        check(same_tile(tile_at_gap(), "refined-concrete"),
            "setup: the gap was never covered, it is " .. tile_at_gap())
        check(count("refined-concrete") == 9,
            "setup: the cover tile was not paid for, inventory holds " .. count("refined-concrete"))
        -- is there anything for ctrl+z to act on at all?
        local stack = world.player.undo_redo_stack
        note("undo items: " .. stack.get_undo_item_count())
        for index = 1, math.min(2, stack.get_undo_item_count()) do
            local kinds = {}
            for _, action in pairs(stack.get_undo_item(index)) do
                kinds[#kinds + 1] = tostring(action.type)
            end
            note("  item " .. index .. ": " .. #kinds .. " actions [" ..
                 table.concat(kinds, ", ") .. "]")
        end
        note("controller: " .. tostring(world.player.controller_type) ..
             " (god is " .. tostring(defines.controllers.god) .. ")")

        world.player.teleport(world.b, world.surface)
        log("AUPC-AWAIT-PROBE")
    end)
    step(function()
        -- does any synthetic key reach the game?
        if not probe_seen then return "again" end
    end)
    step(function()
        note("synthetic input reaches the game: " .. tostring(probe_seen))
        -- an undo pushes onto the redo stack, which is a far better signal that
        -- the keypress landed than guessing what the undo will have removed
        world.redo_before = world.player.undo_redo_stack.get_redo_item_count()
        log("AUPC-AWAIT-UNDO")
    end)
    step(function()
        if world.player.undo_redo_stack.get_redo_item_count() == world.redo_before then
            return "again"
        end
    end)
    step(function()
        local stack = world.player.undo_redo_stack
        if stack.get_redo_item_count() == world.redo_before then
            current.skipped = true
            note(probe_seen
                and "keys arrive but ctrl+z did not undo anything"
                or  "no synthetic input reached the game at all")
            return
        end
        note("after ctrl+z: " .. stack.get_undo_item_count() .. " undo, " ..
             stack.get_redo_item_count() .. " redo")

        local function whats_at(position, label)
            local names = {}
            for _, entity in pairs(world.surface.find_entities{
                { position.x - 0.4, position.y - 0.4 }, { position.x + 0.4, position.y + 0.4 }
            }) do
                names[#names + 1] = entity.name ..
                    (entity.name == "entity-ghost" and "(" .. entity.ghost_name .. ")" or "")
            end
            note(label .. ": " .. (#names > 0 and table.concat(names, "+") or "empty"))
        end
        whats_at(world.a, "at A after undo")
        whats_at(world.b, "at B after undo")
        whats_at(world.gap, "at gap after undo")

        -- 2.0 undo does not revert anything on the spot: it issues deconstruction
        -- orders for bots. Without bots the tile stays put and gains a proxy, so
        -- that proxy is the evidence the cover tile was part of the undo item.
        local proxies = world.surface.find_entities_filtered{
            name = "deconstructible-tile-proxy", position = world.gap,
        }
        check(#proxies == 1,
            "the cover tile the mod placed was not queued for removal by the undo")

        local underground = world.surface.find_entity(UNDERGROUND, world.b)
        check(underground ~= nil and underground.to_be_deconstructed(),
            "the underground was not part of the undo item the tile joined")

        -- the connector turns out to be in the undo item too, which is more than
        -- expected: create_entity has no undo parameter, so the engine is
        -- attributing it to the player action that triggered it
        local connector = pipe_at_gap()
        check(connector ~= nil and connector.to_be_deconstructed(),
            "the connector pipe was left behind by the undo")
    end)
end

--- Freeplay's controller: a real body, a real inventory, and a build reach
local function fixture_character()
    begin("character controller: pays for the connector out of the character")
    step(function()
        paint("refined-concrete")
        local character = world.surface.create_entity{
            name = "character", position = { x = world.left + 9.5, y = 5.5 },
            force = world.player.force,
        }
        if not check(character ~= nil, "could not create a character to control") then return end
        world.player.set_controller{ type = defines.controllers.character, character = character }
        world.stand = { x = world.left + 9.5, y = 5.5 }
        note("controller: " .. tostring(world.player.controller_type) ..
             " (character is " .. tostring(defines.controllers.character) .. ")")
        stock{ [PIPE] = 10 }
        check(count(PIPE) == 10, "the character has no usable main inventory")
    end)
    step(function()
        build_real(UNDERGROUND, world.a, defines.direction.south, world.stand)
    end)
    step(function()
        build_real(UNDERGROUND, world.b, defines.direction.north, world.stand)
    end)
    step(function()
        check(pipe_at_gap() ~= nil, "no connector was placed")
        check(ghost_at_gap() == nil,
            "a ghost was placed instead of a real pipe, " .. tostring(ghost_at_gap()))
        check(count(PIPE) == 9, "expected one pipe consumed, character holds " .. count(PIPE))
    end)
end

--- Map view: cannot move or change items, can only order ghosts
local function fixture_remote()
    begin("remote view: connector is a ghost and costs nothing")
    step(function()
        paint("refined-concrete")
        stock{ [PIPE] = 10 }
        world.player.set_controller{
            type = defines.controllers.remote,
            position = world.b,
            surface = world.surface,
        }
        note("controller: " .. tostring(world.player.controller_type) ..
             " (remote is " .. tostring(defines.controllers.remote) .. ")")
        note("has a main inventory: " .. tostring(world.player.get_main_inventory() ~= nil))
    end)
    -- Ordering ghosts is what remote view can actually do. build_from_cursor
    -- ignores the restriction and builds for real, which no player can, so it
    -- would test the API rather than the mod.
    step(function() build_ghost(UNDERGROUND, world.a, defines.direction.south) end)
    step(function() build_ghost(UNDERGROUND, world.b, defines.direction.north) end)
    step(function()
        note("at the gap: ghost=" .. tostring(ghost_at_gap()) ..
             " real=" .. tostring(pipe_at_gap() ~= nil))
        check(pipe_at_gap() == nil, "a real pipe was built from remote view")
        check(ghost_at_gap() == PIPE,
            "expected a ghost connector, found " .. tostring(ghost_at_gap()))
        check(count(PIPE) == 10, "the mod charged for a ghost, inventory holds " .. count(PIPE))
    end)
end

--- Nothing to pay with is not a reason to place a ghost when nothing is charged
local function fixture_editor_free()
    begin("editor mode: builds real with an empty inventory")
    step(function()
        world.player.set_controller{ type = defines.controllers.editor }
        game.tick_paused = false
        world.player.teleport(world.b, world.surface)
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        local inventory = world.player.get_main_inventory()
        if inventory then inventory.clear() end
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step(function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step(function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step(function()
        check(pipe_at_gap() ~= nil, "no connector was placed")
        check(ghost_at_gap() == nil,
            "a ghost was placed for want of an item that costs nothing, " ..
            tostring(ghost_at_gap()))
        check(same_tile(tile_at_gap(), "refined-concrete"),
            "the gap was not covered with a real tile, it is " .. tile_at_gap())
        check(#tile_ghosts_at_gap() == 0,
            "a cover ghost was placed for want of an item that costs nothing")
    end)
end

--- Editor mode is the other half of undo: placements are free and an undo takes
--- effect on the spot rather than queueing deconstruction for bots.
local function fixture_editor_undo()
    begin("editor mode: undo reverts the cover tile immediately")
    step(function()
        world.player.set_controller{ type = defines.controllers.editor }
        -- the map editor pauses entity updates, which also stops on_tick and would
        -- strand the rest of the run with no report at all
        game.tick_paused = false
        world.player.teleport(world.b, world.surface)
        note("controller: " .. tostring(world.player.controller_type) ..
             " (editor is " .. tostring(defines.controllers.editor) .. ")")
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step(function()
        local inventory = world.player.get_main_inventory()
        if inventory then
            inventory.clear()
            inventory.insert{ name = PIPE, count = 10 }
            inventory.insert{ name = "refined-concrete", count = 10 }
            note("editor inventory holds " .. inventory.get_item_count(PIPE) .. " pipes")
        else
            note("the editor controller has no main inventory")
        end
    end)
    step(function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step(function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step(function()
        check(pipe_at_gap() ~= nil, "no connector was placed in editor mode")
        check(same_tile(tile_at_gap(), "refined-concrete"),
            "the gap was not covered, it is " .. tile_at_gap())
        -- the game does not charge for a build in editor mode, so neither should we
        local inventory = world.player.get_main_inventory()
        if inventory then
            check(inventory.get_item_count(PIPE) == 10,
                "the mod charged for a pipe in editor mode, " ..
                inventory.get_item_count(PIPE) .. " left of 10")
            check(inventory.get_item_count("refined-concrete") == 10,
                "the mod charged for a cover tile in editor mode, " ..
                inventory.get_item_count("refined-concrete") .. " left of 10")
        end
        world.redo_before = world.player.undo_redo_stack.get_redo_item_count()
        log("AUPC-AWAIT-UNDO")
    end)
    step(function()
        if world.player.undo_redo_stack.get_redo_item_count() == world.redo_before then
            return "again"
        end
    end)
    step(function()
        if world.player.undo_redo_stack.get_redo_item_count() == world.redo_before then
            current.skipped = true
            note("no undo arrived, so nothing was checked")
            return
        end
        note("gap tile after undo: " .. tile_at_gap())
        check(tile_at_gap() == "ice-rough",
            "the cover tile was not reverted, the gap is " .. tile_at_gap())
        check(world.surface.find_entity(UNDERGROUND, world.b) == nil,
            "the underground survived an editor mode undo")
        check(pipe_at_gap() == nil, "the connector survived an editor mode undo")
    end)
end

--------------------------------------------------------------------------- driver

local function prepare(player)
    local aquilo = game.planets and game.planets["aquilo"]
    if not aquilo then error("no aquilo planet; is space-age enabled?") end
    local surface = aquilo.surface or aquilo.create_surface()

    -- painting only works on generated chunks
    surface.request_to_generate_chunks({ x = 0, y = 0 }, 12)
    surface.force_generate_chunk_requests()

    player.set_controller{ type = defines.controllers.god }
    player.teleport({ x = 0, y = 0 }, surface)

    world.surface = surface
    world.player = player
    world.patch = 0
    report.surface = surface.name
end

local function finish()
    helpers.write_file(RESULTS_FILE, serpent.dump(report))
    log(SENTINEL)
end

fixture_plain_ground()
fixture_ice_gap_with_cover()
fixture_ice_gap_without_cover()
fixture_ghost_neighbour()
fixture_no_neighbour()
fixture_ocean_ghosts()
fixture_undo()
fixture_character()
fixture_remote()
fixture_editor_free()
fixture_editor_undo()

script.on_event("aupc-tests-probe", function()
    probe_seen = true
end)

script.on_event(defines.events.on_tick, function()
    if finished then return end
    -- nothing in this scenario wants a paused game; a pause here means no report
    if game.tick_paused then game.tick_paused = false end
    local player = game.players[1]
    if not player then return end
    if game.tick < 30 then return end

    if not world.surface then
        local ok, err = pcall(prepare, player)
        if not ok then
            report.error = "prepare failed: " .. tostring(err)
            finished = true
            finish()
        end
        return
    end

    if step_index > #steps then
        finished = true
        finish()
        return
    end

    if world.running_step ~= step_index then
        world.running_step = step_index
        world.step_started = game.tick
    end

    local this_step = steps[step_index]
    local ok, err = pcall(this_step)
    -- a step that returns "again" is waiting on something outside the game
    if ok and err == "again" and game.tick - world.step_started < WAIT_TICKS then
        return
    end
    step_index = step_index + 1
    if not ok then
        local where = current and current.name or "before the first fixture"
        report.error = ("step %d (%s) failed: %s"):format(step_index - 1, where, tostring(err))
        finished = true
        finish()
    end
end)
