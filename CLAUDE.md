# Blockscout Development Guidelines

## Pre-commit Requirements

You MUST run the following linting steps before committing any changes:

1. **Code formatting**: `mix format --check-formatted`
2. **Credo**: `mix credo`
3. **Dialyzer**: `mix dialyzer --halt-exit-status`
   - If your change is chain-type specific, also run with the appropriate `CHAIN_TYPE` env var (e.g. `CHAIN_TYPE=signet`)
4. **Sobelow** (if you changed files in `apps/explorer` or `apps/block_scout_web`):
   - `cd apps/explorer && mix sobelow --config`
   - `cd apps/block_scout_web && mix sobelow --config`
