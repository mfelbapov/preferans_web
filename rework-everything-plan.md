# Rebuild the UI by hand — learning exercise

## Context

User wants to use this Preferans codebase as a learning tool for Phoenix LiveView. Plan: delete the existing UI down to the studs and rebuild it by hand, keeping the entire game engine, business logic, supervision tree, and database layer intact. The goal is learning, not shipping — so the plan is about defining a clean tear-down boundary, not about shipping a replacement UI.

## The architecture in three layers

1. **C++ engine (`priv/bin/preferans_server`)** — rules + AI, JSON over stdio. Untouched.
2. **Elixir contexts (`lib/preferans_web/`)** — wraps the engine, owns game state in a GenServer per game, broadcasts updates over PubSub. **This is the stable surface the rebuilt UI will talk to.**
3. **LiveView UI (`lib/preferans_web_web/` + `assets/`)** — what gets rebuilt.

## The API contract the rebuilt UI must speak

These are the only entry points the UI needs. Anything else is implementation detail.

**Functions to call:**
- `PreferansWeb.Game.start_solo_game(user_id, opts)` → `{:ok, game_id}` ([lib/preferans_web/game.ex](lib/preferans_web/game.ex))
- `PreferansWeb.Game.find_user_active_game(user_id)` ([lib/preferans_web/game.ex](lib/preferans_web/game.ex))
- `PreferansWeb.Game.GameServer.subscribe(game_id)` ([lib/preferans_web/game/game_server.ex](lib/preferans_web/game/game_server.ex))
- `PreferansWeb.Game.GameServer.get_player_view(game_id, seat)`
- `PreferansWeb.Game.GameServer.submit_action(game_id, seat, action)`
- `PreferansWeb.Game.GameServer.deal_next_hand(game_id)`
- `PreferansWeb.Accounts.*` for auth ([lib/preferans_web/accounts.ex](lib/preferans_web/accounts.ex))

**PubSub messages to handle** (topic: `"game:#{game_id}"`):
- `{:action_played, game_id, seat, action}`
- `{:game_state_updated, game_id}`
- `{:new_hand_starting, game_id}`
- `{:hand_completed, game_id, scoring_result}`
- `{:match_ended, game_id, final_scores}`

## Recommended scope: keep auth + minimal lobby, gut gameplay

**Why:** auth is `phx.gen.auth` boilerplate (no learning value). A minimal lobby keeps a working "start a game" entry point so you can iterate on `GameLive` without re-doing routing every time. The real learning is the in-game UI: 8+ phases, PubSub-driven updates, card layout.

### Delete

- [lib/preferans_web_web/live/game_live.ex](lib/preferans_web_web/live/game_live.ex) — main gameplay LiveView (rebuild from scratch)
- [lib/preferans_web_web/components/game_components.ex](lib/preferans_web_web/components/game_components.ex) — 815 lines of phase rendering
- [lib/preferans_web_web/components/card_component.ex](lib/preferans_web_web/components/card_component.ex) — single card render
- Stub LiveViews: [history_live.ex](lib/preferans_web_web/live/history_live.ex), [replay_live.ex](lib/preferans_web_web/live/replay_live.ex), [profile_live.ex](lib/preferans_web_web/live/profile_live.ex)
- Custom game CSS in [assets/css/app.css](assets/css/app.css) (green felt, btn-game variants, card colors)

### Keep

- All of [lib/preferans_web/](lib/preferans_web/) — contexts, schemas, GameServer, engine wrappers
- C++ binary in `priv/bin/`
- [lib/preferans_web/application.ex](lib/preferans_web/application.ex) — supervision tree
- [lib/preferans_web_web/endpoint.ex](lib/preferans_web_web/endpoint.ex), router skeleton, [user_auth.ex](lib/preferans_web_web/user_auth.ex)
- Auth LiveViews: [user_live/login.ex](lib/preferans_web_web/live/user_live/login.ex), [registration.ex](lib/preferans_web_web/live/user_live/registration.ex), [confirmation.ex](lib/preferans_web_web/live/user_live/confirmation.ex), [settings.ex](lib/preferans_web_web/live/user_live/settings.ex)
- A minimal version of [lobby_live.ex](lib/preferans_web_web/live/lobby_live.ex) (just enough to call `start_solo_game` and link to `/game/:id`)
- [core_components.ex](lib/preferans_web_web/components/core_components.ex), [layouts.ex](lib/preferans_web_web/components/layouts.ex) — Phoenix-standard primitives, leave as starter
- All migrations and Ecto schemas

### After deletion, the rebuild process

For each game phase, the loop is:
1. In `GameLive.handle_info(:game_state_updated, ...)`, call `GameServer.get_player_view(game_id, seat)`.
2. Inspect the returned struct in IEx to see what's available for the current phase.
3. Render that phase's view in HEEx.
4. Wire `phx-click` events to `GameServer.submit_action(game_id, seat, action)`.
5. Repeat for the next phase.

## Reference handling: branch it, delete on main

Cut `old-ui` branch from current main before deleting. `git checkout old-ui -- <path>` to peek at the old implementation when stuck. No clutter in working tree on main.

## Verification

- `mix phx.server` boots cleanly with the UI gutted
- Visit `/lobby` → click "new game" → land on `/game/:id` (even if the page is blank)
- `iex -S mix phx.server` → `PreferansWeb.Game.GameServer.get_player_view(game_id, 0)` returns a map (proves engine + GenServer still work)
- `mix test` — engine and context tests still pass; LiveView tests will fail (expected, since LiveViews are gone)
- Auth flow still works: register → log in → reach lobby

## Open questions to resolve before executing

- **Confirm the scope choice** (keep auth + minimal lobby vs. burn it all down vs. keep more).
- **Confirm reference handling** (branch vs. delete-only vs. `_reference/` folder).
- Decide whether to delete LiveView tests now or stub them as you rebuild components.
