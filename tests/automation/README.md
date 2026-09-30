# Offline automation fixtures

Run the self-contained PowerShell 7 harness from the repository root:

```powershell
pwsh -NoProfile -File tests/automation/Test-Automation.ps1
```

The harness uses synthetic state, a local bare Git remote, and no desktop,
Taiga, or production GitHub calls. It covers atomic state recovery, CAS and
ownership/capacity rules, uncertain actions, cursor consumption, pause/resume,
review receipt validation, dependency cycles, epic evidence, fresh-base branch
creation, and a verified local push. A nonzero exit code means a fixture failed.
