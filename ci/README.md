# CI

`.github/workflows/pipeline.yml` is the only workflow with triggers. Every other
workflow is called from it.

```
lint ──────────────┐
test ──────────────┤
build ─────────────┼──> publish ──> gate
migration-parity ──┤
no-enterprise ─────┘
```

| Stage | Workflow | Fails when |
|---|---|---|
| `lint` | `lint.yml` | RuboCop finds an offense outside `.rubocop_todo.yml` |
| `test` | `test.yml` → `ci/rspec` | a spec fails, or an example is skipped, outside `ci/test-exceptions.txt` |
| `build` | `smoke-fresh.yml` | the image built from this commit (same Dockerfile and `RAILS_ENV=production` as `publish`) does not migrate a clean database and answer `/health` and `/ready` |
| guards | `migration-version-parity.yml`, `no-enterprise-guard.yml` | see each file |
| `publish` | `docker-publish.yml` | runs only after all of the above; tags are `pr-<n>`/`sha-<short>`, `:develop`, `:latest` (main and `v*` tags) |
| `gate` | `pipeline.yml` | any stage above is not green. **This is the only required check.** |

Jobs run on `ubuntu-24.04`: `ubuntu-latest` is 26.04, where `setup-ruby` has no Ruby 3.4.4.

## Known debt

- **Lint:** `.rubocop_todo.yml`, generated on 27/11/2026 from `develop` (5ba52fa):
  2,996 offenses in 145 files, every cop still enabled with a per-file list. A new
  offense of a cop already listed for that file passes; fixing debt and
  regenerating is how the list shrinks:
  `bundle exec rubocop --auto-gen-config --no-exclude-limit --no-auto-gen-timestamp`.
- **Tests:** `ci/test-exceptions.txt`, one line per spec file with class, owner and
  reason. Owner reviews it at every release cut; deleting a line puts the spec back.

## Running locally

```
bundle exec rubocop
RAILS_ENV=test bundle exec rails db:create db:schema:load && ci/rspec
SMOKE_IMAGE=evo-auth-smoke:ci docker compose -f docker-compose.smoke-fresh.yml up
```
