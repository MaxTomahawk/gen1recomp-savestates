-- Optional Gen1 Modern UI bridge. It supplies a data-only notification model
-- and leaves save-state behavior, notification lifetime, and native fallback
-- fully owned by this mod.

local ModernUiIntegration = {}
ModernUiIntegration.__index = ModernUiIntegration

function ModernUiIntegration.new(mod, notification)
  assert(type(mod) == "table" and type(mod.id) == "string",
    "ModernUiIntegration.new needs a source mod")
  assert(type(notification) == "table"
      and type(notification.modernModel) == "function",
    "ModernUiIntegration.new needs a notification model")
  local self = setmetatable({ mod = mod, notification = notification },
    ModernUiIntegration)
  self.publicContract = {
    apiVersion = 1,
    screens = {},
    transient = {
      model = function()
        return self.notification:modernModel()
      end,
    },
  }
  return self
end

function ModernUiIntegration:contract()
  return self.publicContract
end

function ModernUiIntegration:handle()
  if type(self.mod.find) ~= "function" then return nil end
  local ok, handle = pcall(self.mod.find, "gen1_modern_ui")
  if not ok or type(handle) ~= "table" or type(handle.exports) ~= "table" then
    return nil
  end
  return handle
end

function ModernUiIntegration:register()
  local handle = self:handle()
  local register = handle and handle.exports and handle.exports.registerAdapter
  if type(register) ~= "function" then return false end
  local ok, accepted = pcall(register, {
    owner = self.mod.id,
    contract = self.publicContract,
  })
  return ok and accepted == true
end

function ModernUiIntegration:claimsPresentation()
  local handle = self:handle()
  local active = handle and handle.exports
    and handle.exports.isTransientPresentationActive
  if type(active) ~= "function" then return false end
  local ok, claimed = pcall(active, self.mod.id)
  return ok and claimed == true
end

return ModernUiIntegration
