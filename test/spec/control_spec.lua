--- Loads the real control.lua against stubs, which is the cheapest way to catch
--- a require that stopped resolving or a top level that stopped running.
local support = require("test.support.factorio")
support.install_defines()
support.install_storage()
support.install_prototypes(require("test.support.vanilla"))

-- core/lualib/util, which only exists inside Factorio
package.loaded["util"] = {
    direction_vectors = {
        [defines.direction.north] = { 0, -1 },
        [defines.direction.east]  = { 1, 0 },
        [defines.direction.south] = { 0, 1 },
        [defines.direction.west]  = { -1, 0 },
    },
}

local registered = { events = {}, on_init = 0, on_configuration_changed = 0, interfaces = {} }
_G.script = {
    on_init = function() registered.on_init = registered.on_init + 1 end,
    on_configuration_changed = function()
        registered.on_configuration_changed = registered.on_configuration_changed + 1
    end,
    on_event = function(event_id, handler, filters)
        registered.events[#registered.events + 1] =
            { id = event_id, handler = handler, filters = filters }
    end,
}
_G.remote = { add_interface = function(name, functions) registered.interfaces[name] = functions end }
_G.game = {}

describe("control.lua", function()
    setup(function() assert.has_no.errors(function() dofile("control.lua") end) end)

    it("registers the index rebuild on both lifecycle hooks", function()
        assert.equals(1, registered.on_init)
        assert.equals(1, registered.on_configuration_changed)
    end)

    it("listens for built entities, filtered to undergrounds and their ghosts", function()
        assert.equals(1, #registered.events)
        assert.equals(defines.events.on_built_entity, registered.events[1].id)
        assert.same({
            { filter = "type", type = "pipe-to-ground" },
            { filter = "ghost_type", type = "pipe-to-ground" },
        }, registered.events[1].filters)
    end)

    it("exposes the lookup table over the remote interface", function()
        local interface = registered.interfaces["automatic-underground-pipe-connectors"]
        assert.is_table(interface)
        for _, name in ipairs({ "get_undergrounds", "set_undergrounds",
                                "add_undergrounds", "remove_undergrounds" }) do
            assert.is_function(interface[name], name .. " is missing")
        end
    end)

    it("seeds the storage tables", function()
        assert.is_table(storage.pipe_lookup)
        assert.is_table(storage.tile_lookup)
    end)
end)
