# Admin access model (RBAC) — grant-backed, no bypass

## The model

Nothing in the stack short-circuits RBAC for the administrator:

- **auth** — the resource gate (`PermissionCheckable#authorize_resource!` → `User#has_permission?`) and the `/permissions` endpoint the frontend consumes are row-based. There is no `super_admin` clause in either.
- **frontend** — `can()` in `PermissionsContext` is purely data-driven (`permissionsArray.includes('resource.action')`). This is intentional and must stay that way: the backend grant set is the single source of truth, and a role short-circuit in the UI would show controls the API then 403s.
- **`super_admin` has everything only because `db/seeds/rbac.rb` grants it the whole catalog.**

`super_admin` is the installation owner: the bootstrap user created by the setup wizard (`SetupBootstrapService`). Three things separate it from `account_owner`, none of them related to multi-tenancy:

1. `installation_configs.manage` — SMTP, Storage, Social Login, OpenAI, channels, frontend runtime. Installation infrastructure, not account data. It is the key that renders `/settings/admin`.
2. Only `super_admin` may grant permissions it does not itself hold (`Api::V1::RolesController#bulk_update_permissions`). Every other admin is capped at its own permission set.
3. Only `super_admin` sees and edits `type: 'user'` roles; `account_owner` is confined to `type: 'account'` roles.

So the shape is **one installation owner × N delegated operation admins** — a single-account installation still has two levels.

## The invariant

> `super_admin` grant set == full permission catalog (`ResourceActionsConfig.all_permission_keys`).

Because there is no bypass, every capability of the admin depends on this holding. When the catalog grows (a new resource/action) and an already-bootstrapped installation keeps the old grant set, the effect is a **silent** capability loss: the backend 403s the admin on the new feature and the frontend hides the control, with no configuration error anywhere.

`account_owner` has two documented exclusions from the catalog: `installation_configs.manage` and `accounts.stats` (`account_owner_exclusive` in the seed).

## How the invariant is protected

| Layer | Where | What it does |
|---|---|---|
| Fresh install | `db/seeds/rbac.rb` | Grants the whole catalog to `super_admin`. |
| CI tripwire | `.github/workflows/test.yml` running `spec/db/seeds/rbac_spec.rb` — "super_admin grant set == full permission catalog (seed policy)" | Fails the build when the seed stops granting `super_admin` the catalog whole (an exclusion list of its own), when `account_owner`'s exclusions change, and when any role other than `super_admin` holds `installation_configs.manage`. Drives the seed through a stubbed catalog so the assertion has an oracle independent of `all_permission_keys` — comparing the seeded set back against that same method is a tautology that stays green while the catalog grows. |
| Runtime repair | `RbacGrantReconciler` + `rails rbac:reconcile_super_admin` | Idempotent convergence: grants the missing catalog keys, drops grants the catalog no longer defines. Conflicts are skipped (`insert_all` + `ON CONFLICT DO NOTHING`) so two replicas booting at once cannot roll the whole batch back. Touches `super_admin` only. |
| Deploy | `docker-entrypoint.sh` | Runs the reconcile task on every boot, right after `db:migrate`. No-op before bootstrap; a failure is logged as a prominent ERROR block naming the repair command, but does not abort the boot (a stale grant is degraded, not unsafe). Gated by `RUN_MIGRATIONS` — setting it to `false` disables the self-heal along with the migrations. |
| Editing | `Api::V1::RolesController#bulk_update_permissions` | Rejects permission edits on `super_admin` with 403. Its grant set is an invariant, not a preference: accepting the edit would persist it, return 200, and let the next boot revert it silently. |

## Runbook

Every image boot already reconciles (`RUN_MIGRATIONS` gate, default on). Manual operations:

```bash
# Report drift without writing; exits non-zero when the grant set diverged
bundle exec rails rbac:check_super_admin_drift

# Converge (idempotent, safe to re-run)
bundle exec rails rbac:reconcile_super_admin
```

After adding a permission to `ResourceActionsConfig`:

1. **Fresh installs** need nothing: `super_admin` and `account_owner` both pick the new key up from `all_permission_keys` the next time `db/seeds/rbac.rb` runs. Edit the seed only if a *non-admin* role (e.g. `agent`) should receive it too.
2. **Existing installations** are covered by the boot reconciliation **for `super_admin` only**.
3. **`account_owner` on existing installations needs a paired data migration — always.** It is the delegated-admin role most operators actually use, it holds the whole catalog minus two keys by seed policy, and it is *not* auto-reconciled (it is editable in the role editor, so rewriting it on every boot would revert operator customisations). Skip this step and every delegated admin silently loses the new feature: the API 403s them and the UI hides the control. Follow `GrantIntegrationsExecuteToAdminRoles` for the pattern.

`rails rbac:check_super_admin_drift` reports `account_owner`'s missing catalog keys as an informational line (it never changes the exit status) so a forgotten step 3 is visible rather than silent.

## Product decision: `super_admin` stays the installation owner

**Decided 2026-07-22 by Guilherme Gomes (TL) — option (a) of EVO-2062. This is intentional, not leftover multi-tenancy.**

The community edition keeps `super_admin` as the top of the role hierarchy. It is *not* "the role that has everything" — it is the privilege-escalation boundary, and all three things that separate it from `account_owner` are unrelated to multi-account:

1. **`installation_configs.manage`** — SMTP, Storage, Social Login, OpenAI, channels, frontend runtime. Infrastructure of the installation, not data of the operation. It is the key that renders `/settings/admin`.
2. **Granting beyond your own set** — `Api::V1::RolesController#bulk_update_permissions` caps every other admin at the permissions they themselves hold. `super_admin` is the only role that can raise the installation's ceiling.
3. **Scope over `type: 'user'` roles** — `account_owner` sees and edits only `type: 'account'` roles (`enforce_role_scope!`).

So the shape is **one installation owner × N delegated operation admins**. A single-account installation still has two levels of admin, and "conta única" does not imply "um único nível de admin".

Option (b) — promoting `account_owner` to the top — was rejected: it drops all three boundaries at once, so every delegated admin could rewrite SMTP/Storage/OAuth and self-escalate, at the cost of a coordinated migration across auth + CRM + frontend (bootstrap, `installation_configs.manage`, data-migration of existing users, `ADMIN_ROLE_KEYS` / `administrator?` / `isAdminRole`) with a real risk of locking the live admin out mid-deploy — to rename a concept.

If the *name* ever reads as multi-tenant, the cheap move is to change the display label only ("Dono da instalação") and keep the `key`: no data touched, no gate touched.

The frontend stays data-driven — `can()` answers strictly from the granted permission list, with no role short-circuit (pinned by `PermissionsContext.spec.tsx` in the frontend repo). The invariant, the guard and the reconciliation above are what make that correct.
