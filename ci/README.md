# CI

`.github/workflows/ci.yml` is the only workflow: triggers, order and services.
What each check does lives in its own composite action under
`.github/actions/<check>/action.yml`, so a change to one check touches one file.
Every check still runs on every change, and the image is published only after
all of them pass.

| Check | Action | What it does | Fails when |
|---|---|---|---|
| **Check Syntax** | `check-syntax` | RuboCop | an offense outside `.rubocop_todo.yml` |
| **Application Tests** | `application-tests` | RSpec through `ci/rspec`, with Postgres and Redis | a spec fails, or an example is skipped, outside `ci/test-exceptions.txt` |
| **Build Application** | `build-application` | builds this commit's image (same Dockerfile and `RAILS_ENV=production` as the publish jobs) and boots it with `RAILS_ENV=production` on a clean database | migrations fail, or `/health` and `/ready` do not answer ready |
| **Migration Version Check** | `migration-version-check` | auth and CRM share `schema_migrations`; auth owns odd versions | a new migration has an even version |
| **Community Boundary Check** | `community-boundary-check` | the community code has no enterprise identifiers | one of the identifiers listed in the action appears |
| **Publish Image** | `publish-image` | pull requests: `pr-<n>`, `sha-<short>` (amd64); pushes: one image per architecture | the build or the push fails |
| **Publish Image Tags** | `publish-image-tags` | `:develop` on develop, `:latest` on main and on `v*` tags (plus `:X.Y.Z`) | the manifest cannot be created |
| **Pipeline Status** | `pipeline-status` | **the only required check** | any check above is not green |

Jobs run on `ubuntu-24.04`: `ubuntu-latest` is 26.04, where `setup-ruby` has no Ruby 3.4.4.

## Known debt

- **Lint:** `.rubocop_todo.yml`, generated on 27/11/2026 from `develop` (5ba52fa):
  2,996 offenses in 145 files, every cop still enabled with a per-file list. A new
  offense of a cop already listed for that file passes; fixing debt and
  regenerating is how the list shrinks:
  `bundle exec rubocop --auto-gen-config --no-exclude-limit --no-auto-gen-timestamp`.
- **Tests:** `ci/test-exceptions.txt`, one line per spec file with class, owner and
  reason. The owner reviews it at every release cut; deleting a line puts the spec back.

## Running locally

```
bundle exec rubocop
RAILS_ENV=test bundle exec rails db:create db:schema:load && ci/rspec   # needs Postgres and Redis
docker build --build-arg RAILS_ENV=production -t evo-auth-smoke:ci . && \
  SMOKE_IMAGE=evo-auth-smoke:ci SMOKE_RAILS_ENV=production docker compose -f docker-compose.smoke-fresh.yml up
```
