return function(DataOnly)
  local Snapshot = {}
  Snapshot.FORMAT = 1
  Snapshot.MOD_ID = "savestates"

  function Snapshot.new(args)
    if type(args) ~= "table" then
      return nil, "corrupt_metadata", "Snapshot arguments must be a table."
    end
    if type(args.checkpoint) ~= "table" then
      return nil, "missing_checkpoint", "Snapshot requires an engine checkpoint."
    end
    local checkpoint, code, message = DataOnly.copy(args.checkpoint)
    if not checkpoint then return nil, code, message end
    local checkpointIdentity = checkpoint.identity or {}

    return {
      format = Snapshot.FORMAT,
      identity = {
        modId = Snapshot.MOD_ID,
        modVersion = args.modVersion,
        modApi = args.modApi,
        engineVersion = checkpointIdentity.engineVersion,
        gameVersion = checkpointIdentity.gameVersion,
        playthroughId = checkpointIdentity.playthroughId,
      },
      metadata = {
        id = args.id,
        stateClass = args.stateClass,
        trigger = args.trigger,
        createdAt = args.createdAt,
        label = args.label,
        locationId = args.locationId,
        locationName = args.locationName,
        stateKind = checkpoint.kind,
        fingerprint = args.fingerprint,
        slot = args.slot,
      },
      checkpoint = checkpoint,
    }
  end

  return Snapshot
end
