# AGENTS.md

## Local Dev Helper
- Use `./re-run.sh` to rebuild, restart daemon, and summon UI in one command.
- Keep runtime/build flags centralized in `re-run.sh` (or `.rerun.env` overrides) so flag changes only need one update.

## Commit Cadence Rule
- Small commits are required at healthy checkpoints.
- When the user gives feedback like "it looks good", "nice", or "it's working", treat that as a checkpoint signal and commit the current working state before proceeding.
