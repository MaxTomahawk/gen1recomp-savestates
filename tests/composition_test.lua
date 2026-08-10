local Test = dofile("tests/testlib.lua")
local T = Test.new("core composition")

local logs = {}
local registeredScreens = {}
local startMenuWrapper
local titleMenuWrapper
local renderHudWrapper
local inputStepWrapper
local eventHandlers = {}
local selectedStorageCalls = 0
local modernRegistration
local modernActive = false
local mod = {
  id = "savestates",
  version = "0.1.0",
  path = "mods/savestates",
  exports = {},
  find = function(id)
    if id ~= "gen1_modern_ui" then return nil end
    return {
      exports = {
        registerAdapter = function(spec)
          modernRegistration = spec
          return true
        end,
        isTransientPresentationActive = function(owner)
          return modernActive and owner == "savestates"
        end,
      },
    }
  end,
  storage = {
    selected = function(_, game)
      selectedStorageCalls = selectedStorageCalls + 1
      T:eq(game.save.meta.playthroughId, nil,
        "title storage resolution receives the unbound fresh title skeleton")
      return {
        context = function()
          return { engineVersion = "0.9.0-dev", gameVersion = "red",
            playthroughId = "selected-playthrough" }
        end,
        read = function(_, key) return nil, "not_found", "missing " .. key end,
        write = function() return true end,
        list = function() return {} end,
        delete = function() return true end,
      }
    end,
  },
  checkpoints = {},
  options = {
    get = function() return nil end,
    define = function(self, schema) self.schema = schema return schema end,
  },
  hooks = {
    wrap = function(_, name, callback)
      if name == "ui.start_menu.items" then startMenuWrapper = callback end
      if name == "ui.title_menu.items" then titleMenuWrapper = callback end
      if name == "render.hud" then renderHudWrapper = callback end
      if name == "input.step" then inputStepWrapper = callback end
      return function() end
    end,
  },
  events = {
    on = function(_, name, callback) eventHandlers[name] = callback end,
  },
  ui = {
    insertBefore = function(items, anchor, item)
      local at = #items + 1
      for index, candidate in ipairs(items) do
        if candidate.label == anchor then at = index break end
      end
      table.insert(items, at, item)
      return items
    end,
    push = function() end,
    ListMenu = { new = function(_, title, items, opts)
      return { title = title, items = items, opts = opts }
    end },
    NamingScreen = { new = function(_, opts) return { opts = opts } end },
  },
  content = {
    screens = {
      register = function(_, id, factory) registeredScreens[id] = factory end,
    },
    constants = {
      get = function(_, id)
        if id == "badges" then return { { id = "BOULDERBADGE" } } end
      end,
    },
    pokemon = {
      get = function(_, id) return { name = id } end,
    },
  },
  log = {
    info = function(_, format, ...)
      logs[#logs + 1] = (format):format(...)
    end,
    error = function(_, format, ...)
      logs[#logs + 1] = "ERROR " .. (format):format(...)
    end,
  },
}
function mod:read(path)
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local source = file:read("*a")
  file:close()
  return source
end

local entry = dofile("main.lua")
T:eq(type(entry), "function", "main returns a Gen1Recomp entry function")
local ok, err = pcall(entry, mod)
T:check(ok, "entry composes without throwing: " .. tostring(err))
T:eq(mod.exports.snapshotFormat, 1, "composition publishes snapshot format compatibility")
T:eq(mod.exports.apiVersion, 1, "composition publishes its inter-mod API version")
T:eq(mod.exports.gen1ModernUi.apiVersion, 1,
  "composition publishes the optional Modern UI presentation contract")
T:eq(type(mod.exports.gen1ModernUi.transient.model), "function",
  "Modern UI receives only the source-owned notification model")
T:eq(modernRegistration.owner, "savestates",
  "composition registers the optional Modern UI adapter through public exports")
T:eq(modernRegistration.contract, mod.exports.gen1ModernUi,
  "composition registers the same public data-only adapter it exports")
T:eq((mod.exports.supportedStateKinds or {})[1], "overworld",
  "composition advertises overworld checkpoints")
T:eq((mod.exports.supportedStateKinds or {})[2], "battle",
  "composition advertises proven battle safe-point checkpoints")
T:eq(type(mod.exports.quickSave), "function", "composition publishes quicksave command")
T:eq(type(mod.exports.quickLoad), "function", "composition publishes quickload command")
T:eq(type(mod.exports.undoLastLoad), "function", "composition publishes undo command")
T:eq(#(mod.options.schema or {}), 12, "composition registers the full options schema")
T:eq(type(startMenuWrapper), "function", "composition installs START decoration")
T:eq(type(titleMenuWrapper), "function", "composition installs title decoration")
T:eq(type(renderHudWrapper), "function", "composition installs non-modal HUD overlay")
T:eq(type(inputStepWrapper), "function", "composition installs deferred autosave boundary")
T:eq(type(eventHandlers["map.entered"]), "function",
  "composition subscribes to location autosaves")
T:eq(type(eventHandlers["battle.ended"]), "function",
  "composition subscribes to enabled-safe after-battle autosaves")
T:eq(type(eventHandlers["battle.started"]), "function",
  "composition subscribes to deferred battle-start autosaves")
T:eq(type(eventHandlers["player.warped"]), "function",
  "composition subscribes to immediate before-warp autosaves")
local screenCount = 0
for _ in pairs(registeredScreens) do screenCount = screenCount + 1 end
T:eq(screenCount, 11,
  "composition registers the action and dedicated detail state manager screens")
local menu = startMenuWrapper(function(_, items) return items end, {}, {
  { label = "SAVE" }, { label = "OPTION" },
})
T:eq(menu[2].label, "QUICKSAVE", "composed START menu exposes quicksave")
T:eq(menu[3].label, "STATES", "composed START menu exposes manager")
local titleMenu = titleMenuWrapper(function(_, items) return items end, {}, {
  { label = "CONTINUE" }, { label = "NEW GAME" }, { label = "OPTION" },
})
T:eq(titleMenu[2].label, "SAVE STATES",
  "composed title menu exposes selected-playthrough manager")
local titleRoot = registeredScreens[mod.exports.screenIds.root].new({
  save = { version = "red", meta = {} },
}, { context = "title" })
T:eq(selectedStorageCalls, 2,
  "title policy and manager resolve only the engine-selected storage facade")
T:eq(titleRoot.items[1].label, "QUICK SAVES",
  "empty selected title history remains natively browsable")
T:check(type(logs[#logs]) == "string" and logs[#logs]:find("core ready", 1, true),
  "successful composition logs one ready lifecycle message")
for _, message in ipairs(logs) do
  T:check(not message:match("^ERROR"), "successful composition emits no error log")
end

T:finish()
