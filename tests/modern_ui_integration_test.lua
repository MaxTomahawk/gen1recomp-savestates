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
