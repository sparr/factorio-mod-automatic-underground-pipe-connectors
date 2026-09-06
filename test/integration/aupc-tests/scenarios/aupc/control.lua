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

-- Written by setup.sh next to this file. Absent means a plain headless run.
local ok_mode, mode = pcall(require, "mode")
if not ok_mode or type(mode) ~= "table" then mode = { walkthrough = false } end

local report = { fixtures = {} }
local steps = {}
local step_index = 1
local finished = false
local probe_seen = false
local current
local world = {}

--------------------------------------------------------------------------- plumbing

--- @param label string? user-facing description, nil for internal bookkeeping
local function step(label, fn)
    local entry = { label = label, fn = fn }
    steps[#steps + 1] = entry
    return entry
end

--------------------------------------------------------------------- walkthrough

local FRAME = "aupc-walkthrough"
local walk = {
    waiting = false,    -- a prompt is up and the run is holding for it
    run_rest = false,   -- finish without stopping again
    skipping = false,   -- fast forward to the next fixture
    stopped = false,
    prompted_for = nil, -- step index the current prompt belongs to
    last = nil,         -- outcome of the step just run
}

local CONTROLLER_NAMES = {}
for name, value in pairs(defines.controllers) do CONTROLLER_NAMES[value] = name end

--- @param caption string
--- @return LuaGuiElement frame
--- @return boolean is_new
local function ensure_frame(caption)
    local player = world.player
    local existing = player.gui.screen[FRAME]
    if existing and existing.valid then return existing, false end

    local frame = player.gui.screen.add{
        type = "frame", name = FRAME, direction = "vertical", caption = caption }
    -- a strip to drag it by, since a bare frame cannot be moved. Untested: synthetic
    -- mouse input does not reach the GUI on Xvfb, so this was never clicked here.
    local grip = frame.add{ type = "empty-widget", name = "grip",
        style = "draggable_space_header" }
    grip.style.height = 16
    grip.style.horizontally_stretchable = true
    grip.drag_target = frame

    local text = frame.add{ type = "label", name = "body" }
    text.style.single_line = false
    text.style.maximal_width = 440
    text.style.bottom_margin = 8
    frame.add{ type = "flow", name = "buttons", direction = "horizontal" }
    return frame, true
end

--- @param title string
--- @param body string
--- @param with_next boolean whether a click advances, or something else does
---
--- Built once and relabelled after that, so a frame the player has dragged
--- somewhere stays there. Positioned only on the first prompt, and only once the
--- children exist: near the top edge the frame renders with its upper rows cut
--- off, which silently loses the caption and then the body as it grows.
local function show_prompt(title, body, with_next)
    local player = world.player
    if not player then return end
    local caption = title .. "  [" .. (CONTROLLER_NAMES[player.controller_type] or "?") .. "]"
    local frame, is_new = ensure_frame(caption)
    frame.caption = caption
    frame.body.caption = body

    local buttons = frame.buttons
    buttons.clear()
    if with_next then
        -- deliberately the plain button style: confirm_button advertises E as its
        -- shortcut, and E is the inventory key, so the hint would be a lie
        buttons.add{ type = "button", name = "aupc-next", caption = "Next" }
    end
    buttons.add{ type = "button", name = "aupc-skip", caption = "Skip fixture" }
    buttons.add{ type = "button", name = "aupc-rest", caption = "Run the rest" }
    buttons.add{ type = "button", name = "aupc-stop", caption = "Stop" }

    if is_new then
        -- bottom left, clear of the camera focus at the centre and of the hotbar
        local resolution = player.display_resolution
        frame.location = { x = 16, y = math.max(16, resolution.height - 260) }
    end
    log("AUPC-PROMPT " .. title .. " | " .. body:gsub("\n", " "))
end

--- Ask the player to press the key themselves, so a watched run never needs
--- synthetic input aimed at a desktop they are using
local function prompt_for_undo()
    show_prompt("Undo", "Press ctrl+z in the game window.\n\n" ..
        "The run continues as soon as the undo reaches the redo stack.", false)
end

script.on_event(defines.events.on_gui_click, function(event)
    local element = event.element
    if not (element and element.valid) then return end
    if element.name == "aupc-next" then
        walk.waiting = false
    elseif element.name == "aupc-skip" then
        walk.waiting = false
        walk.skipping = true
        if current then current.skipped = true end
    elseif element.name == "aupc-rest" then
        walk.waiting = false
        walk.run_rest = true
    elseif element.name == "aupc-stop" then
        walk.waiting = false
        walk.stopped = true
    else
        return
    end
end)

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
    -- marked so "skip fixture" knows where the next one starts
    step(nil, function()
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

        -- Frame the patch once per fixture and leave it there. Re-centring on
        -- every placement made it hard to see what had actually changed.
        if world.player then
            world.player.teleport({ x = left + 6.5, y = 5.5 }, world.surface)
        end
    end).boundary = true
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

--- Take the item out of the player's own inventory rather than conjuring it into
--- the cursor. Otherwise the fixture builds the undergrounds for free and then
--- watches the mod pay for the connector, which is not a situation any player is
--- ever in. Editor and remote have nothing to draw from, and the game charges
--- nothing in either, so those fall back to a stack from thin air.
local function build_real(name, position, direction, stand_at)
    -- Only move for a caller that asks: a character has to stand clear of its own
    -- build site, but moving for every placement drags the camera off the patch.
    if stand_at then world.player.teleport(stand_at, world.surface) end
    local inventory = world.player.get_main_inventory()
    local stack = inventory and inventory.find_item_stack(name)
    if stack then
        world.player.cursor_stack.swap_stack(stack)
    else
        world.player.cursor_stack.set_stack{ name = name, count = 1 }
    end
    world.player.build_from_cursor{ position = position, direction = direction }
    if inventory and world.player.cursor_stack.valid_for_read then
        inventory.insert(world.player.cursor_stack)
    end
    world.player.cursor_stack.clear()
end

--- The API has no shift-click equivalent, so a one-entity blueprint stands in.
--- It still reaches the mod as a real on_built_entity with a player index.
local function build_ghost(name, position, direction, stand_at)
    -- remote view builds where it is looking, so that one has to move; everything
    -- else keeps the camera parked on the patch
    if stand_at then world.player.teleport(stand_at, world.surface) end
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
    step("paint the patch with refined concrete and stock pipes and undergrounds", function()
        paint("refined-concrete")
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        check(same_tile(tile_at_gap(), "refined-concrete"),
            "setup: the gap is " .. tile_at_gap() .. ", not refined concrete")
    end)
    step("build underground A, facing south", function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step("confirm nothing was placed yet, then build underground B facing north", function()
        check(pipe_at_gap() == nil, "a pipe appeared before the second underground existed")
        build_real(UNDERGROUND, world.b, defines.direction.north)
    end)
    step("check a real pipe filled the gap and one pipe was spent", function()
        check(pipe_at_gap() ~= nil, "no pipe was placed in the gap")
        check(ghost_at_gap() == nil, "a ghost was placed instead of a real pipe")
        check(count(PIPE) == 9, "expected one pipe consumed, inventory holds " .. count(PIPE))
        check(count(UNDERGROUND) == 8,
            "both undergrounds should have been paid for too, inventory holds " ..
            count(UNDERGROUND))
        check(same_tile(tile_at_gap(), "refined-concrete"),
            "the ground was changed to " .. tile_at_gap())
        check(#tile_ghosts_at_gap() == 0, "an unnecessary tile ghost was placed")
    end)
end

--- The gap is meltable, the player is carrying something that can cover it
local function fixture_ice_gap_with_cover()
    begin("meltable gap gets a real cover tile when the item is held")
    step("paint refined concrete with an ice gap, stock pipes, undergrounds and cover tiles", function()
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        stock{ [PIPE] = 10, [UNDERGROUND] = 10, ["refined-concrete"] = 10 }
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step("build underground A, facing south", function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step("record the ground the mod will see, then build underground B", function()
        -- the state the mod will actually see, captured before it runs
        note("at build time, under A: " .. world.surface.get_tile(world.a.x, world.a.y).name)
        note("at build time, under B: " .. world.surface.get_tile(world.b.x, world.b.y).name)
        note("at build time, gap: " .. tile_at_gap())
        build_real(UNDERGROUND, world.b, defines.direction.north)
    end)
    step("check the gap was covered with a real tile and both items were spent", function()
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
    step("paint refined concrete with an ice gap, stock pipes and undergrounds but no cover tiles", function()
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step("build underground A, facing south", function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step("build underground B, facing north", function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step("check the mod fell back to a pipe ghost over a cover ghost", function()
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
    begin("real underground beside a ghost one gets a real pipe, paid for")
    step("paint refined concrete and stock pipes and undergrounds", function()
        paint("refined-concrete")
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
    end)
    step("blueprint a ghost underground at A",
        function() build_ghost(UNDERGROUND, world.a, defines.direction.south) end)
    step("build a real underground at B, next to the ghost",
        function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step("check the connector matches the real placement and was paid for", function()
        -- the neighbour being a ghost is irrelevant; the player placed a real
        -- underground, so they get a real pipe and are charged for it
        check(pipe_at_gap() ~= nil, "no connector was placed")
        check(ghost_at_gap() == nil,
            "the neighbour's ghostness leaked into the connector, found " ..
            tostring(ghost_at_gap()))
        check(count(PIPE) == 9, "expected one pipe consumed, inventory holds " .. count(PIPE))
    end)
end

--- The mirror of the case above: the placement is a ghost, so the connector is
local function fixture_ghost_placement_beside_real()
    begin("ghost underground beside a real one gets a ghost, free")
    step("paint refined concrete and stock pipes and undergrounds", function()
        paint("refined-concrete")
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
    end)
    step("build a real underground at A",
        function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step("blueprint a ghost underground at B",
        function() build_ghost(UNDERGROUND, world.b, defines.direction.north) end)
    step("check the connector is a ghost and nothing was spent", function()
        check(pipe_at_gap() == nil, "a real pipe was placed for a ghost placement")
        check(ghost_at_gap() == PIPE, "expected a pipe ghost, found " .. tostring(ghost_at_gap()))
        check(count(PIPE) == 10, "a ghost connector was charged for, inventory holds " .. count(PIPE))
    end)
end

--- A real placement wants a real pipe, but an empty pocket cannot pay for one
local function fixture_no_pipe_in_inventory()
    begin("real pair with no pipe in inventory falls back to a ghost, free")
    step("paint refined concrete and stock undergrounds but no pipes", function()
        paint("refined-concrete")
        stock{ [UNDERGROUND] = 10 }
        check(count(PIPE) == 0, "setup: the player should hold no pipes")
    end)
    step("build underground A, facing south",
        function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step("build underground B, facing north",
        function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step("check the connector fell back to a ghost and cost nothing", function()
        check(pipe_at_gap() == nil, "a real pipe was placed without one to pay with")
        check(ghost_at_gap() == PIPE, "expected a pipe ghost, found " .. tostring(ghost_at_gap()))
        check(count(PIPE) == 0, "pipes appeared from nowhere, inventory holds " .. count(PIPE))
        check(count(UNDERGROUND) == 8,
            "both undergrounds should still have been paid for, inventory holds " ..
            count(UNDERGROUND))
    end)
end

--- One underground on its own should do nothing at all
local function fixture_no_neighbour()
    begin("a lone underground places nothing")
    step("paint refined concrete and stock pipes and undergrounds", function()
        paint("refined-concrete")
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
    end)
    step("build a single underground at B, with nothing to connect to",
        function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step("check nothing at all was placed", function()
        check(pipe_at_gap() == nil, "a pipe was placed with nothing to connect to")
        check(ghost_at_gap() == nil, "a ghost was placed with nothing to connect to")
        check(count(PIPE) == 10, "a pipe was consumed with nothing to connect to")
    end)
end

--- Ammoniacal ocean needs an ice platform to exist at all and then something
--- non-meltable on top of that, so the gap wants two stacked tile ghosts
local function fixture_ocean_ghosts()
    begin("ocean gap between ice platforms gets stacked cover ghosts")
    step("paint ice platform, leaving one tile of ammoniacal ocean in the gap", function()
        -- ice platform everywhere the undergrounds stand, ocean only in the gap.
        -- A blueprint will not put entity ghosts on open water, so the pair needs
        -- ground of its own; the gap is what drives the tile logic either way.
        paint("ice-platform")
        paint("ammoniacal-ocean", { left = world.left + 6, top = 5, width = 1, height = 1 })
        stock{}
        check(tile_at_gap() == "ammoniacal-ocean",
            "setup: the gap is " .. tile_at_gap() .. ", not ocean")
    end)
    step("add the cover ghosts the game adds when shift-placing onto ice", function()
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
    step("blueprint a ghost underground at A",
        function() build_ghost(UNDERGROUND, world.a, defines.direction.south) end)
    step("blueprint a ghost underground at B",
        function() build_ghost(UNDERGROUND, world.b, defines.direction.north) end)
    step("check the gap got a pipe ghost over two stacked cover ghosts", function()
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
    step("paint refined concrete with an ice gap, stock pipes, undergrounds and cover tiles", function()
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        stock{ [PIPE] = 10, [UNDERGROUND] = 10, ["refined-concrete"] = 10 }
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step("build underground A, facing south", function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step("build underground B, facing north", function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step("confirm the cover was placed and paid for, then ask for a probe keypress", function()
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

        world.player.teleport({ x = world.left + 6.5, y = 5.5 }, world.surface)
        if mode.walkthrough then
            -- a person is pressing the keys, so there is nothing to prove
            probe_seen = true
        else
            log("AUPC-AWAIT-PROBE")
        end
    end)
    step(nil, function()
        -- does any synthetic key reach the game?
        if not probe_seen then return "again" end
    end)
    step("ask for ctrl+z", function()
        note("synthetic input reaches the game: " .. tostring(probe_seen))
        -- an undo pushes onto the redo stack, which is a far better signal that
        -- the keypress landed than guessing what the undo will have removed
        world.redo_before = world.player.undo_redo_stack.get_redo_item_count()
        if mode.walkthrough then prompt_for_undo() else log("AUPC-AWAIT-UNDO") end
    end)
    step(nil, function()
        if world.player.undo_redo_stack.get_redo_item_count() == world.redo_before then
            return "again"
        end
    end)
    step("check the cover tile and both entities were queued for removal", function()
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

---@param dx integer
---@param dy integer
---@return defines.direction?
local function direction_of(dx, dy)
    if dx == 0 and dy == -1 then return defines.direction.north end
    if dx == 1 and dy == 0 then return defines.direction.east end
    if dx == 0 and dy == 1 then return defines.direction.south end
    if dx == -1 and dy == 0 then return defines.direction.west end
    return nil
end

--- An underground is not the only thing worth connecting to: the mod also joins
--- one to any entity whose fluidbox points at the gap. That entity goes down
--- first, so the underground is the second placement and the one that triggers it.
---@param entity_name string
---@param as_ghost boolean? place the neighbour as a ghost rather than a real entity
local function fixture_fluid_neighbour(entity_name, as_ghost)
    begin((as_ghost and "a ghost " or "") .. entity_name ..
        " connects to an underground aimed at its fluidbox")
    step("paint refined concrete and stock pipes and undergrounds", function()
        paint("refined-concrete")
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        world.facing = nil
    end)
    step("place the " .. entity_name, function()
        -- raise_built fires script_raised_built, not on_built_entity, so putting
        -- this down does not itself wake the mod
        world.neighbour = world.surface.create_entity{
            name = as_ghost and "entity-ghost" or entity_name,
            inner_name = as_ghost and entity_name or nil,
            position = { x = world.left + 6.5, y = 3.5 },
            direction = defines.direction.south,
            force = world.player.force,
            raise_built = true,
        }
        check(world.neighbour ~= nil, "could not place a " .. entity_name)
    end)
    step("aim an underground at one of its fluid connections", function()
        if not world.neighbour then return end
        -- 2.1 removed LuaFluidBox; the entity carries the count and the connections
        for index = 1, world.neighbour.fluids_count do
            for _, connection in pairs(world.neighbour.get_fluid_box_pipe_connections(index)) do
                local target = connection.target_position
                local dx = target.x - connection.position.x
                local dy = target.y - connection.position.y
                dx = dx > 0.25 and 1 or (dx < -0.25 and -1 or 0)
                dy = dy > 0.25 and 1 or (dy < -0.25 and -1 or 0)
                -- one tile further along, facing back, so the gap is exactly the target
                local facing = direction_of(-dx, -dy)
                local spot = { x = target.x + dx, y = target.y + dy }
                local clear = #world.surface.find_entities{
                    { spot.x - 0.4, spot.y - 0.4 }, { spot.x + 0.4, spot.y + 0.4 } } == 0
                if facing and clear then
                    world.gap = target
                    world.b = spot
                    world.facing = facing
                    note("connecting at " .. target.x .. "," .. target.y ..
                         " from an underground at " .. spot.x .. "," .. spot.y)
                    return
                end
            end
        end
        check(false, "no reachable fluid connection on the " .. entity_name)
    end)
    step("build the underground facing it", function()
        if not world.facing then return end
        build_real(UNDERGROUND, world.b, world.facing)
    end)
    step("check a connector filled the gap", function()
        if not world.facing then return end
        -- A ghost neighbour still gets a real pipe: only a ghost *underground* puts
        -- the mod into ghost mode. Recorded rather than judged; the point of the
        -- ghost case is that the neighbour is seen at all, which it was not in 2.0.
        check(pipe_at_gap() ~= nil, "no connector was placed against the " ..
            (as_ghost and "ghost " or "") .. entity_name)
        check(ghost_at_gap() == nil, "a ghost was placed instead of a real pipe")
        check(count(PIPE) == 9, "expected one pipe consumed, inventory holds " .. count(PIPE))
    end)
end

--- The occupancy guard used to refuse on anything sharing the tile. A character
--- standing on the gap is the case a player actually hits.
---@param blocker string? entity to stand on the gap, nil for the negative case
---@param label string
---@param expect_connector boolean
local function fixture_gap_occupant(blocker, label, expect_connector)
    begin(label)
    step("paint refined concrete and stock pipes and undergrounds", function()
        paint("refined-concrete")
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        world.blocker = nil
    end)
    step("put a " .. tostring(blocker) .. " on the gap", function()
        world.blocker = world.surface.create_entity{
            name = blocker, position = world.gap, force = world.player.force }
        check(world.blocker ~= nil, "could not place a " .. tostring(blocker) .. " on the gap")
    end)
    -- both ghosts, so the placement is a ghost and the occupancy guard is what
    -- decides. A real placement would go through can_place_entity instead.
    step("blueprint a ghost underground at A", function()
        build_ghost(UNDERGROUND, world.a, defines.direction.south)
    end)
    step("blueprint a ghost underground at B", function()
        build_ghost(UNDERGROUND, world.b, defines.direction.north)
    end)
    step("check whether a ghost connector appeared", function()
        local ghost = ghost_at_gap()
        note("at the gap: " .. tostring(ghost) .. ", blocker still there: " ..
             tostring(world.blocker ~= nil and world.blocker.valid))
        if expect_connector then
            check(ghost == PIPE,
                "the " .. tostring(blocker) .. " blocked a ghost it should not have, found " ..
                tostring(ghost))
        else
            check(ghost == nil,
                "a ghost was placed on top of a " .. tostring(blocker) .. ", found " .. tostring(ghost))
        end
        if world.blocker and world.blocker.valid then world.blocker.destroy() end
    end)
end

--- Freeplay's controller: a real body, a real inventory, and a build reach
local function fixture_character()
    begin("character controller: pays for the connector out of the character")
    step("create a character to control, and stock its inventory", function()
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
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        check(count(PIPE) == 10, "the character has no usable main inventory")
    end)
    step("build underground A from the character, standing clear of it", function()
        build_real(UNDERGROUND, world.a, defines.direction.south, world.stand)
    end)
    step("build underground B from the character", function()
        build_real(UNDERGROUND, world.b, defines.direction.north, world.stand)
    end)
    step("check the connector was paid for out of the character", function()
        check(pipe_at_gap() ~= nil, "no connector was placed")
        check(ghost_at_gap() == nil,
            "a ghost was placed instead of a real pipe, " .. tostring(ghost_at_gap()))
        check(count(PIPE) == 9, "expected one pipe consumed, character holds " .. count(PIPE))
    end)
end

--- Map view: cannot move or change items, can only order ghosts
local function fixture_remote()
    begin("remote view: connector is a ghost and costs nothing")
    step("stock pipes and undergrounds, then switch to remote view", function()
        paint("refined-concrete")
        stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        -- 2.1 remote view reports no main inventory even with a character, so hold
        -- onto the one we stocked; it is the character's and stays valid
        world.stocked = world.player.get_main_inventory()
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
    step("order a ghost underground at A",
        function() build_ghost(UNDERGROUND, world.a, defines.direction.south, world.a) end)
    step("order a ghost underground at B",
        function() build_ghost(UNDERGROUND, world.b, defines.direction.north, world.b) end)
    step("check the connector is a ghost and nothing was charged", function()
        note("at the gap: ghost=" .. tostring(ghost_at_gap()) ..
             " real=" .. tostring(pipe_at_gap() ~= nil))
        for label, position in pairs({ A = world.a, B = world.b }) do
            local ghost = world.surface.find_entity("entity-ghost", position)
            note(label .. ": ghost=" .. tostring(ghost and ghost.ghost_name) ..
                 " real=" .. tostring(world.surface.find_entity(UNDERGROUND, position) ~= nil))
        end
        note("physical controller: " .. tostring(world.player.physical_controller_type) ..
             ", character: " .. tostring(world.player.character ~= nil))

        check(pipe_at_gap() == nil, "a real pipe was built from remote view")
        check(ghost_at_gap() == PIPE,
            "expected a ghost connector, found " .. tostring(ghost_at_gap()))
        local held = world.stocked and world.stocked.valid and world.stocked.get_item_count(PIPE)
        check(held == 10, "the mod charged for a ghost, the character holds " .. tostring(held))
    end)
end

--- Nothing to pay with is not a reason to place a ghost when nothing is charged
local function fixture_editor_free()
    begin("editor mode: builds real with an empty inventory")
    step("switch to the editor, paint an ice gap, and empty the inventory", function()
        world.player.set_controller{ type = defines.controllers.editor }
        game.tick_paused = false
        world.player.teleport({ x = world.left + 6.5, y = 5.5 }, world.surface)
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        local inventory = world.player.get_main_inventory()
        if inventory then inventory.clear() end
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step("build underground A", function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step("build underground B", function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step("check a real pipe and a real cover appeared with nothing to pay", function()
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
    step("switch to the editor and paint an ice gap", function()
        world.player.set_controller{ type = defines.controllers.editor }
        -- the map editor pauses entity updates, which also stops on_tick and would
        -- strand the rest of the run with no report at all
        game.tick_paused = false
        world.player.teleport({ x = world.left + 6.5, y = 5.5 }, world.surface)
        note("controller: " .. tostring(world.player.controller_type) ..
             " (editor is " .. tostring(defines.controllers.editor) .. ")")
        paint("refined-concrete")
        paint("ice-rough", { left = world.left + 6, top = 5, width = 1, height = 1 })
        check(tile_at_gap() == "ice-rough", "setup: the gap is " .. tile_at_gap() .. ", not ice")
    end)
    step("stock pipes, undergrounds and cover tiles", function()
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
    step("build underground A", function() build_real(UNDERGROUND, world.a, defines.direction.south) end)
    step("build underground B", function() build_real(UNDERGROUND, world.b, defines.direction.north) end)
    step("check nothing was charged, then ask for ctrl+z", function()
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
        if mode.walkthrough then prompt_for_undo() else log("AUPC-AWAIT-UNDO") end
    end)
    step(nil, function()
        if world.player.undo_redo_stack.get_redo_item_count() == world.redo_before then
            return "again"
        end
    end)
    step("check the cover tile reverted and both entities vanished", function()
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
    log("AUPC-MODE walkthrough=" .. tostring(mode.walkthrough))
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
    if mode.walkthrough then
        local failures = 0
        for _, fixture in ipairs(report.fixtures) do
            if #fixture.failures > 0 then failures = failures + 1 end
        end
        show_prompt("Finished",
            #report.fixtures .. " fixtures, " .. failures .. " failed.\n\n" ..
            "The game is left running; quit it normally when you are done.", false)
    end
end

fixture_plain_ground()
fixture_ice_gap_with_cover()
fixture_ice_gap_without_cover()
fixture_ghost_neighbour()
fixture_ghost_placement_beside_real()
fixture_no_pipe_in_inventory()
fixture_no_neighbour()
fixture_fluid_neighbour("pump")
fixture_fluid_neighbour("storage-tank")
fixture_fluid_neighbour("storage-tank", true)
fixture_gap_occupant("character", "a character on the gap does not block a ghost connector", true)
fixture_gap_occupant("wooden-chest", "a real entity on the gap does block a ghost connector", false)
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

    local this_step = steps[step_index]

    if mode.walkthrough then
        if walk.stopped then
            finished = true
            show_prompt("Stopped",
                "Stopped after " .. #report.fixtures .. " fixtures. The report has been written; " ..
                "the game is left running.", false)
            finish()
            return
        end
        if walk.skipping then
            -- advance without running anything until the next fixture starts
            if not this_step.boundary then
                step_index = step_index + 1
                return
            end
            walk.skipping = false
        end
        -- steps with no label are bookkeeping or are waiting on something else,
        -- and a prompt of their own would replace the one already on screen
        if this_step.label and not walk.run_rest then
            if walk.prompted_for ~= step_index then
                walk.prompted_for = step_index
                walk.waiting = true
                show_prompt(
                    current and current.name or "starting up",
                    (walk.last and ("Last: " .. walk.last .. "\n\n") or "") ..
                    "Next: " .. this_step.label,
                    true)
                return
            end
            if walk.waiting then return end
        end
    end

    if world.running_step ~= step_index then
        world.running_step = step_index
        world.step_started = game.tick
    end

    local ok, err = pcall(this_step.fn)
    if not ok and current then
        -- otherwise the fixture that was running when the scenario died is
        -- reported with no failures at all, which prints as a pass
        current.failures[#current.failures + 1] =
            "the run stopped here: " .. tostring(err)
    end
    -- a step that returns "again" is waiting on something outside the game
    if ok and err == "again" and game.tick - world.step_started < WAIT_TICKS then
        return
    end
    step_index = step_index + 1
    if mode.walkthrough and this_step.label then
        local failures = current and #current.failures or 0
        walk.last = this_step.label ..
            (failures == 0 and " — ok" or (" — " .. failures .. " failure(s) so far"))
    end
    if not ok then
        local where = current and current.name or "before the first fixture"
        report.error = ("step %d (%s) failed: %s"):format(step_index - 1, where, tostring(err))
        finished = true
        finish()
    end
end)
