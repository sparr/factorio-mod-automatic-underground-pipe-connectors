--- A blueprint says what the player asked for, so the mod has no business editing it.
local world = require("test.ft.world")

local PIPE, UNDERGROUND = world.PIPE, world.UNDERGROUND
local SOUTH, NORTH = defines.direction.south, defines.direction.north

--- Lay the pair down without waking the mod: create_entity's raise_built fires
--- script_raised_built, which the mod does not listen to.
local function lay_facing_pair(patch)
    for _, place in ipairs({ { patch.a, SOUTH }, { patch.b, NORTH } }) do
        patch.surface.create_entity{ name = UNDERGROUND, position = place[1],
            direction = place[2], force = patch.player.force, raise_built = true }
    end
    assert.is_true(patch.pipe_at() == nil and patch.ghost_at() == nil,
        "setup: something already filled the gap before the blueprint existed")
end

describe("a blueprint drawn with a deliberate gap", function()
    test("stamped from the cursor is left exactly as drawn", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        lay_facing_pair(patch)

        local captured = patch.restamp{ { patch.a.x - 0.5, patch.a.y - 0.5 },
                                        { patch.b.x + 0.5, patch.b.y + 0.5 } }
        assert.equals(2, captured, "the blueprint should hold exactly the two undergrounds")

        local undergrounds = patch.surface.find_entities_filtered{
            ghost_name = UNDERGROUND, area = patch.area }
        assert.equals(2, #undergrounds,
            "expected the blueprint's two underground ghosts, found " .. #undergrounds)
        -- derived from where the stamp actually landed rather than where we asked
        local names = patch.occupants(world.in_front_of(undergrounds[1]))
        assert.equals(0, #names,
            "the mod filled a gap the blueprint drew deliberately: " .. table.concat(names, "+"))
    end)

    --- A known gap, pinned rather than fixed.
    ---
    --- build_blueprint fires on_built_entity whenever by_player is given, so an
    --- API-driven stamp reaches the mod exactly as a hand placement does, while nothing
    --- in the cursor says a blueprint is involved. There is no creation tick on an
    --- entity to ask instead, and same-tick bookkeeping cannot stand in for one: the
    --- game creates all of a stamp's entities before raising any of their events, so
    --- the first underground already sees the second. Closing it properly means
    --- deferring every connector to the end of the tick, which would split the cover
    --- tile out of the player's undo item and make ctrl+z two steps for everybody, to
    --- fix a path only other mods take.
    ---
    --- So this asserts what the mod does today, not what it ought to do. If it fails
    --- because the gap came back empty, something has fixed the gap: flip the check and
    --- delete this.
    test("stamped through the API still gets a connector (known gap)", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }
        lay_facing_pair(patch)

        local captured = patch.restamp_via_api{ { patch.a.x - 0.5, patch.a.y - 0.5 },
                                                { patch.b.x + 0.5, patch.b.y + 0.5 } }
        assert.equals(2, captured, "the blueprint should hold exactly the two undergrounds")
        assert.is_false(patch.player.cursor_stack.valid_for_read,
            "setup: a blueprint in the cursor would let the mod off the hook")

        local undergrounds = patch.surface.find_entities_filtered{
            ghost_name = UNDERGROUND, area = patch.area }
        assert.equals(2, #undergrounds,
            "expected the blueprint's two underground ghosts, found " .. #undergrounds)
        local names = patch.occupants(world.in_front_of(undergrounds[1]))
        assert.is_true(#names > 0,
            "the API stamp was left alone, so the known gap is closed: make this " ..
            "test assert an empty gap instead")
    end)

    --- The other half of the same question: a blueprint that aims an underground at
    --- its own tank is still drawn as the player drew it.
    test("aiming an underground at its own tank is stamped as drawn", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }

        local tank = patch.surface.create_entity{
            name = "storage-tank", position = { x = patch.left + 6.5, y = patch.top + 2.5 },
            direction = SOUTH, force = patch.player.force, raise_built = true }
        assert.is_not_nil(tank, "could not place the tank")

        -- downward only: the engine lays a stamp out in its own order, and putting the
        -- tank above the underground is what makes the tank the one already standing
        -- there when the mod wakes up
        local connection = patch.reachable_connection(tank, true)
        assert.is_not_nil(connection,
            "setup: found nowhere to aim an underground at the tank")
        patch.surface.create_entity{ name = UNDERGROUND, position = connection.spot,
            direction = connection.facing, force = patch.player.force, raise_built = true }

        local captured = patch.restamp(patch.area)
        print("blueprint captured " .. captured .. " entities")

        local underground = patch.surface.find_entities_filtered{
            ghost_name = UNDERGROUND, area = patch.area }[1]
        assert.is_not_nil(underground, "the blueprint did not put its underground down")
        local names = {}
        for _, name in ipairs(patch.occupants(world.in_front_of(underground))) do
            -- the tank's own ghost is the blueprint's, not something the mod added
            if name ~= "entity-ghost/storage-tank" then names[#names + 1] = name end
        end
        assert.equals(0, #names,
            "the mod added a connector the blueprint did not ask for: " ..
            table.concat(names, "+"))
    end)
end)

--- Issue #19, from the blueprint on the report. An underground opens south into two
--- storage tanks sitting side by side; relative to the underground, tank A is at
--- (-2,+2) and tank B at (+1,+2).
---
--- The ordering is what does the damage. With tank A down and the underground down, the
--- tile tank B is about to occupy is still empty, while tank A's side connection points
--- straight at it -- so the mod fills it with a connector and the tank that was meant to
--- go there no longer fits. The report reads as the blueprint deleting a tank; really
--- the tank never gets placed.
---
--- This fixture does not fail without the blueprint check, and cannot on 2.1: the engine
--- creates every entity of a stamp before raising any of their build events, so tank B is
--- already standing there when the mod looks and the occupancy guard turns it away. It
--- guards the outcome rather than the mechanism. What actually makes the mod safe here is
--- that it ignores a stamp outright, which holds whatever order the engine builds in.
describe("the issue 19 blueprint", function()
    test("lands whole, with no connector wedged into it", function()
        local patch = world.patch()
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [UNDERGROUND] = 10 }

        patch.player.cursor_stack.set_stack{ name = "blueprint" }
        -- positions relative to the underground, in the order the report's blueprint
        -- lists them: the underground first, then the two tanks
        patch.player.cursor_stack.set_blueprint_entities{
            { entity_number = 1, name = UNDERGROUND, position = { 0, 0 }, direction = SOUTH },
            { entity_number = 2, name = "storage-tank", position = { -2, 2 },
              direction = defines.direction.east },
            { entity_number = 3, name = "storage-tank", position = { 1, 2 },
              direction = NORTH },
        }
        patch.player.build_from_cursor{ position = patch.gap }
        patch.player.cursor_stack.clear()

        local tanks = patch.surface.find_entities_filtered{
            ghost_name = "storage-tank", area = patch.area }
        local undergrounds = patch.surface.find_entities_filtered{
            ghost_name = UNDERGROUND, area = patch.area }
        local connectors = patch.surface.find_entities_filtered{
            ghost_name = PIPE, area = patch.area }
        assert.equals(1, #undergrounds,
            "expected the blueprint's underground, found " .. #undergrounds)
        assert.equals(0, #connectors,
            "the mod wedged " .. #connectors .. " connector(s) into the blueprint")
        assert.equals(2, #tanks,
            "the blueprint should have placed both tanks, only " .. #tanks .. " landed")
    end)
end)
