--- Telling a blueprint stamp apart from a placement the player made by hand.
local blueprint = {}

--- Is this player stamping a blueprint right now?
---
--- Same-tick bookkeeping cannot answer this: the game creates all of a stamp's
--- entities and only then raises the build events, so the first underground already
--- sees the second standing there before anything has been recorded about it. The
--- blueprint stays in the cursor for the whole stamp, though, so every build it
--- causes can be recognised from there -- the undergrounds and the machines that
--- land beside them alike.
---
--- Known gap: a mod calling LuaItemStack.build_blueprint with by_player also fires
--- on_built_entity, and the cursor holds whatever that player happened to have, so
--- this says no and the connectors go in. Closing it would mean deferring every
--- connector to the end of the tick, which splits the cover tile out of the player's
--- undo item. The fixture "stamped through the API still gets a connector (known gap)"
--- in test/ft/blueprints.lua pins that behaviour deliberately. Passing raise_built instead of
--- by_player fires script_raised_built, which the mod never subscribed to, so that
--- path was never affected either way.
---@param player LuaPlayer
---@return boolean
local function is_stamping(player)
    local cursor = player.cursor_stack
    if not cursor or not cursor.valid_for_read then return false end
    return cursor.is_blueprint or cursor.is_blueprint_book
end

blueprint.is_stamping = is_stamping

return blueprint
