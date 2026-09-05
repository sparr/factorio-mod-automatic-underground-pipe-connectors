local support = require("test.support.factorio")
support.install_defines()
support.install_storage()
local tile_prototypes = support.install_prototypes(require("test.support.vanilla"))
local tiles = require("lib.tiles")

local force = { name = "player" }

describe("tile_item_name", function()
    before_each(support.install_storage)

    it("finds the item that places a tile", function()
        assert.equals("stone-brick", tiles.tile_item_name("stone-path"))
    end)

    it("returns false, not nil, when no item places the tile", function()
        assert.is_false(tiles.tile_item_name("ammoniacal-ocean"))
    end)

    it("caches the answer, including the false one", function()
        assert.is_false(tiles.tile_item_name("ammoniacal-ocean"))
        assert.equals("concrete", tiles.tile_item_name("concrete"))
        assert.same({ ["ammoniacal-ocean"] = false, ["concrete"] = "concrete" }, storage.tile_lookup)
    end)

    it("reads the cache rather than the prototype on a second call", function()
        tiles.tile_item_name("concrete")
        storage.tile_lookup["concrete"] = "something-else"
        assert.equals("something-else", tiles.tile_item_name("concrete"))
    end)
end)

describe("tile_can_cover", function()
    before_each(support.install_storage)

    -- `condition` is an exclusion mask, so a target carrying one of its layers is refused
    describe("over ice, which is ground_tile plus meltable", function()
        local ice = tile_prototypes["ice-rough"]

        it("allows concrete and refined concrete", function()
            assert.is_true(tiles.tile_can_cover(tile_prototypes["concrete"], ice))
            assert.is_true(tiles.tile_can_cover(tile_prototypes["refined-concrete"], ice))
        end)

        it("refuses stone path, which space-age excludes from meltable ground", function()
            assert.is_false(tiles.tile_can_cover(tile_prototypes["stone-path"], ice))
        end)

        it("refuses landfill, which excludes ground_tile", function()
            assert.is_false(tiles.tile_can_cover(tile_prototypes["landfill"], ice))
        end)

        it("refuses foundation, whose tile_condition does not name ice", function()
            assert.is_false(tiles.tile_can_cover(tile_prototypes["foundation"], ice))
        end)

        it("refuses ice platform, which also excludes ground_tile", function()
            assert.is_false(tiles.tile_can_cover(tile_prototypes["ice-platform"], ice))
        end)
    end)

    describe("over ammoniacal ocean, which is water_tile", function()
        local ocean = tile_prototypes["ammoniacal-ocean"]

        it("allows ice platform, which names the ocean in its tile_condition", function()
            assert.is_true(tiles.tile_can_cover(tile_prototypes["ice-platform"], ocean))
        end)

        it("refuses concrete, which excludes water_tile", function()
            assert.is_false(tiles.tile_can_cover(tile_prototypes["concrete"], ocean))
        end)

        it("refuses landfill and foundation, which do not name the ocean", function()
            assert.is_false(tiles.tile_can_cover(tile_prototypes["landfill"], ocean))
            assert.is_false(tiles.tile_can_cover(tile_prototypes["foundation"], ocean))
        end)
    end)

    it("refuses a tile no item can place", function()
        assert.is_false(tiles.tile_can_cover(tile_prototypes["grass-1"], tile_prototypes["ice-rough"]))
    end)
end)

describe("cover_tile_for", function()
    before_each(support.install_storage)

    it("uses the tile prototype's own default when the force has no override", function()
        local surface = support.surface{}
        assert.equals(tile_prototypes["ice-platform"],
            tiles.cover_tile_for(surface, force, tile_prototypes["ammoniacal-ocean"]))
    end)

    it("prefers a per-force override", function()
        local surface = support.surface{ cover_tiles = { ["ammoniacal-ocean"] = tile_prototypes["foundation"] } }
        assert.equals(tile_prototypes["foundation"],
            tiles.cover_tile_for(surface, force, tile_prototypes["ammoniacal-ocean"]))
    end)

    it("is nil for a tile that needs no cover", function()
        assert.is_nil(tiles.cover_tile_for(support.surface{}, force, tile_prototypes["grass-1"]))
    end)
end)

describe("find_melt_cover_tile", function()
    local ice = tile_prototypes["ice-rough"]
    local on_refined = support.tile(tile_prototypes["refined-concrete"])
    local on_ice = support.tile(ice)
    before_each(support.install_storage)

    it("takes the per-force override first", function()
        local surface = support.surface{ cover_tiles = { ["ice-rough"] = tile_prototypes["refined-concrete"] } }
        assert.equals(tile_prototypes["refined-concrete"],
            tiles.find_melt_cover_tile(surface, force, ice, on_ice, nil))
    end)

    it("ignores an override that could not legally go there", function()
        -- ice platform is itself meltable, so covering ice with it solves nothing
        local surface = support.surface{ cover_tiles = { ["ice-rough"] = tile_prototypes["ice-platform"] } }
        assert.equals(tile_prototypes["concrete"],
            tiles.find_melt_cover_tile(surface, force, ice, on_ice, nil))
    end)

    it("otherwise matches the foundation the underground is standing on", function()
        assert.equals(tile_prototypes["refined-concrete"],
            tiles.find_melt_cover_tile(support.surface{}, force, ice, on_refined, nil))
    end)

    it("prefers what the player is carrying when the underground is on bare ice", function()
        local inventory = support.inventory{ ["refined-concrete"] = 5 }
        assert.equals(tile_prototypes["refined-concrete"],
            tiles.find_melt_cover_tile(support.surface{}, force, ice, on_ice, inventory))
    end)

    it("falls back to the lowest legal name so every player agrees", function()
        assert.equals(tile_prototypes["concrete"],
            tiles.find_melt_cover_tile(support.surface{}, force, ice, on_ice, support.inventory{}))
    end)

    it("never picks something the player could not place there", function()
        -- stone brick is the only thing carried, and space-age bars it from ice
        local inventory = support.inventory{ ["stone-brick"] = 50 }
        local chosen = tiles.find_melt_cover_tile(support.surface{}, force, ice, on_ice, inventory)
        assert.not_equals(tile_prototypes["stone-path"], chosen)
        assert.equals(tile_prototypes["concrete"], chosen)
    end)
end)

describe("tile state", function()
    it("captures the hidden tiles as well as the visible one", function()
        local state = tiles.save_tile_state(
            support.tile(tile_prototypes["concrete"], { x = 3, y = 4 }, "ice-rough"))
        assert.same({ position = { x = 3, y = 4 }, name = "concrete",
                      hidden_tile = "ice-rough", double_hidden_tile = nil }, state)
    end)

    it("puts every layer back, quietly", function()
        local surface = support.surface{}
        local state = { position = { x = 3, y = 4 }, name = "ice-rough",
                        hidden_tile = nil, double_hidden_tile = nil }
        tiles.restore_tile_state(surface, state, false)

        local call = surface.calls.set_tiles[1]
        assert.same({ { name = "ice-rough", position = { x = 3, y = 4 } } }, call.tiles)
        -- correct_tiles, remove_colliding_entities, remove_colliding_decoratives, raise_event
        assert.same({ false, false, false, false }, call.args)
        assert.equals(1, #surface.calls.set_hidden_tile)
        assert.equals(1, #surface.calls.set_double_hidden_tile)
    end)
end)
