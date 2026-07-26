# ItemRack TBC Anniversary - Release v4.43-beta1

This beta release includes the complete AutoQueue refactoring, readiness-safe initialization lifecycle, and captured trinket cooldown provenance.

---

### 🚀 Changes in this Beta Release

- **Readiness-Safe AutoQueue Initialization**: Gated queue evaluation (`PeriodicQueueCheck`, `ProcessAutoQueue`, `AutoQueueItemToEquip`) behind `ItemRack.QueueStateReady` to prevent queue evaluation during loading screens or incomplete addon loading.
- **Item Resolution Safety (`TryInitializeQueueState`)**: Scans equipment slots via native `GetInventoryItemID`, deferring initialization gracefully if any occupied slot's item data is unresolved (`GetID == 0`) without publishing partial snapshots or falsely treating occupied slots as empty.
- **Persisted Schema & Stale Timer Sanitization**: Validates saved `EquipTimers` records on UI reload/login, checking table schemas, numeric timestamps, exact item IDs, and enforcing the 0-30s elapsed window.
- **Zone Transition Baseline Protection**: Snapshot initialization runs once on startup. `PLAYER_ENTERING_WORLD` zone/instance transitions preserve the baseline snapshot without resetting equip timers or generating false equip penalties.
- **Captured Cooldown Provenance for Dual Trinkets**: Replaced temporal guessing with exact post-activation state tracking (`ItemRack.LastActivation`) for primary and follower trinket slots, enforcing an 8-point follower rejection guard for macro activations (`/use 13 \n /use 14`) while allowing independent trinket and ring activations.
- **Event-Driven Burn-on-Use Architecture**: Converted Burn-on-Use to 100% event-driven activation (`ReflectItemUse`), removing legacy duration-based burn inference (> 30s) and establishing slot-aware equip hold thresholds (`ShouldHoldEquippedItem`).
- **Equip Penalty & Transition Mechanics**: Added empty-to-item transition handling (`previousID == 0`) for `RecordEquipTime` and ensured `OnUnitInventoryChanged` maintains button updates, `CombatQueue` cleanup, menu rebuilds, and options panel updates even when queue state is uninitialized.


