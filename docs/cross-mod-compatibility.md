# Cross-Mod Checkpoint Compatibility

Save States rewinds the game world, not every byte owned by every installed mod.
The generic boundary is ownership and meaning: progress-coupled data rewinds;
independent durable data, configuration, and arbitrary Lua runtime state do not.

This contract was audited against:

- `masterwebx/gen1recomp-shiny-pokemon` at
  `2141b2ed35f4261d7306d8bb4d66a8c50e87125f` (index entry
  `masterwebx@SHINY_POKEMON`);
- `masterwebx/overworld-spawn-mod` at
  `866bbdf5afa771bfeacbb3bb639cddd9b5c171cd` as the optional runtime-only
  overworld encounter integration;
- public-API-only fake cooperating and passive mods in the upstream
  `checkpoint_cross_mod` integration suite.

No Save States code recognizes either mod id or accesses another mod's private
tables.

## Ownership matrix

| State class | Checkpoint behavior | Semantic rule | If it does not rewind | Reconciliation contract |
| --- | --- | --- | --- | --- |
| Core progress in `game.save` | captured and restored | rewinds | world and player progress would disagree | engine reconstructs and verifies the checkpoint |
| Every mod's `mod.save` / `save.modData` | captured and restored as part of `game.save` | rewinds when it describes this playthrough's progress | mod progress could remain ahead of or behind the restored world | engine rebinds each loaded mod's public `mod.save`; a cooperating mod invalidates derived runtime state after restore |
| Independent data in another mod's `mod.storage` | not captured or restored | does not rewind | expected for histories, indexes, caches, and tool-owned records | owning mod keeps its durable data and may reconcile references itself |
| Global or per-mod options | not rewound; current options are preserved | does not rewind | the player's present configuration remains active | existing `mod.options_changed` behavior remains authoritative |
| Runtime-only/in-memory mod state | not serialized | does not rewind directly | a progress-derived cache can temporarily describe condition B after progress returns to A | derive on demand or subscribe to `checkpoint.restored` and rebuild from public restored state |
| Mod-added data-only Pokémon/gameplay metadata embedded in canonical progress | captured and restored with its containing record | rewinds | identity/progress metadata would detach from the Pokémon or object it describes | use data-only fields on canonical save records and keep coupled fields consistent |
| Derived/cached runtime state | not serialized | rebuilds | stale visuals, lookup results, or transient flags may persist until refresh | make the cache self-validating or clear/rebuild it on `checkpoint.restored` |

`mod.storage` is intentionally not a second progress save. A mod that chooses to
put progress-coupled authoritative data there owns a two-store transaction and
reconciliation problem; Save States must not rewind the entire namespace because
it may also contain independent history or configuration.

## Shiny Pokémon roundtrip

The shiny mod represents shiny identity with two fields on the same Pokémon
record: `isShinyMon` accepts a true `mon.shiny` marker first, or derives shiny
status from the Gen 2 predicate over `mon.dvs`. `applyShinyToMon` writes both the
selected DVs and marker, then recalculates the Pokémon's stats/HP.

Party, boxes, daycare records, battle parties, and battle enemy Pokémon are plain
data-only Pokémon records inside the canonical checkpoint save/battle payload.
Gen1Recomp validation preserves mod-added data-only fields rather than projecting
records onto a closed schema. The real behavior is therefore generic:

1. capture condition A with Pokémon DVs/marker and matching game progress;
2. mutate both the Pokémon/progress and shiny metadata to condition B;
3. restore A;
4. observe the original Pokémon DVs, marker, calculated values, and game progress
   together again.

The upstream cross-mod suite proves this for a settled overworld checkpoint and
for supported wild-battle player-decision checkpoints, including both player and
enemy Pokémon. It uses the same data shape and shiny predicate without loading or
special-casing the shiny mod.

The shiny mod's option cache, image cache/bake jobs, sparkle timers, pending wild
roll, and battler/entity presentation flags are runtime state. They are not
checkpoint payloads. Battle rendering already rechecks the restored battler's
Pokémon data, so its visual state can be derived again. Wilds of Kanto overworld
encounter records are documented runtime entities; their shiny flags should be
regenerated with the entities rather than made into canonical save progress.

The current shiny implementation does not use `mod.save` or `mod.storage` for
shiny identity, so it needs no mod-specific migration or adapter.

## Restore lifecycle for cooperating mods

Upstream draft PR
[`bryanthaboi/gen1recomp#993`](https://github.com/bryanthaboi/gen1recomp/pull/993)
adds the minimal generic event proven necessary by the audit:

```lua
mod.events:on("checkpoint.restored", function(event)
  -- event.game is already restored; event.kind is "overworld" or "battle".
  cachedProgress = rebuildFrom(mod.save, event.game)
end)
```

The event is emitted only after reconstruction and differential recapture have
succeeded. Validation failures, reconstruction failures, and successful rollback
emit nothing. The payload deliberately contains no checkpoint data and exposes no
other mod's state.

Mods that only read canonical state on demand need no subscriber. Mods with
progress-derived runtime caches should treat the event as an invalidation/rebuild
boundary. Independent storage and options remain unchanged when the event fires.

## Tested generic scenarios

The upstream public SDK suite verifies:

- canonical progress and two mods' `mod.save` tables rewind from B to A;
- a subscriber rebuilds its cached progress from restored `mod.save`;
- a passive mod's arbitrary in-memory field is not silently serialized;
- independent `mod.storage` history and current global/mod options stay at B;
- shiny-style Pokémon metadata roundtrips in overworld and supported battle
  checkpoints;
- invalid and rolled-back restores do not publish a false success event;
- the event observes the final installed overworld or battle controller.

This is the compatibility model for all mods: cooperate through public canonical
state and a success-only lifecycle event, never through Save States adapters for
individual mod implementations.
