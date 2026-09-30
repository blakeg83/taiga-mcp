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
