# Compatibility and rollback

Supported registry records include schema versions 1 and 2 through explicit
adapters/validation. Paused tickets, uncertain actions, ownership generations,
branches, external IDs, and prior receipts/evidence remain data, not fields to
reset for convenience. Unsupported versions and divergent legacy duplicates
fail closed for manual recovery. JSON corruption may recover from a valid
backup, but a semantic migration error is never hidden by an older snapshot.

Compatibility fixtures use copies only. They do not migrate or resume the
audited operational registry.
