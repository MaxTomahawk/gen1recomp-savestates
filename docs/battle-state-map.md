# Battle State Map and Level B Contract

Status: Gate D complete; supported Level B subset implemented and verified

Evidence baseline: `bryanthaboi/gen1recomp` `dev` at `112120e`, plus the
Level A checkpoint branch through `05b43ca`

## Scope and conclusion

`src/battle/BattleState.lua` is a mutable state machine whose action queue can
contain functions, UI factories, live battler references, renderer objects, and
partially completed effects. A data-only checkpoint therefore cannot safely copy
the `BattleState` table. Level B will capture a semantic battle model only at a
settled player-decision boundary and will reconstruct the controller.

The supported first Level B subset is normal single-player wild and trainer
battles with an engine-owned, serializable continuation descriptor. Link,
Safari, ghost, old-man/demo, script-suspended, and mod-defined continuation
battles remain explicitly unavailable until each has a tested semantic resume
contract. This is narrower than "any battle frame" but stronger than an
in-memory-only snapshot: supported checkpoints must remain loadable after the
original battle object and process no longer exist.

There are no unclassified fields in the supported subset. Fields that cannot be
made data-only are either reconstructed by the engine or make the boundary
ineligible.

## Required safe boundary

Capture is allowed only when all of these invariants hold:

- the stack top is the active `BattleState`;
- `phase == "menu"`, the ordinary player command menu;
- `queue` is empty and `current`, `afterQueue`, `nextInsert`, `pendingHit`,
  `waitingUI`, `waitingSound`, `waitFrames`, and `draining` are absent;
- no animation, HP tween, faint slide, intro transition, typed message, choice,
  Mimic chooser, item/party screen, or forced replacement is active;
- both battlers exist, the player battler is conscious, and no locked automatic
  action (`thrash`, `rage`, recharge, trapping continuation) is about to bypass
  player selection;
- the battle kind and continuation origin are in the supported subset;
- the underlying overworld has no suspended `ScriptRunner`, parallel runner,
  queued script, movement, warp, or transition that would need a Lua coroutine
  stack to resume.

Restore is allowed from a settled overworld or another eligible battle boundary.
Validation, detached reconstruction, content checks, and rollback capture happen
before the live stack is replaced.

## Battle controller fields

The classifications below cover every mutable `self.*` field found in
`BattleState.lua`. Groups list fields with the same treatment.

| Classification | Fields | Treatment |
| --- | --- | --- |
| Engine anchors | `game`, `data`, `ruleset`, `rng`, `onFinish` | Never serialized. Resolve registries/ruleset again; install the standard RNG adapter; reconstruct `onFinish` from a validated continuation descriptor. |
| Identity and roster | `kind`, `oppClass`, `partyIndex`, `enemyParty`, `enemyIndex`, `player`, `enemy`, `trainer`, `enemyAIMods` | Store kind/class/party indices and dynamic Pokémon records. Resolve trainer and static definitions from current content. Rebuild battlers and references. |
| Turn/model state | `turnCount`, `menuIndex`, `moveIndex`, `moveSwapIndex`, `aiUses`, `runAttempts`, `payDay`, `sideToxic`, `participants`, `leveledUp`, `isGymLeader`, `musicKind`, `lastBall`, `lowHealthAlarmDisabled`, `lowHealthAlarmOn`, `victoryMusicPlayed`, `lockedBall`, `endBattleText` | Snapshot data values. Convert Pokémon-keyed sets (`participants`, `leveledUp`) to stable party indices and reconstruct their keys. `endBattleText` is already a finished string. Boundary validation rejects values that are meaningful only in an unsupported subphase. |
| Mod battle substrate | `sides`, `field` | Snapshot only recursively data-only `screens`, `hazards`, `weather`, and token payloads. Rebuild `sides[*].battlers` from reconstructed battlers. A token containing callbacks, userdata, metatables, or live objects makes capture unavailable rather than being dropped. |
| Variant model | `safari`, `safariCatchRate`, `baitFactor`, `escapeFactor`, `ghost`, `ghostReal`, `scopeReveal`, `noCatch`, `demo`, `demoFails`, `demoName`, `demoTimer`, `oakDemo`, plus link-injected `opponentName` and `playerParty` | Unsupported in the first Level B subset. Presence produces a specific capability refusal. |
| Settled presentation | `phase`, `shown`, `codes`, `total`, `charIndex`, `charTimer`, `lineIndex`, `lines`, `msgAutoWait`, `msgHold`, `msgPreWait`, `msgPrompt`, `msgPromptWait`, `msgWaiting`, `frame` | Do not preserve a partial presentation. Restore directly to a fresh `menu` presentation with battler `shownHP`/`shownStatus` synchronized to the reconstructed model. |
| Ephemeral queue/control | `queue`, `current`, `afterQueue`, `nextInsert`, `pendingHit`, `waitingUI`, `waitingSound`, `waitFrames`, `draining`, `mimicCtx`, `mimicMoves`, `mimicIndex`, `mimicRestores`, test-only `mimicChoice` | Must be absent at capture. These may contain functions or live references and are never serialized. Mimic's persistent move mutation is represented through battler move data; an active chooser is rejected. |
| Visual/runtime objects | `animPlayer`, `animPlaying`, `animName`, `animAttackerIsPlayer`, `moveAnimRow`, `bgCanvas`, `waveCanvas`, `waveQuad`, `grayPics`, `playerBackPic`, `trainerPic`, `fx`, `picFx`, `picOff`, `colorFxReady`, `growIn`, `introSlide`, `introBalls`, `introSfx`, `introText`, `enemyHidden`, `enemySendingOut`, `sendingOut`, `showEnemyBalls`, `showEnemyTrainer`, `showPlayerBack`, `scrollPx`, `scopeReveal`, `ghostReveal`, `blackedOut`, `blankForAskName`, `isOpaque` | Never serialized. Recreate render assets from registries and normalize all effects to the settled menu state. Non-settled values make capture unavailable. |
| Terminal/invalid | `result`, `dead` | A terminal battle is outside the safe boundary and is rejected. Battler `fainted` is captured only for inactive party members as part of their model; active `faintQueued` is boundary-forbidden below. |

## Battler fields

`makeBattler` combines a live Pokémon record with battle-only state. The
checkpoint stores a side plus a party index (or enemy roster index), never an
object pointer.

| Classification | Fields | Treatment |
| --- | --- | --- |
| Reconstruct from content/model | `mon`, `def`, `name`, `isPlayer`, `badges`, `badgeBoosts`, `sprite` | Store Pokémon data and stable indices; resolve species/moves/sprites and recompute definitions on restore. |
| Snapshot combat state | `statuses`, `stages`, `curStats`, `curTypes`, `curMoves`, `shownHP`, `shownStatus`, `sleepTurns`, `confusedTurns`, `disabledSlot`, `disabledTurns`, `toxicCounter`, `substituteHP`, `bideDamage`, `bideTurns`, `boundTurns`, `charging`, `chargeReady`, `invulnerable`, `mustRecharge`, `thrashMove`, `thrashTurns`, `thrashAnnounced`, `rageMove`, `focusEnergy`, `leechSeeded`, `lightScreen`, `reflect`, `mist`, `xAccuracy`, `lastMove`, `flinched`, `skipMove`, `hazeStatReset`, `drainFloor`, `drainHold`, `trappingTurns`, `trapMove`, `trapDamage` | Snapshot as validated scalars/data tables. Preserve move PP and Mimic-mutated battle move IDs separately from canonical party move identity when they differ. Normalize displayed values at the menu boundary. |
| Boundary-forbidden transient | `draining`, `faintQueued` | Must be absent. They mean an HP tween or faint queue is incomplete. |

The canonical save copy remains authoritative for player party HP, PP, status,
experience, inventory, money, Pokédex, and flags. Battle-only copies supplement
it; restore must reject contradictions instead of choosing one silently.

## Side, field, and extension data

Every battle creates two sides with `index`, `battlers`, `screens`, `hazards`,
and `tokens`, plus a field with `weather`, `tokens`, and `sides`. Vanilla leaves
these extension tables empty, but mods may populate them. Tokens may include
`onResidual` and `onExpire` functions (`BattleState:tickTokens`). Function-bearing
tokens cannot cross the data-only boundary. Level B therefore supports:

- empty vanilla extension tables; and
- mod extension values that pass the same recursive data-only validator as the
  public checkpoint.

Any callback-bearing or otherwise non-data extension returns
`battle_extension_unsafe`. The checkpoint never silently strips it.

## RNG inventory

Normal battle construction sets `BattleState.rng` to a wrapper around
`love.math.random`. Battle mechanics pass that wrapper into:

- `src/battle/Damage.lua`: critical-hit, accuracy, and damage rolls;
- `src/battle/Catching.lua`: capture shakes/results;
- `src/battle/TrainerAI.lua`: random AI decisions;
- `src/battle/TurnOrder.lua`: equal-priority/equal-speed ordering;
- status and move-effect branches inside `BattleState.lua`; and
- escape and Safari logic inside `BattleState.lua`.

Overworld encounter selection uses `love.math.random` through
`src/world/Encounter.lua` and `OverworldController:rollEncounter`. Lua's
`math.random` is also used for player/OT identifiers, but it is not the normal
battle-mechanics stream. Link battles intentionally install a separate
deterministic stream in `src/link/LinkBattle.lua` and are excluded here.

LÖVE exposes `love.math.getRandomState` and `setRandomState`; current upstream
does not use them. The engine checkpoint must capture the LÖVE random state at
the same logical instant as the battle model and restore it only after all
validation/reconstruction work that could consume randomness. Tests must prove
identical damage, critical, accuracy, AI, escape, and encounter outcomes after
reload. The distributable mod will not monkeypatch a global RNG.

## Continuation inventory

`BattleState:finish` invokes `self.onFinish`, which is a closure in every current
single-player caller. Closures are not serializable, and several capture live
objects:

| Origin | Current continuation | Persistent Level B decision |
| --- | --- | --- |
| ordinary grass/water/cave wild | `OverworldState:afterBattle` | Support after engine tags the origin semantically. |
| fishing wild | clears fishing state, then `afterBattle` | Defer initially; distinct origin semantics required. |
| static map Pokémon | defeated-object flag/removal, `afterBattle`, unfreeze | Defer initially; requires stable object id and post-battle reconstruction. |
| ordinary map trainer | defeated/header flags, rewards, `afterBattle`, optional `onDone` | Support only when no script runner is suspended and the engine owns a serializable trainer continuation descriptor. |
| `Commands.start_battle` | updates script context and resumes a suspended coroutine | Reject with `script_busy`; the program counter and Lua stack are not serializable. |
| ghost/Safari/old-man demo | variant-specific state and callbacks | Explicitly excluded from the first subset. |
| link battle | network peer and separate synchronized RNG | Reject with `link_battle_unsupported`. |
| mod-created battle/closure | arbitrary caller behavior | Reject unless a future public continuation registry supplies validated data-only capture/restore handlers. |

`src/script/ScriptRunner.lua` stores the program counter and locals inside a Lua
coroutine created by `ScriptRunner:run`; `Commands.start_battle` yields that
coroutine and resumes it from `onFinish`. Restoring only the battle would strand
or skip the script. This is a proven blocker, not an assumed limitation.

## Chosen public contract

Extend the existing generic `mod.checkpoints` facade rather than add a
savestate-specific API:

1. `inspect(game)` may report `kind = "battle"` only at the boundary above.
2. `capture(game)` returns the additive format-1 battle kind with the canonical save, an overworld
   return point, a semantic continuation descriptor, normalized battle model,
   and RNG state.
3. `restore(game, checkpoint)` validates identity and content, reconstructs a
   new battle and continuation on a detached path, atomically installs it, then
   restores RNG state.
4. Failure restores the pre-load runtime checkpoint, including its RNG state.
5. Existing format-1 overworld checkpoints remain accepted unchanged.

This is a generic engine capability: mods see opaque, data-only runtime
checkpoints and never import `BattleState`, `StateStack`, RNG, or overworld
controllers. Existing mods require no changes and behavior is unchanged when the
API is unused.

## Required verification before enabling Level B

- format-1 overworld checkpoint compatibility and no-mod parity;
- strict refusal for every excluded variant and unsafe phase;
- capture -> mutate -> restore -> recapture equality for ordinary wild and
  trainer battles;
- process-independent reconstruction (no reliance on the original battle,
  closure, or object identity);
- player/enemy HP, PP, status, stages, volatiles, participants, turn count,
  switches, fainted party members, enemy roster, AI uses, escape state, and
  extension data roundtrips;
- exact RNG replay for damage, critical, accuracy, AI choice, escape, and next
  encounter;
- restore-failure injection with successful runtime and RNG rollback;
- public mod API tests and full ROM-free upstream suite;
- mod integration tests proving recovery and compatibility behavior for battle
  checkpoints.

These checks pass on the stacked Level B branch through `5b3eed8`; battle restore
has 43/43 checks and the public facade has 53/53 checks. The public suite includes
a complete battle capture/restore/recapture roundtrip and explicit complete
overworld-progress fidelity. The mod advertises the supported `battle` kind while
retaining every exclusion above.
