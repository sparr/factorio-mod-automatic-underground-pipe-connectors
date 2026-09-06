data:extend{
    {
        -- Off keeps the behaviour every version before this one had: no pipe of the
        -- underground's own quality means a ghost, and nothing is spent.
        type = "bool-setting",
        name = "aupc-substitute-pipe-quality",
        setting_type = "runtime-per-user",
        default_value = false,
        order = "a",
    },
}
