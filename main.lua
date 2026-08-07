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
  local SnapshotFactory = DataOnly and module("src/state/Snapshot.lua")
  local ValidatorFactory = SnapshotFactory and module("src/state/SnapshotValidator.lua")
  local MigrationsFactory = ValidatorFactory and module("src/state/StateMigrations.lua")
  local IndexFactory = MigrationsFactory and module("src/state/StateIndex.lua")
  local Retention = IndexFactory and module("src/state/Retention.lua")
  local CanonicalFactory = Retention and module("src/util/Canonical.lua")
  local FingerprintFactory = CanonicalFactory and module("src/util/Fingerprint.lua")
  local Deduplicator = FingerprintFactory and module("src/autosave/Deduplicator.lua")
  local StoreFactory = Deduplicator and module("src/state/StateStore.lua")
  local Options = StoreFactory and module("src/config/Options.lua")
  local ServiceFactory = Options and module("src/service/SaveStateService.lua")
  if not ServiceFactory then return end

  local ok, core = pcall(function()
    local Snapshot = SnapshotFactory(DataOnly)
    local Validator = ValidatorFactory(DataOnly)
    local StateMigrations = MigrationsFactory(DataOnly)
    local StateIndex = IndexFactory(DataOnly)
    local Canonical = CanonicalFactory(DataOnly)
    local Fingerprint = FingerprintFactory(Canonical)
    local StateStore = StoreFactory({ DataOnly = DataOnly, StateIndex = StateIndex })
    local migrations = StateMigrations.new(Snapshot.FORMAT)
    local Service = ServiceFactory({
      Snapshot = Snapshot,
      Retention = Retention,
      Fingerprint = Fingerprint,
    })
    local service = Service.new({
      checkpoints = mod.checkpoints,
      storeFactory = function(game)
        return StateStore.new({
          storage = mod.storage,
          game = game,
          validator = Validator,
          migrations = migrations,
          supportedKinds = { overworld = true },
        })
      end,
      clock = os.time,
      quickLimit = function()
        return mod.options:get("quick_history") or 5
      end,
      modVersion = mod.version,
      modApi = 2,
      warn = function(code, message, metadata)
        if mod.log.warn then
          mod.log:warn("Savestate %s (%s): %s",
            metadata and metadata.id or "operation", tostring(code), tostring(message))
        end
      end,
    })
    return {
      DataOnly = DataOnly,
      Snapshot = Snapshot,
      Validator = Validator,
      StateMigrations = StateMigrations,
      StateIndex = StateIndex,
      Retention = Retention,
      Canonical = Canonical,
      Fingerprint = Fingerprint,
      Deduplicator = Deduplicator,
      StateStore = StateStore,
      Options = Options,
      Service = Service,
      service = service,
    }
  end)
  if not ok then
    mod.log:error("Save States core failed (module_init_failed): %s", tostring(core))
    return
  end

  mod.options:define(core.Options.schema())

  -- This deliberately small inter-mod surface is compatibility metadata, not a
  -- promise that every future internal module stays public.
  mod.exports.apiVersion = 1
  mod.exports.snapshotFormat = core.Snapshot.FORMAT
  mod.exports.supportedStateKinds = { "overworld" }
  mod.exports.quickSave = function(game) return core.service:quickSave(game) end
  mod.exports.quickLoad = function(game) return core.service:quickLoad(game) end
  mod.exports.undoLastLoad = function(game) return core.service:undoLastLoad(game) end

  mod.log:info("Save States %s core ready", mod.version)
end
