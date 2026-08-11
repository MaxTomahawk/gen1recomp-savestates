local Test = dofile("tests/testlib.lua")
local T = Test.new("Modern UI notification integration")
local Integration = dofile("src/ui/ModernUiIntegration.lua")

local active = {
  id = "savestates:notification",
  title = "QUICK SAVED",
  detail = "CERULEAN CITY",
  severity = "success",
}
local notice = { modernModel = function() return active end }
local registered
local modernEnabled = true
local modelValid = true
local mod = {
  id = "savestates",
  find = function(id)
    if id ~= "gen1_modern_ui" then return nil end
    return {
      exports = {
        registerAdapter = function(spec)
          registered = spec
          return true
        end,
        isTransientPresentationActive = function(owner, game)
          return modernEnabled and modelValid and owner == "savestates"
            and game == "game-context"
        end,
      },
    }
  end,
}

local adapter = Integration.new(mod, notice)
local contract = adapter:contract()
T:eq(contract.apiVersion, 1, "source contract uses the released Modern UI API")
T:eq(type(contract.screens), "table", "transient source declares no custom screen renderer")
T:eq(type(contract.screens.history), "table",
  "history publishes a presentation-only screen adapter")
T:eq(type(contract.screens.details), "table",
  "details publish a presentation-only screen adapter")
local history = {
  screenId = "SavestatesHistory",
  modernModel = function() return { title = "QUICK SAVES", rows = {
    { label = "11-08-2026", header = true, enabled = false },
    { label = "OAKS LAB", value = "00:03" },
  }, index = 2 } end,
  moveSelection = function(self, delta) self.moved = delta end,
  selectCurrent = function(self) self.selected = true end,
  back = function(self) self.backed = true end,
}
T:eq(contract.screens.history.match(history), true,
  "history match uses only the stable public screen id and model")
T:eq(contract.screens.history.model(nil, history).rows[1].header, true,
  "history adapter forwards the source-owned data-only model")
contract.screens.history.actions.down(nil, history)
T:eq(history.moved, 1, "Modern UI semantic Down remains source-owned")
contract.screens.history.actions.select(nil, history)
T:eq(history.selected, true, "Modern UI semantic select remains source-owned")
contract.screens.history.actions.back(nil, history)
T:eq(history.backed, true, "Modern UI semantic back remains source-owned")

local details = {
  screenId = "SavestatesDetails",
  modernModel = function() return { title = "STATE DETAILS", rows = {
    { label = "PIKACHU", value = "LV22 HP 45/57", species = "PIKACHU" },
  }, index = 1 } end,
  moveSelection = function(self, delta) self.moved = delta end,
  back = function(self) self.backed = true end,
}
T:eq(contract.screens.details.match(details), true,
  "details match uses the stable public screen id and model")
T:eq(contract.screens.details.model(nil, details).rows[1].species, "PIKACHU",
  "details adapter carries detached species identity for icon presentation")
T:eq(contract.screens.details.canSuppressNative, true,
  "Modern UI suppresses native details only after accepting the model")
contract.screens.details.actions.select(nil, details)
T:eq(details.backed, true,
  "Modern UI detail taps preserve the source-owned A/B close behavior")
T:eq(type(contract.transient.model), "function", "source exports only a model callback")
T:eq(contract.transient.model().title, "QUICK SAVED",
  "source model preserves notification content")
T:eq(adapter:register(), true, "present Modern UI registers the source contract")
T:eq(registered.owner, "savestates", "registration is scoped to this source mod")
T:eq(registered.contract, contract, "registration passes the exact public contract")
T:eq(adapter:claimsPresentation("game-context"), true,
  "enabled Modern UI claims the transient and prevents a duplicate native banner")

modernEnabled = false
T:eq(adapter:claimsPresentation("game-context"), false,
  "disabled Modern UI releases the native notification fallback")
modernEnabled, modelValid = true, false
T:eq(adapter:claimsPresentation("game-context"), false,
  "malformed or throwing Modern UI presentation releases native fallback")
mod.find = function() return nil end
T:eq(adapter:claimsPresentation("game-context"), false,
  "absent Modern UI leaves the native notification fallback intact")

T:finish()
