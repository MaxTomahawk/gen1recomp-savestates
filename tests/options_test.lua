local Test = dofile("tests/testlib.lua")
local T = Test.new("options schema")
local Options = dofile("src/config/Options.lua")

local schema = Options.schema()
T:eq(type(schema), "table", "schema is a public options row list")

local rows = {}
for _, row in ipairs(schema) do rows[row.key] = row end

local function choices(key, expected)
  local row = rows[key]
  T:check(row ~= nil, key .. " option exists")
  T:eq(row.type, "choice", key .. " is a choice")
  local values = {}
  for _, choice in ipairs(row.choices or {}) do values[#values + 1] = choice[2] end
  T:eq(#values, #expected, key .. " exposes the supported choice count")
  for index, value in ipairs(expected) do
    T:eq(values[index], value, key .. " choice " .. index .. " is exact")
  end
end

choices("quick_history", { 1, 3, 5, 10, 15, 20, 30, 50, 75, 100 })
T:eq(rows.quick_history.default, 50, "quick history defaults to fifty")
choices("auto_history", { 5, 10, 20, 30, 50, 75, 100 })
T:eq(rows.auto_history.default, 50, "auto history defaults to fifty")
choices("history_time", { "play_time", "date_time", "age" })
T:eq(rows.history_time.default, "play_time",
  "history time defaults to captured play time")

local toggles = {
  auto_location = true,
  auto_trainer_battle = true,
  auto_wild_battle = true,
  auto_after_battle = false,
  auto_before_warp = false,
  save_notifications = true,
  load_notifications = true,
  continue_latest = true,
  debug_logging = false,
}
for key, expected in pairs(toggles) do
  T:check(rows[key] ~= nil, key .. " option exists")
  T:eq(rows[key].type, "toggle", key .. " is a toggle")
  T:eq(rows[key].default, expected, key .. " has the product default")
end

local first = Options.schema()
first[1].label = "MUTATED"
T:check(Options.schema()[1].label ~= "MUTATED", "schema callers receive detached rows")

T:finish()
