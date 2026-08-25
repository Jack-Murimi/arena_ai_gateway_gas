# Gateway Gas Enterprises — POS & ERP

Flutter point-of-sale + ERP system for **Gateway Gas Enterprises**, backed by
[Supabase](https://supabase.com) (Auth + PostgreSQL).

## Modules

| Module | Status |
|---|---|
| Auth (email/password, roles) | 🚧 Skeleton done |
| POS (cart, payments) | 🚧 Layout skeleton |
| Inventory & stock | 🚧 Schema ready — inter-branch transfer workflow included |
| Customers, credit & deposits | 🚧 Schema ready |
| Suppliers & purchases | 🚧 Schema ready |
| Reports | 📋 Planned |
| Receipt printing | 📋 Planned |

## Setup

### 1. Supabase

1. Create a project at https://supabase.com (free tier is fine to start).
2. Open **SQL Editor**, paste the contents of
   [`supabase/migrations/0001_initial_schema.sql`](supabase/migrations/0001_initial_schema.sql)
   and click **Run**. This creates all tables, triggers, RLS policies and seed data.
3. Open **Authentication → Users → Add user** and create your first user
   (e.g. `admin@gatewaygas.co.ke`). Optionally set their role in the
   `profiles` table via the Table Editor (`admin`, `cashier` or `stock_manager`).

### 2. Run the app

```sh
flutter pub get
flutter run
```

The app ships with the dev project's Supabase URL and publishable key baked
in, so it connects out of the box. To point at a different project (e.g. your
production Supabase), override via `--dart-define`:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT-REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_XXX
```

- Find the URL + key under **Project Settings → API** (publishable key).
- The publishable key is a *public* key — safe to embed (security comes from
  Row Level Security, which the migration enables).

To run on a specific device:

```sh
flutter run -d windows      # desktop till
flutter run -d chrome       # web
flutter run -d <device-id>  # Android/anything
```

## Project layout

```
lib/
  main.dart                  # Supabase init + app entry
  app.dart                   # root widget, auth-based routing
  core/
    config/app_config.dart   # --dart-define config
    theme/app_theme.dart     # brand theme (deep green + flame amber)
    utils/formatters.dart    # KSh / date formatting
    widgets/                 # shared widgets
  features/
    auth/                    # login + auth state controller
    shell/                   # navigation shell (rail on desktop)
    dashboard/               # stats overview
    pos/                     # point of sale
    inventory/               # stock & products
    customers/               # customers, credit, deposits
    reports/                 # sales & analytics
    settings/                # app info, sign out
supabase/migrations/         # SQL schema (apply in Supabase SQL editor)
```

## Conventions

- Feature folders under `lib/features/<module>/` with `data/` (Supabase
  queries) and `presentation/` (widgets) subfolders as features grow.
- Money in KSh as `numeric(12,2)`; dates as `timestamptz` (UTC, display local).
- All DB writes go through Row Level Security; never use the service-role key
  in the app.
