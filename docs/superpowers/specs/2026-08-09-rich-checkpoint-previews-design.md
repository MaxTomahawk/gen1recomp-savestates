# Rich Checkpoint Previews Design

## Decision

Implement rich previews entirely in the Save States mod. The public checkpoint
record contains detached canonical `checkpoint.save`; no runtime object or new
engine API is required. The user steering dated 2026-08-09 is the approved
product decision for this design.

## Capture-time data

Each new snapshot gets optional `metadata.preview`:

```lua
{
  playTime = 16620, -- captured seconds
  badgeCount = 1,
  badgeTotal = 8,
  party = {
    { name = "PIKACHU", level = 22, hp = 45, maxHp = 57 },
  },
}
```

`party` is ordered and contains zero through six records. It deliberately has no
status, moves, DVs, or other restoration data. `name` prefers nonempty
`mon.nickname`; otherwise capture queries the effective public
`mod.content.pokemon:get(mon.species)` record and falls back to the species id.
Badge ids and the total come from the effective public
`mod.content.constants:get("badges")` list at capture time; earned badges are
truthy entries in the captured save inventory. `playTime`, HP, and max HP are
copied from the captured save, never read from live state during browsing.

The checkpoint payload remains authoritative. Preview is descriptive metadata:
the browser loads it from the index only, then performs one lazy payload read
when the player opens a state or slot detail. This preserves corruption handling
without decoding every payload simply to draw a list.

## Validation and compatibility

Preview remains optional in wrapper format 1. Missing preview is valid for old
records and renders a compact legacy detail. Present preview is strict data-only
metadata: finite nonnegative play time, coherent badge count/total, dense party
of at most six, nonempty name, positive level/max HP, and HP from zero through
max. Unknown/status fields are rejected. Snapshot and index validation both
enforce the same rule; malformed present preview makes that record unavailable.

Direct slot saving captures a new preview. Pinning and rename copy the source
preview exactly, including its absence for legacy source records, so manual slot
labels remain separate from capture provenance. No naming prompt is added to an
empty-slot save path.

## Native UI

The existing native `ListMenu` detail screens display location, play time,
badges, up to six compact party rows, created time, kind, compatibility, and
actions. This naturally pages when required. State/history and slot rows stay
cheap; opening one detail invokes a new public-mod-local `inspectState` service
operation that reads and validates only that selected payload.

## Non-blocking ecosystem work

Fresh check: official `dev` remains `943ba5d`; #993 is open/ready at `aa3b2a1`.
No open PR implements complete semantic Gen1Recomp playthrough transfer. Issue
#949 is raw `.sav` behavior and #977 is Android external-sync permissions; neither
is a complete mod-storage-aware transfer implementation. Portability remains a
separate generic engine follow-up and cannot raise Save States' release floor.

The local wiki branch `docs/mod-state-checkpoints` already carries storage and
battle checkpoint pages. It will receive the `checkpoint.restored` page updates
only after #993 has a verified upstream merge commit.
