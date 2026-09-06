--- Issue #15: undergrounds that open somewhere other than the way they face.
---
--- The junction shapes come from test/ft/aupc-tests/data.lua, rebuilt from
--- Pipe Plus's own prototypes. North is the whole problem: a vanilla underground opens
--- on the side it faces, so "the tile ahead" and "the tile it opens onto" are the same
--- tile, and the mod used to take the first as a stand-in for the second.
local world = require("test.ft.world")

local PIPE = world.PIPE
local SOUTH, NORTH = defines.direction.south, defines.direction.north

--- Two junctions of the same kind facing each other head on, one tile apart.
--- The T opens east and west above ground and nowhere else, so it must be left alone.
--- The X also opens the way it faces, so it must still be joined: the fix is not
--- "ignore junctions".
local function head_on(name, expect_connector)
    local patch = world.patch()
    patch.paint("refined-concrete")
    patch.stock{ [PIPE] = 10, [name] = 10 }

    local openings = {}
    local proto = prototypes.entity[name]
    for index = 1, #proto.fluidbox_prototypes do
        for _, connection in pairs(proto.fluidbox_prototypes[index].pipe_connections) do
            openings[#openings + 1] = connection.connection_type
        end
    end
    print(name .. " connection types: " .. table.concat(openings, ","))

    patch.build(name, patch.a, SOUTH)
    assert(patch.pipe_at() == nil, "a pipe appeared before the second junction existed")
    patch.build(name, patch.b, NORTH)

    if expect_connector then
        assert(patch.pipe_at() ~= nil, "the junction opens onto the gap but got no connector")
        assert(patch.count(PIPE) == 9,
            "expected one pipe spent, inventory holds " .. patch.count(PIPE))
    else
        assert(patch.pipe_at() == nil,
            "a pipe was wedged onto a side the junction has no connection on")
        assert(patch.ghost_at() == nil,
            "a ghost was wedged onto a side the junction has no connection on")
        assert(patch.count(PIPE) == 10, "a pipe was spent, inventory holds " .. patch.count(PIPE))
    end
end

describe("a junction underground", function()
    test("is not bridged on a side it has no connection on", function()
        head_on("aupc-tests-t-junction", false)
    end)

    test("is still bridged on a side it does open onto", function()
        head_on("aupc-tests-x-junction", true)
    end)

    --- Two T junctions set side by side, one tile apart on the axis they actually open
    --- along. Nothing about this is straight ahead of either, so it only works once
    --- connector tiles come from the openings themselves rather than from the way the
    --- entity faces.
    test("is joined along the arms it does open on", function()
        local patch = world.patch()
        local TILE = "aupc-tests-t-junction"
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [TILE] = 10 }
        local left_j = { x = patch.left + 4.5, y = patch.top + 5.5 }
        local right_j = { x = patch.left + 6.5, y = patch.top + 5.5 }
        local arm_gap = { x = patch.left + 5.5, y = patch.top + 5.5 }

        patch.build(TILE, left_j, SOUTH, patch.stand)
        assert(patch.pipe_at(arm_gap) == nil, "a pipe appeared before the second junction existed")
        patch.build(TILE, right_j, SOUTH, patch.stand)

        assert(patch.pipe_at(arm_gap) ~= nil,
            "the two junctions open onto the same tile but got no connector")
        assert(patch.count(PIPE) == 9,
            "expected one pipe spent, inventory holds " .. patch.count(PIPE))
    end)

    --- One placement, two connectors. An X junction dropped between two partners opens
    --- onto a gap on either side, and each is somewhere a pipe belongs, so both get one
    --- and both are paid for. Placing a single connector per build was only ever an
    --- assumption of the old straight-ahead geometry.
    test("dropped between two partners is joined on both arms", function()
        local patch = world.patch()
        local TILE = "aupc-tests-x-junction"
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [TILE] = 10 }
        local mid = { x = patch.left + 4.5, y = patch.top + 5.5 }
        local west_gap = { x = patch.left + 3.5, y = patch.top + 5.5 }
        local east_gap = { x = patch.left + 5.5, y = patch.top + 5.5 }

        patch.build(TILE, { x = patch.left + 2.5, y = patch.top + 5.5 }, NORTH, patch.stand)
        patch.build(TILE, { x = patch.left + 6.5, y = patch.top + 5.5 }, NORTH, patch.stand)
        assert(patch.count(PIPE) == 10,
            "the outer pair reach different tiles and should not have been joined")

        patch.build(TILE, mid, NORTH, patch.stand)

        assert(patch.pipe_at(west_gap) ~= nil, "the west arm was left unjoined")
        assert(patch.pipe_at(east_gap) ~= nil, "the east arm was left unjoined")
        assert(patch.count(PIPE) == 8,
            "expected two pipes spent, inventory holds " .. patch.count(PIPE))
    end)

    --- The elbow, which has one opening and it is never straight ahead. Two of them are
    --- turned to face each other along that opening, so the tile between them is the
    --- only one either can use -- and the tile each of them faces is one neither can.
    test("elbow is joined along its arm, not where it points", function()
        local patch = world.patch()
        local TILE = "aupc-tests-elbow"
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [TILE] = 10 }
        local elbow_a = { x = patch.left + 4.5, y = patch.top + 5.5 }
        local elbow_b = { x = patch.left + 6.5, y = patch.top + 5.5 }
        local arm_gap = { x = patch.left + 5.5, y = patch.top + 5.5 }
        -- straight ahead of A, which is where the old geometry would have aimed
        local ahead = { x = patch.left + 4.5, y = patch.top + 4.5 }

        patch.build(TILE, elbow_a, NORTH, patch.stand)
        patch.build(TILE, elbow_b, SOUTH, patch.stand)

        assert(patch.pipe_at(arm_gap) ~= nil,
            "the two elbows open onto the same tile but got no connector")
        assert(patch.pipe_at(ahead) == nil,
            "a pipe went where the elbow points, which it cannot join")
        assert(patch.count(PIPE) == 9,
            "expected one pipe spent, inventory holds " .. patch.count(PIPE))
    end)

    --- The u-turn, whose above-ground opening and buried run leave on the same side.
    --- Two of them facing each other open onto the same tile, so a connector belongs
    --- there -- and note they are joined underground as well, which is inherent to the
    --- shape rather than anything the mod did.
    test("u-turn is joined on the side both of them open onto", function()
        local patch = world.patch()
        local TILE = "aupc-tests-u-turn"
        patch.paint("refined-concrete")
        patch.stock{ [PIPE] = 10, [TILE] = 10 }
        local ahead = { x = patch.left + 6.5, y = patch.top + 3.5 }

        patch.build(TILE, patch.a, NORTH, patch.stand)
        assert(patch.pipe_at() == nil, "a pipe appeared before the second u-turn existed")
        patch.build(TILE, patch.b, SOUTH, patch.stand)

        assert(patch.pipe_at() ~= nil, "both u-turns open onto the gap but got no connector")
        assert(patch.pipe_at(ahead) == nil,
            "a pipe went where the u-turn points rather than where it opens")
        assert(patch.count(PIPE) == 9,
            "expected one pipe spent, inventory holds " .. patch.count(PIPE))
    end)
end)
