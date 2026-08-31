# AGENTS.md

Project conventions and instructions for AI agents working on this repo.

## Post-pull workflow

After every `git pull`, apply any **new** Supabase migrations:

1. Compare `supabase/migrations/` against what is already applied to the
   database and identify new `00NN_*.sql` files.
2. Apply each new migration to the Supabase project. In this repo migrations
   are SQL files applied via the Supabase SQL Editor (or `supabase db push` for
   a linked project). Pick the method the project currently uses and run only
   the migrations not yet applied.
3. Do **not** re-run already-applied migrations.

Note: there is no `supabase/config.toml` in this repo (only `supabase/migrations/`),
so confirm the apply method / DB access before running anything destructive.

## Tech stack

- Flutter app (Dart) + Supabase (Auth + PostgreSQL).
- Migrations live in `supabase/migrations/` as ordered `00NN_*.sql` files.
- README: paste migration SQL into the Supabase SQL Editor to apply.
