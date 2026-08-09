-- Save States: public-API composition root. Local modules load through
-- mod:read + load; distributable code never imports private engine modules.

local function bootstrap(mod)
  local source, readErr = mod:read("src/ModuleLoader.lua")
  if type(source) ~= "string" then
    return nil, "module_missing", "Could not read ModuleLoader: " .. tostring(readErr)
  end
  local chunk, compileErr = load(source, "@" .. mod.path .. "/src/ModuleLoader.lua")
  if not chunk then
    return nil, "module_compile_failed",
      "Could not compile ModuleLoader: " .. tostring(compileErr)
  end
  local ok, ModuleLoader = pcall(chunk)
  if not ok or type(ModuleLoader) ~= "table" then
    return nil, "module_init_failed",
      "Could not initialize ModuleLoader: " .. tostring(ModuleLoader)
  end
  return ModuleLoader.new(mod)
end

return function(mod)
  local loader, code, message = bootstrap(mod)
  if not loader then
    mod.log:error("Save States core failed (%s): %s", tostring(code), tostring(message))
    return
  end

  local function module(path)
    local exported, moduleCode, moduleMessage = loader:load(path)
    if not exported then
      mod.log:error("Save States core failed (%s): %s",
        tostring(moduleCode), tostring(moduleMessage))
      return nil
    end
    return exported
  end

  local DataOnly = module("src/util/DataOnly.lua")
  local PreviewFactory = DataOnly and module("src/state/Preview.lua")
  local SnapshotFactory = PreviewFactory and module("src/state/Snapshot.lua")
  local ValidatorFactory = SnapshotFactory and module("src/state/SnapshotValidator.lua")
  local MigrationsFactory = ValidatorFactory and module("src/state/StateMigrations.lua")
  local IndexFactory = MigrationsFactory and module("src/state/StateIndex.lua")
  local Retention = IndexFactory and module("src/state/Retention.lua")
  local CanonicalFactory = Retention and module("src/util/Canonical.lua")
  local FingerprintFactory = CanonicalFactory and module("src/util/Fingerprint.lua")
  local Time = FingerprintFactory and module("src/util/Time.lua")
  local Deduplicator = Time and module("src/autosave/Deduplicator.lua")
  local AutoSaveController = Deduplicator and module("src/autosave/AutoSaveController.lua")
  local StoreFactory = AutoSaveController and module("src/state/StateStore.lua")
  local Options = StoreFactory and module("src/config/Options.lua")
  local StartMenu = Options and module("src/ui/StartMenuIntegration.lua")
  local ScreenFactory = StartMenu and module("src/ui/ScreenRegistry.lua")
  local Notification = ScreenFactory and module("src/ui/Notification.lua")
  local ServiceFactory = Notification and module("src/service/SaveStateService.lua")
  if not ServiceFactory then return end

  local ok, core = pcall(function()
    local Preview = PreviewFactory(DataOnly)
    local Snapshot = SnapshotFactory(DataOnly)
    local Validator = ValidatorFactory(DataOnly, Preview)
    local StateMigrations = MigrationsFactory(DataOnly)
    local StateIndex = IndexFactory(DataOnly, Preview)
    local Canonical = CanonicalFactory(DataOnly)
    local Fingerprint = FingerprintFactory(Canonical)
    local StateStore = StoreFactory({ DataOnly = DataOnly, StateIndex = StateIndex })
    local Screens = ScreenFactory({ Time = Time })
    local function capturePreview(_, checkpoint)
      local badgeIds = {}
      local constants = mod.content and mod.content.constants
      local badges = constants and constants:get("badges")
      if type(badges) == "table" then
        for _, badge in ipairs(badges) do
          if type(badge) == "table" and type(badge.id) == "string" and badge.id ~= "" then
            badgeIds[#badgeIds + 1] = badge.id
          end
        end
      end
      local pokemon = mod.content and mod.content.pokemon
      return Preview.capture(checkpoint and checkpoint.save, {
        badgeIds = badgeIds,
        speciesName = function(id)
          local definition = pokemon and pokemon:get(id)
          return type(definition) == "table" and definition.name or nil
        end,
      })
    end
    local function uiClock()
      if love and love.timer and love.timer.getTime then return love.timer.getTime() end
      return os.clock()
    end
    local notification = Notification.new({
      clock = uiClock,
      duration = 1.5,
      isEnabled = function(group)
        return mod.options:get(group == "load"
          and "load_notifications" or "save_notifications") ~= false
      end,
    })
    local migrations = StateMigrations.new(Snapshot.FORMAT)
    local Service = ServiceFactory({
      Snapshot = Snapshot,
      Retention = Retention,
      Fingerprint = Fingerprint,
      Deduplicator = Deduplicator,
    })
    local service = Service.new({
      checkpoints = mod.checkpoints,
      storeFactory = function(game)
        return StateStore.new({
          storage = mod.storage,
          game = game,
          validator = Validator,
          migrations = migrations,
          supportedKinds = { overworld = true, battle = true },
        })
      end,
      clock = os.time,
      quickLimit = function()
        return mod.options:get("quick_history") or 5
      end,
      autoLimit = function()
        return mod.options:get("auto_history") or 20
      end,
      previewFor = capturePreview,
      modVersion = mod.version,
      modApi = 2,
      notify = function(kind, detail) notification:show(kind, detail) end,
      debugEnabled = function()
        return mod.options:get("debug_logging") == true
      end,
      timer = uiClock,
      measureSize = function(value)
        local encoded = Canonical.encode(value)
        return encoded and #encoded or 0
      end,
      debug = function(metric)
        local size = metric.bytes and (", " .. tostring(metric.bytes) .. " bytes") or ""
        mod.log:info("[debug] %s %.3f ms%s",
          tostring(metric.operation), tonumber(metric.elapsedMs) or 0, size)
      end,
      warn = function(code, message, metadata)
        if mod.log.warn then
          mod.log:warn("Savestate %s (%s): %s",
            metadata and metadata.id or "operation", tostring(code), tostring(message))
        end
      end,
      error = function(code, message, metadata)
        mod.log:error("Savestate %s (%s): %s",
          metadata and metadata.id or "operation", tostring(code), tostring(message))
      end,
    })
    return {
      DataOnly = DataOnly,
      Preview = Preview,
      Snapshot = Snapshot,
      Validator = Validator,
      StateMigrations = StateMigrations,
      StateIndex = StateIndex,
      Retention = Retention,
      Canonical = Canonical,
      Fingerprint = Fingerprint,
      Time = Time,
      Deduplicator = Deduplicator,
      AutoSaveController = AutoSaveController,
      StateStore = StateStore,
      Options = Options,
      StartMenu = StartMenu,
      Screens = Screens,
      Notification = Notification,
      notification = notification,
      Service = Service,
      service = service,
    }
  end)
  if not ok then
    mod.log:error("Save States core failed (module_init_failed): %s", tostring(core))
    return
  end

  mod.options:define(core.Options.schema())
  core.screenIds = core.Screens.install(mod, core.service, os.time)
  core.StartMenu.install(mod, core.service, core.screenIds.root)
  core.autosaves = core.AutoSaveController.new({
    service = core.service,
    checkpoints = mod.checkpoints,
    option = function(key) return mod.options:get(key) end,
    report = function(code, message)
      mod.log:error("Autosave controller (%s): %s", tostring(code), tostring(message))
      core.notification:show("save_failed", { code = code, message = message })
    end,
  }):install(mod)
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    local result = next(game, viewport)
    core.notification:draw(viewport, mod.ui.Font)
    return result
  end)

  -- This deliberately small inter-mod surface is compatibility metadata, not a
  -- promise that every future internal module stays public.
  mod.exports.apiVersion = 1
  mod.exports.snapshotFormat = core.Snapshot.FORMAT
  mod.exports.supportedStateKinds = { "overworld", "battle" }
  mod.exports.quickSave = function(game) return core.service:quickSave(game) end
  mod.exports.quickLoad = function(game) return core.service:quickLoad(game) end
  mod.exports.autoSave = function(game, trigger, context)
    return core.service:autoSave(game, trigger, context)
  end
  mod.exports.undoLastLoad = function(game) return core.service:undoLastLoad(game) end
  mod.exports.loadState = function(game, id) return core.service:loadState(game, id) end
  mod.exports.listStates = function(game, class) return core.service:listStates(game, class) end
  mod.exports.listSlots = function(game) return core.service:listSlots(game) end
  mod.exports.saveSlot = function(game, slot, label)
    return core.service:saveSlot(game, slot, label)
  end
  mod.exports.loadSlot = function(game, slot) return core.service:loadSlot(game, slot) end
  mod.exports.deleteSlot = function(game, slot) return core.service:deleteSlot(game, slot) end
  mod.exports.screenIds = core.screenIds

  mod.log:info("Save States %s core ready", mod.version)
end
