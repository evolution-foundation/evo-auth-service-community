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
| **Resolve Version** | `resolve-version` | pushes: the version of this run and what to publish (see Releases) | a release branch is not named `release/X.Y`, or a new candidate is asked for a commit that is not the branch tip; on main, main is not identical to any tested RC, or the final tag exists on another commit |
| **Publish Image Tags** | `publish-image-tags` | `:develop` on develop, `:X.Y.Z-rc.N` on `release/X.Y` | the manifest cannot be created |
| **Publish Release Candidate** | `release-candidate` | `release/X.Y` only: tag `vX.Y.Z-rc.N` and a GitHub prerelease, after the image is published | the release cannot be created |
| **Promote Release** | `promote-release` | merge of `release/X.Y` into main: the last RC image gets `:X.Y.Z` and `:latest` without a rebuild, then tag `vX.Y.Z` and the final GitHub release | the RC image cannot be retagged or the release cannot be created |
| **Release Dry Run** | `release-dry-run` | pull requests into main: rehearses the promotion the merge would run (version, source RC, identical images) and writes it in the run summary, publishing nothing | the merge would not publish a final version: the branch is not `release/X.Y`, main would differ from the last RC, or the final tag exists |
| **Pipeline Status** | `pipeline-status` | **the only required check** | any check above is not green |

Jobs run on `ubuntu-24.04`: `ubuntu-latest` is 26.04, where `setup-ruby` has no Ruby 3.4.4.

## Releases

Versions follow semver, adapted to the release flow:

- **X** changes when an upgrade needs action from whoever installs (manual
  migration, incompatible API, a new required variable).
- **Y** changes on every regular cut from `develop`.
- **Z** changes only for an urgent fix on a released line.

The flow, with version 1.2.0 as the example:

1. **Every change** reaches `develop` by pull request; Pipeline Status must be green.
2. **Cut:** create `release/1.2` from a green `develop`. This is the only
   manual step that starts a version.
3. **Candidate:** every push on `release/1.2` runs every check and publishes the
   next candidate: `1.2.0-rc.1`, `rc.2`, ... as an image tag, a `v1.2.0-rc.N` tag
   and a GitHub prerelease. `:latest` does not move. A candidate is never a final
   version.
4. **Fixes** reach `release/1.2` by pull request (only fixes, nothing new), and
   the same fix goes to `develop`. Each merge is a new candidate.
5. **Release:** a pull request `release/1.2 -> main`, approved and merged by an
   admin, with any merge method. Before the merge, **Release Dry Run** shows on
   the pull request what the merge will publish and fails if it would not
   publish a final version. **main is the only trigger of a final version:**
   main must be identical to the last candidate of the version, and that
   candidate's image is promoted, without a rebuild, to `1.2.0` and `:latest`, with the `v1.2.0` tag
   and the final GitHub release. If main matches no candidate, matches an
   older candidate than the last one, or `v1.2.0` exists on another commit,
   nothing is published. A promotion that failed
   halfway is completed by re-running it.
6. **Urgent fix** after `1.2.0`: a pull request on `release/1.2` publishes
   `1.2.1-rc.1`, and its merge into main publishes `1.2.1`. What `develop` got
   since the cut does not go with it.

Nobody creates a version or publishes by hand: tags are created only by this
workflow, and a tag pushed by hand publishes nothing. Anything on main that is
not identical to a tested candidate (`develop`, a feature branch, a direct
push) fails Resolve Version and publishes nothing.

Only the tip of a release branch gets a new candidate; re-running an older push
reuses its candidate or fails. Release notes start at the highest final version
below the one published, so an urgent `1.2.1` is compared with `1.2.0` even
after `1.3.0`. The final image keeps the candidate's version label inside
(`1.2.0-rc.3`): changing it would make a different image. The final version is
in the image tags, the index annotation and the git tag.

Protection: `develop`, `release/**` and `main` require Pipeline Status and one
approval, and only admins can merge. `v*` tags cannot be moved or deleted.

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
