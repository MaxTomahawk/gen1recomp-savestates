# Cross-Mod Checkpoint Compatibility Design

Status: approved by the focused release-gate request

Evidence pins:

- Gen1Recomp `dev`: `943ba5dcbfa62cf831e881684857ffd4867fe774`
- merged battle checkpoint PR: `983bea61aa78e19b769db219894eadd1538007ad`
- mod index `main`: `6f7eb4a`
- `masterwebx/gen1recomp-shiny-pokemon`: `2141b2ed35f4261d7306d8bb4d66a8c50e87125f`
- `YoDrehDenSwagAuf/overworld-spawn-mod`: `866bbdf5afa771bfeacbb3bb639cddd9b5c171cd`

## Goal

Define and prove one generic compatibility contract for checkpoint restores across
mods. Save States must rewind the game world, preserve independent durable data
and configuration, and give cooperating mods one safe point to rebuild derived
runtime state. It must never inspect or special-case another mod's private state.

## Real-world shiny case

Shiny Pokemon 1.0.8 does not use `mod.save` or `mod.storage` for shiny identity.
It makes a captured or party Pokémon shiny by mutating the plain Pokémon record:
the Gen 2-compatible `dvs` are authoritative and `mon.shiny` is a redundant fast
marker. Those records live in canonical progress for party, boxes, and daycare.
Checkpoint capture copies the complete save except `options`; validation preserves
unknown data-only Pokémon fields; battle capture also copies the enemy Pokémon and
the canonical player party. Both overworld and supported battle restore therefore
rewind shiny identity with the Pokémon it belongs to.

The mod's option cache mirrors global `mod.options` and must not rewind. Image
caches, bake queues, sparkle timers, temporary wild-roll sentinels, battler sprite
markers, and decorated overworld entities are runtime presentation state and must
not be serialized. Battle draw/overlay paths re-derive shiny presentation from the
restored Pokémon. Optional Wilds of Kanto spawn records are explicitly runtime-only;
their `shiny` and `shinyDVs` decorations must be regenerated with their entities,
not treated as durable Pokémon progress.

## State-class contract

| State class | Captured now | Rewind semantics | Owner action after restore |
| --- | --- | --- | --- |
| Core `game.save` progress | Yes, except `options` | Rewind | None unless the mod caches references or derived values |
| `save.modData` / `mod.save` | Yes, as part of progress | Rewind | Re-read through `mod.save`; rebuild caches |
| Another mod's `mod.storage` | No | Do not rewind by default | Treat as history, config, cache, or externally versioned data; reconcile explicitly if coupled to progress |
| Global/per-mod options | No; current options are reattached | Do not rewind | Invalidate only on `mod.options_changed`, not checkpoint restore |
| Runtime-only Lua/LÖVE state | No | Do not rewind or serialize | Drop/rebind/rebuild from restored public state |
| Data-only Pokémon/gameplay metadata inside canonical save records | Yes | Rewind with its owning record | Derive presentation/runtime behavior from the restored record |
| Derived/cache state | No | Rebuild | Recompute lazily or on the checkpoint lifecycle event |

`mod.storage` is intentionally not a second progress namespace. A mod that puts
quest truth or other rewind-coupled gameplay state only in `mod.storage` owns a
versioning/reconciliation problem; Save States must not roll back every independent
history merely because one checkpoint loads.

## Proven lifecycle gap

Checkpoint reconstruction replaces `game.save`, rebinds the engine's `mod.save`
backing, and reconstructs controller objects while deliberately suppressing normal
`save.loaded`, `map.entered`, and battle-intro events. A cooperating mod can
therefore have restored `mod.save` value A while retaining an in-memory cached value
B and references to discarded runtime objects. No current public event reliably
identifies a successful checkpoint restore.

The smallest additive seam is one success-only public event:

```lua
mod.events:on("checkpoint.restored", function(ev)
  -- ev.game is the live game after verified reconstruction.
  -- ev.kind is "overworld" or "battle".
  rebuildFromPersistentState(ev.game)
end)
```

The engine emits `{ game = game, kind = checkpoint.kind }` only after restore and
differential recapture verification succeed. It emits nothing for validation
failure, failed reconstruction, or successful rollback. The payload excludes the
checkpoint record, other mods' data, physical storage identity, and runtime
internals. Listener failures remain isolated by the existing event bus.

A pre-restore event, participant registry, arbitrary runtime snapshot protocol,
and automatic `mod.storage` rewind are deliberately excluded. They add ordering,
privacy, transaction, and serialization problems without being needed to rebuild
derived state after a committed restore.

## Verification design

Extend the real public modkit checkpoint suite with cooperating probe mods and
engine-side fixtures:

1. shiny-like Pokémon metadata: capture A, mutate progress and `dvs`/`shiny` to B,
   restore A, and verify combined overworld recapture plus restored derived shiny
   classification;
2. repeat player and enemy Pokémon metadata through a supported battle checkpoint;
3. `mod.save` gameplay state plus an in-memory cache: first prove the cache stays B
   without a lifecycle callback, then subscribe and prove successful restore
   rebuilds it to A through public API only;
4. an independent `mod.storage` history/config record: mutate it to B after capture,
   restore A, and prove it remains B;
5. global options: mutate to B and prove they remain B;
6. failed restore: prove no lifecycle event fires and live/cached B state remains;
7. successful overworld and battle restore: prove exactly one event with the final
   runtime kind, after `mod.save` has been rebound and after the reconstructed stack
   is available.

Run the focused public suite, complete ROM-free upstream suite, Save States test
and package gate, and a clean-clone package check. No ROM-derived fixture or asset
is introduced.

## User and mod-author contract

Save States rewinds canonical game progress, including other mods' `mod.save` and
data-only metadata embedded in saved Pokémon/game records. It preserves options
and independent `mod.storage`. It does not serialize mod runtime objects. Mods
whose runtime derives from rewound state should either make caches self-validating
or rebuild/rebind them on `checkpoint.restored`. Mods that use `mod.storage` for
progress-coupled truth must store an explicit checkpoint/version relationship and
reconcile it themselves; independent logs, histories, caches, and configuration
should continue forward across loads.
