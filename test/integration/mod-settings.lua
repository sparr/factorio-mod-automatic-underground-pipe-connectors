#!/usr/bin/env lua5.2
--- Write a mod-settings.dat holding one runtime-per-user boolean.
---
--- Factorio refuses to let one mod change another mod's setting at runtime -- it
--- answers "Settings can only be changed by the owning player or the mod that made
--- the setting" -- so a fixture cannot flip this from inside the game. The harness
--- has to put the value in place before the game starts.
---
--- The file is a version header then a PropertyTree:
---   header      four u16 versions, then one unused false byte
---   value       a type byte, an "any type" flag byte, then the payload
---   type bytes  1 bool, 5 dictionary
---   string      a not-empty flag byte, a length byte, then the characters
---   dictionary  u32 count, then a key string and a value for each entry
--- Lengths of 255 or more use a longer form; every name here is far shorter.

local out_path, setting_name, value_text, version_text = ...
if not out_path or not setting_name or not value_text then
    io.stderr:write("usage: mod-settings.lua <path> <setting> <true|false> [version]\n")
    os.exit(2)
end
local value = value_text == "true" or value_text == "1"

local function u16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32(n)
    return string.char(n % 256, math.floor(n / 256) % 256,
                       math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function pstring(text)
    assert(#text < 255, "this writer only handles short names")
    return "\0" .. string.char(#text) .. text
end

local function pbool(flag)
    return "\1\0" .. (flag and "\1" or "\0")
end

--- entries is an ordered list of { key, already-encoded value }
local function pdict(entries)
    local parts = { "\5\0", u32(#entries) }
    for _, entry in ipairs(entries) do
        parts[#parts + 1] = pstring(entry[1])
        parts[#parts + 1] = entry[2]
    end
    return table.concat(parts)
end

local version = { 2, 1, 17, 0 }
if version_text then
    local index = 1
    for part in version_text:gmatch("%d+") do
        version[index] = tonumber(part)
        index = index + 1
    end
    version[4] = 0
end

local header = u16(version[1]) .. u16(version[2]) .. u16(version[3]) .. u16(version[4]) .. "\0"
local tree = pdict{
    { "startup", pdict{} },
    { "runtime-global", pdict{} },
    { "runtime-per-user", pdict{
        { setting_name, pdict{ { "value", pbool(value) } } },
    } },
}

local file = assert(io.open(out_path, "wb"))
file:write(header .. tree)
file:close()
