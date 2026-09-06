--- Tile and item data copied out of the shipped base and space-age prototypes,
--- so the specs pin what the game actually says rather than what we remember.
---   base/prototypes/tile/tile-collision-masks.lua   collision masks
---   base/prototypes/item.lua                        concrete, refined concrete, landfill
---   space-age/prototypes/item.lua                   ice platform, foundation
---   space-age/base-data-updates.lua:934             the stone brick patch
---   core/lualib/collision-mask-defaults.lua         the building() entity mask a pipe uses
return {
    tiles = {
        -- tile_collision_masks.meltable_tile()
        ["ice-rough"]        = { layers = {ground_tile=true, meltable=true} },
        ["ice-smooth"]       = { layers = {ground_tile=true, meltable=true} },
        ["ice-platform"]     = { layers = {ground_tile=true, meltable=true}, item = "ice-platform" },
        -- tile_collision_masks.ammoniacal_ocean()
        ["ammoniacal-ocean"] = { layers = {water_tile=true, item=true, player=true, doodad=true, floor=true},
                                 default_cover = "ice-platform" },
        -- tile_collision_masks.water()
        ["water"]            = { layers = {water_tile=true, resource=true, item=true, player=true,
                                           doodad=true, floor=true},
                                 default_cover = "landfill" },
        -- tile_collision_masks.ground()
        -- no item places this one, and the engine refuses to make a tile ghost of it
        ["empty-space"]      = { layers = {ground_tile=true, water_tile=true, empty_space=true,
                                           resource=true, floor=true, item=true, object=true,
                                           player=true, doodad=true} },
        ["grass-1"]          = { layers = {ground_tile=true} },
        ["concrete"]         = { layers = {ground_tile=true}, item = "concrete" },
        ["refined-concrete"] = { layers = {ground_tile=true}, item = "refined-concrete" },
        ["stone-path"]       = { layers = {ground_tile=true}, item = "stone-brick" },
        ["landfill"]         = { layers = {ground_tile=true}, item = "landfill" },
        ["foundation"]       = { layers = {ground_tile=true}, item = "foundation" },
    },
    -- collision_mask_defaults.building(), which is what a pipe gets. Note the absence
    -- of ground_tile: that is why a pipe sits on grass but not on water or on ice.
    entities = {
        ["pipe"] = { layers = {item=true, meltable=true, object=true, player=true,
                               water_tile=true, is_object=true, is_lower_object=true} },
    },
    -- `condition` is an exclusion mask: the target tile must have none of these layers
    items = {
        ["concrete"]         = { result = "concrete",         condition = {water_tile=true} },
        ["refined-concrete"] = { result = "refined-concrete", condition = {water_tile=true} },
        -- space-age adds meltable here, which is what keeps stone path off Aquilo ice
        ["stone-brick"]      = { result = "stone-path",       condition = {water_tile=true, meltable=true} },
        ["landfill"]         = { result = "landfill",         condition = {ground_tile=true},
                                 tile_condition = {"water"} },
        ["ice-platform"]     = { result = "ice-platform",     condition = {ground_tile=true},
                                 tile_condition = {"ammoniacal-ocean"} },
        -- the real list is water, wetland, oil ocean and lava, pointedly not ammoniacal ocean
        ["foundation"]       = { result = "foundation",       condition = {},
                                 tile_condition = {"water"} },
    },
}
