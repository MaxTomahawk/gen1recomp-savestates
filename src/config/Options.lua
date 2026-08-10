local Options = {}

local ROWS = {
  { key = "quick_history", label = "QUICK SAVE HISTORY", type = "choice",
    default = 5, choices = {
      { "1", 1 }, { "3", 3 }, { "5", 5 }, { "10", 10 }, { "20", 20 },
    } },
  { key = "auto_history", label = "AUTO SAVE HISTORY", type = "choice",
    default = 20, choices = {
      { "5", 5 }, { "10", 10 }, { "20", 20 }, { "30", 30 }, { "50", 50 },
    } },
  { key = "history_time", label = "HISTORY TIME", type = "choice",
    default = "play_time", choices = {
      { "PLAY TIME", "play_time" }, { "DATE/TIME", "date_time" }, { "AGE", "age" },
    } },
  { key = "auto_location", label = "AUTO: LOCATION ENTRY", type = "toggle",
    default = true },
  { key = "auto_trainer_battle", label = "AUTO: TRAINER BATTLE", type = "toggle",
    default = true },
  { key = "auto_wild_battle", label = "AUTO: WILD BATTLE", type = "toggle",
    default = true },
  { key = "auto_after_battle", label = "AUTO: AFTER BATTLE", type = "toggle",
    default = false },
  { key = "auto_before_warp", label = "AUTO: BEFORE WARP", type = "toggle",
    default = false },
  { key = "save_notifications", label = "SAVE NOTIFICATIONS", type = "toggle",
    default = true },
  { key = "load_notifications", label = "LOAD NOTIFICATIONS", type = "toggle",
    default = true },
  { key = "continue_latest", label = "CONTINUE LATEST", type = "toggle",
    default = true },
  { key = "debug_logging", label = "DEBUG TIMINGS", type = "toggle",
    default = false },
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, item in pairs(value) do out[key] = copy(item) end
  return out
end

function Options.schema()
  return copy(ROWS)
end

return Options
