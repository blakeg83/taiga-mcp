# Ticket-loop improvement acceptance

Offline acceptance is green on the sanitized fixtures and the full PowerShell
harness. It covers receipt compatibility, immutable evidence, trusted
publication acceptance, compact dispatch and quiet waits, worker-owned
verification, usage/cost separation, migration boundaries, and helper-integrated
replay of the audited failure classes.

Final offline validation was run from the TaigaMCP repository on 2026-09-30:

```text
pwsh -NoProfile -File tests/automation/Test-Automation.ps1
  Passed 34 automation fixtures; 0 failed
python C:\Users\Blake\.codex\skills\.system\skill-creator\scripts\quick_validate.py .agents/skills/taiga-ticket-loop
  valid
git diff --check
  passed
dotnet restore
  passed
dotnet build -c Debug --no-restore
  passed; 0 warnings, 0 errors
dotnet test -c Debug --no-build --no-restore
  525 passed, 0 failed, 0 skipped
dotnet build -c Release --no-restore
  passed; 0 warnings, 0 errors
dotnet test -c Release --no-build --no-restore
  525 passed, 0 failed, 0 skipped
```

These results are local/offline provenance from the commands above. They do
not verify a named-machine installation, native chat or heartbeat behavior,
live Taiga/GitHub/PR publication, or attributable manual-versus-automated
cost.

The following remain unverified because this implementation did not receive
operational authorization:

- installation on a personal/named machine;
- native ordinary-chat and heartbeat behavior;
- a live Taiga/GitHub/PR publication exercise;
- an equivalent manual-versus-automated comparison with attributable cost.

No raw-token threshold, savings percentage, or quality-equivalence claim is
made. A future trial must use the deliberate plan, exact worker profiles, the
same acceptance requirements, and explicit stop conditions.
