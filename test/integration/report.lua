--- Turn the scenario's serpent dump into a pass/fail summary and an exit code.
local path = ...
if not path then
    io.stderr:write("usage: lua5.2 report.lua <results file>\n")
    os.exit(2)
end

local handle = io.open(path, "r")
if not handle then
    io.stderr:write("no results file at " .. path ..
        "\nthe run produced nothing; see env/run.out\n")
    os.exit(1)
end
local contents = handle:read("*a")
handle:close()

-- the file is data, so it loads with no environment at all
local chunk, err = load(contents, "results", "t", {})
if not chunk then
    io.stderr:write("could not parse the results file: " .. tostring(err) .. "\n")
    os.exit(1)
end
local report = chunk()

local failed = 0
for _, fixture in ipairs(report.fixtures or {}) do
    if #fixture.failures == 0 then
        print("ok   " .. fixture.name)
    else
        failed = failed + 1
        print("FAIL " .. fixture.name)
        for _, failure in ipairs(fixture.failures) do
            print("       " .. failure)
        end
        for _, note in ipairs(fixture.notes or {}) do
            print("     . " .. note)
        end
    end
end

if report.error then
    failed = failed + 1
    print("FAIL the scenario itself errored")
    print("       " .. report.error)
end

print(string.format("\n%d fixtures, %d failed", #(report.fixtures or {}), failed))
os.exit(failed == 0 and 0 or 1)
