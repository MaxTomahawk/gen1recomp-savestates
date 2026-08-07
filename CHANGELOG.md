# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`.

## Unreleased

### Added

- Current modkit API-2 technical shell and public-API-only architecture.
- Upstream audit, living project plan, and verified Level A integration design.
- Versioned data-only snapshots, migrations, strict identity validation, and
  transaction-ordered persistent histories.
- Rolling quicksave/quickload, durable recovery and undo, corrupt-newest fallback,
  and failure-safe ten-slot management with pin/rename/delete.
- Native START decoration and state manager screens that coexist with other menu
  decorators.
- Deferred event-based location and optional after-battle autosaves with cooldown,
  semantic replacement, and retention.
- Persistent ordinary wild/trainer battle safe-point states with deterministic
  gameplay RNG, semantic continuation reconstruction, and deferred battle-start
  autosaves.
- Replace-in-place HUD notifications and native mod option schema.
- Capability-gated, synchronous before-warp autosaves through the public
  pre-transition event.
- Opt-in capture, serialization/size, persistence, recovery, and restore timing
  diagnostics.
- State detail rows for trigger, age, runtime kind, and compatibility, plus a
  complete native settings summary.
- Default-NO native confirmation for history and permanent-slot deletion.
- Structured warning/error diagnostics for capability refusal, persistence,
  restoration, and unexpected autosave-controller failures.
- Semantic autosave fingerprints ignore play time and remembered START cursor
  while retaining gameplay progress, so true duplicates can replace after cooldown.
- Native notification text fitting/wrapping, live manager count refresh after
  pin/delete, and visible autosave capture failures.
- A tested release gate that validates against the exact minimum released engine
  tag declared by the manifest rather than a moving development branch.

## 0.1.0

Reserved for the first verified technical MVP; not yet released.
