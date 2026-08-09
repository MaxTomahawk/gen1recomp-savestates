return function(DataOnly, Preview)
  local Validator = {}

  local CLASSES = { quick = true, auto = true, slot = true, recovery = true }

  local function failure(code, message)
    return nil, code, message
  end

  local function nonempty(value)
    return type(value) == "string" and value ~= ""
  end

  local function optionalString(value)
    return value == nil or type(value) == "string"
  end

  function Validator.validate(snapshot, context)
    if type(snapshot) ~= "table" then
      return failure("corrupt_metadata", "Snapshot root must be a table.")
    end
    local copy, dataCode, dataMessage = DataOnly.copy(snapshot)
    if not copy then return nil, dataCode, dataMessage end
    if copy.format ~= 1 then
      return failure("bad_format", "Snapshot format is not supported.")
    end

    context = type(context) == "table" and context or {}
    local identity = copy.identity
    if type(identity) ~= "table" or identity.modId ~= "savestates"
        or not nonempty(identity.modVersion) or identity.modApi ~= 2
        or not nonempty(identity.engineVersion)
        or not nonempty(identity.gameVersion)
        or not nonempty(identity.playthroughId) then
      return failure("corrupt_identity", "Snapshot identity is missing or corrupt.")
    end
    if identity.gameVersion ~= context.gameVersion then
      return failure("wrong_game", "Snapshot belongs to another game version.")
    end
    if identity.playthroughId ~= context.playthroughId then
      return failure("wrong_playthrough", "Snapshot belongs to another playthrough.")
    end

    local metadata = copy.metadata
    local slotOk = type(metadata) == "table" and (
      (metadata.stateClass == "slot" and type(metadata.slot) == "number"
        and metadata.slot >= 1 and metadata.slot <= 10 and metadata.slot % 1 == 0)
      or (metadata.stateClass ~= "slot" and metadata.slot == nil))
    if type(metadata) ~= "table" or not nonempty(metadata.id)
        or not metadata.id:match("^[%w_-]+$")
        or not CLASSES[metadata.stateClass] or not nonempty(metadata.trigger)
        or type(metadata.createdAt) ~= "number" or metadata.createdAt < 0
        or not nonempty(metadata.stateKind)
        or not optionalString(metadata.label)
        or not optionalString(metadata.locationId)
        or not optionalString(metadata.locationName)
        or not optionalString(metadata.fingerprint)
        or not optionalString(metadata.contextKey) or not slotOk then
      return failure("corrupt_metadata", "Snapshot metadata is missing or corrupt.")
    end
    if metadata.preview ~= nil then
      if not Preview then
        return failure("corrupt_preview", "Snapshot preview validation is unavailable.")
      end
      local preview, previewCode, previewMessage = Preview.validate(metadata.preview)
      if not preview then return nil, previewCode, previewMessage end
      metadata.preview = preview
    end

    local checkpoint = copy.checkpoint
    if type(checkpoint) ~= "table" then
      return failure("missing_checkpoint", "Snapshot checkpoint is missing.")
    end
    if checkpoint.kind ~= metadata.stateKind then
      return failure("corrupt_metadata", "Snapshot runtime kind is inconsistent.")
    end
    if type(context.supportedKinds) ~= "table"
        or not context.supportedKinds[metadata.stateKind] then
      return failure("unsupported_runtime_kind",
        "Snapshot runtime kind is not supported here.")
    end
    local checkpointIdentity = checkpoint.identity
    if type(checkpointIdentity) ~= "table"
        or checkpointIdentity.engineVersion ~= identity.engineVersion
        or checkpointIdentity.gameVersion ~= identity.gameVersion
        or checkpointIdentity.playthroughId ~= identity.playthroughId then
      return failure("corrupt_identity", "Snapshot and checkpoint identities disagree.")
    end

    local warnings = {}
    if nonempty(context.engineVersion)
        and context.engineVersion ~= identity.engineVersion then
      warnings[#warnings + 1] = "engine_version_mismatch"
    end
    return copy, nil, nil, warnings
  end

  return Validator
end
