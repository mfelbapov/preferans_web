# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PreferansWeb is a Phoenix 1.8 / LiveView web application using Elixir, PostgreSQL, Tailwind CSS v4, and daisyUI. HTTP server is Bandit.

## Common Commands

- `mix setup` — install deps, create/migrate DB, build assets
- `mix phx.server` — start dev server (localhost:4000)
- `mix test` — run all tests (auto-creates and migrates test DB)
- `mix test test/path/to_test.exs` — run a single test file
- `mix test --failed` — re-run previously failed tests
- `mix format` — format all code
- `mix precommit` — compile (warnings-as-errors), unlock unused deps, format, and test. **Run this before committing.**
- `mix ecto.migrate` — run pending migrations
- `mix ecto.reset` — drop + recreate + migrate + seed DB

## Architecture

- **`PreferansWeb`** (`lib/preferans_web/`) — business logic, contexts, Ecto repo, mailer
- **`PreferansWebWeb`** (`lib/preferans_web_web/`) — web layer: endpoint, router, controllers, LiveViews, components
- `lib/preferans_web_web/components/core_components.ex` — reusable UI components (`<.input>`, `<.icon>`, `<.flash_group>`, etc.)
- `lib/preferans_web_web/components/layouts.ex` — layout module; all LiveView templates must start with `<Layouts.app flash={@flash} ...>`
- `assets/js/app.js` — JS entry point; vendor deps must be imported here (no inline `<script>` tags)
- `assets/css/app.css` — CSS entry point; uses Tailwind v4 `@import "tailwindcss"` syntax (no `tailwind.config.js`)

## Key Conventions

### Elixir / Phoenix
- Use `Req` for HTTP requests (never httpoison/tesla/httpc)
- Never nest multiple modules in one file
- Use `cond` for multiple conditionals (no `if/elsif` in Elixir)
- Use `Enum.at/2` for list index access (lists don't support `list[i]`)
- Bind block expression results: `socket = if ... do ... end`
- Never use map syntax on structs; use `struct.field` or `Ecto.Changeset.get_field/2`
- Predicate functions end with `?` (reserve `is_` prefix for guards)

### Contexts
- Each context (`lib/preferans_web/context_name.ex`) is a facade with a clean public API (`create_thing/2`, `list_things/1`, `get_thing!/1`); internal helpers stay private
- Schemas live in subdirectories under their context (`lib/preferans_web/context_name/schema.ex`)
- Use `!` bang variants for functions that raise on not-found
- Test fixtures should use context public API (not direct Repo inserts)
- Use `Enum.reduce/3` for dynamic query filtering from params

### Ecto
- Always preload associations needed in templates (avoid N+1)
- Schema fields use `:string` type even for text columns
- Never put programmatic fields (e.g. `user_id`) in `cast` calls
- Use `Ecto.Changeset.get_field/2` to read changeset fields
- Use `:utc_datetime` for timestamp fields
- Prefer flexible `:map` fields for variant-specific metadata over wide schemas
- Use `Repo.insert_all/3` with `on_conflict: :nothing` for bulk operations

### LiveView
- Use streams for collections (never assign raw lists); use `stream/3`, `stream_delete/3`
- Streams are not enumerable — refetch + `reset: true` to filter
- Use `<.link navigate={href}>` / `<.link patch={href}>` (never `live_redirect`/`live_patch`)
- Avoid LiveComponents unless specifically needed
- LiveView modules use `Live` suffix: `PreferansWebWeb.ThingLive`
- Router scopes are already aliased to `PreferansWebWeb`
- `phx-hook` + custom DOM management requires `phx-update="ignore"`
- Use reusable `on_mount` hooks for cross-cutting concerns (auth, locale); compose via separate `live_session` blocks
- Group routes by auth level in separate `live_session` blocks with appropriate hook sets
- Single file per LiveView: mount -> event handlers -> render -> private helpers

### Templates (HEEx)
- Always use `~H` sigil or `.html.heex` files (never `~E`)
- Forms: `<.form for={@form}>` with `to_form/2` (never pass changeset directly to template)
- Use `<.input field={@form[:field]}>` component for inputs
- Use `<.icon name="hero-x-mark">` for icons (never Heroicons modules)
- `<.flash_group>` only in `layouts.ex`
- Use `{...}` for attribute interpolation; `<%= %>` only for block constructs in tag bodies
- Use `class={["base", condition && "extra"]}` list syntax for conditional classes
- HEEx comments: `<%!-- comment --%>`
- Literal curlies in code blocks need `phx-no-curly-interpolation` on parent tag
- Add unique DOM IDs to key elements (forms, buttons) for testability

### CSS / JS
- Tailwind CSS v4 with `@import "tailwindcss" source(none)` syntax in `app.css`
- Write tailwind-based components manually instead of using daisyUI components directly
- Use daisyUI semantic classes; never hardcode Tailwind color palettes directly
- Component variant pattern: `[base, variant_class, size_class, modifier_classes, custom_class] |> List.flatten() |> Enum.filter(& &1) |> Enum.join(" ")`
- Never use `@apply` in raw CSS
- Only `app.js` and `app.css` bundles are supported; no external script/link tags in layouts

### Testing
- Uses ExUnit + Phoenix.LiveViewTest + LazyHTML
- Test with `element/2`, `has_element/2` selectors — never assert against raw HTML strings
- Test outcomes, not implementation details
- Debug test failures with LazyHTML selectors: `LazyHTML.filter(document, "selector")`
- Fixtures in `test/support/fixtures/` — always use context public API, not direct DB inserts
- Use `System.unique_integer/0` for test data isolation (e.g. unique emails)
