--- A keybinding whose only job is to prove that synthetic input reaches the game.
--- Without it, a silent ctrl+z is indistinguishable from an undo that did nothing.
data:extend{
    {
        type = "custom-input",
        name = "aupc-tests-probe",
        key_sequence = "CONTROL + SHIFT + F9",
    },
}
