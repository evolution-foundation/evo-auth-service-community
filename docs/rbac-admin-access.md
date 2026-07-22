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

`account_owner` has exactly one documented exclusion from the catalog: `installation_configs.manage`.

## How the invariant is protected

| Layer | Where | What it does |
|---|---|---|
| Fresh install | `db/seeds/rbac.rb` | Grants the whole catalog to `super_admin`. |
| CI tripwire | `spec/db/seeds/rbac_spec.rb` — "super_admin grant set == full permission catalog" | Fails the build when the seeded set diverges from the catalog in either direction (missing catalog key, or grant absent from the catalog), and when any role other than `super_admin` holds `installation_configs.manage`. |
| Runtime repair | `RbacGrantReconciler` + `rails rbac:reconcile_super_admin` | Idempotent convergence: grants the missing catalog keys, drops grants the catalog no longer defines. Touches `super_admin` only — roles customised through the role editor are never rewritten. |
| Deploy | `docker-entrypoint.sh` | Runs the reconcile task on every boot, right after `db:migrate`. No-op before bootstrap; a failure warns but does not abort the boot (a stale grant is degraded, not unsafe). |

## Runbook

Every image boot already reconciles (`RUN_MIGRATIONS` gate, default on). Manual operations:

```bash
# Report drift without writing; exits non-zero when the grant set diverged
bundle exec rails rbac:check_super_admin_drift

# Converge (idempotent, safe to re-run)
bundle exec rails rbac:reconcile_super_admin
```

After adding a permission to `ResourceActionsConfig`:

1. Decide whether non-admin roles need it and edit `db/seeds/rbac.rb` accordingly — `super_admin` and `account_owner` pick it up automatically from `all_permission_keys`.
2. Existing installations get it from the boot reconciliation. A dedicated data-migration is only needed when a role **other than** `super_admin` must receive the new key (see `GrantIntegrationsExecuteToAdminRoles` for the pattern).

## Open decision

Whether the community edition keeps `super_admin` as the name of the installation-owner role, or moves the top of the hierarchy to `account_owner`, is a product decision pending with the TL. It does not change anything above: the invariant, the guard and the reconciliation apply to whichever role is the installation owner.
