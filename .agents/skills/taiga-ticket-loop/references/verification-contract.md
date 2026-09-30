# Worker-owned verification contract

The implementer owns a short verification plan derived from the assignment
packet and repository instructions. `workflow-verification.ps1 -Operation plan`
writes the plan to the durable state root and records check IDs, criterion
coverage, mandatory full-suite/TDD/browser requirements, UI interactions, and
shared-output serialization groups. The reviewer evaluates adequacy; the
coordinator only checks that the plan reference and hash exist.

An optional repository smoke entry point is configuration, not a generic
application harness. It may name an existing command, working directory,
disposable setup/cleanup, and required capabilities. Setup requires cleanup,
unsupported capabilities block the worker, and the generic helper never starts
services or performs browser/database/HTTPS work.

Checks that share compiler or other output directories are serialized. Safe
independent reads may be batched. A required check cannot be waived because a
shorter command is convenient.

## Evidence reuse

Each captured evidence record may carry input coverage: checked revision, base
SHA, covered files, environment hash, and dependency hash. Exact-revision
reuse is allowed only when all those inputs match. A documentation-only delta
may reuse a check when its covered source files do not overlap and base,
environment, and dependency inputs remain unchanged. Source/base/environment/
dependency drift invalidates reuse.

Reuse returns the original evidence ID, action, checked revision, and capture
timestamp and is labeled `freshlyExecuted: false`. The reviewer must approve
reuse; it is never relabeled as a new browser click or a newly run test.
