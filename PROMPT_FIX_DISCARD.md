# Bug Fix: Discard Card Selection Not Working

## The Problem

During the discard phase, clicking cards does nothing visible. The events DO fire — server logs show:

```
[debug] HANDLE EVENT "toggle_discard" in PreferansWebWeb.GameLive
  Parameters: %{"card" => "karo:ten"}
[debug] Replied in 399µs
[debug] HANDLE EVENT "toggle_discard" in PreferansWebWeb.GameLive
  Parameters: %{"card" => "karo:seven"}
[debug] Replied in 403µs
[debug] HANDLE EVENT "confirm_discard" in PreferansWebWeb.GameLive
  Parameters: %{"value" => ""}
```

So the click events reach the server and the handler replies. But:
- Cards do NOT visually highlight when clicked
- The confirm discard button either doesn't appear or doesn't work
- No errors in terminal — it just silently does nothing

## What This Means

The events fire, but the socket assigns are probably not updating correctly, OR the template is not reading the assigns correctly. Common causes:

1. **`selected_discards` assign not initialized** — if it's not in the socket assigns on mount, the template can't read it
2. **Card comparison failing** — the card tuple `{:karo, :ten}` parsed from the string `"karo:ten"` might not match the cards in the hand due to format mismatch (e.g., strings vs atoms, or the card format in the hand is different from what's being compared)
3. **Template not checking the right assign** — the template might check `@selected` instead of `@selected_discards`, or use a different variable name
4. **`assign` not called correctly** — the handler might compute the new set but forget to actually `assign` it to the socket
5. **MapSet vs List mismatch** — if selected_discards is a MapSet but the template checks with `card in @selected_discards` using a List function, it might not work
6. **The confirm_discard handler doesn't read selected_discards** — it might not extract the cards from the assign, or it might format the action wrong for the GameServer

## How to Fix

### Step 1: Check assign initialization

In `mount/3` or wherever the socket assigns are set up, make sure `selected_discards` is initialized:

```elixir
|> assign(:selected_discards, MapSet.new())
```

It MUST be present before the first render. If it's only set when entering discard phase, the template will crash or silently fail.

### Step 2: Check the toggle_discard handler

It should look like this:

```elixir
def handle_event("toggle_discard", %{"card" => card_key}, socket) do
  card = Cards.parse_card_key(card_key)  # "karo:ten" -> {:karo, :ten}
  selected = socket.assigns.selected_discards

  selected =
    if MapSet.member?(selected, card) do
      MapSet.delete(selected, card)
    else
      if MapSet.size(selected) < 2 do
        MapSet.put(selected, card)
      else
        selected  # already 2 selected, ignore
      end
    end

  {:noreply, assign(socket, :selected_discards, selected)}
end
```

**Verify:**
- `Cards.parse_card_key/1` returns `{:karo, :ten}` (atoms, not strings)
- The hand contains cards in the SAME format: `{:karo, :ten}` not `%{suit: :karo, rank: :ten}` or `"karo:ten"`
- `assign` is called with the new `selected` value
- The function returns `{:noreply, socket}` with the UPDATED socket

### Step 3: Check card format consistency

**THIS IS THE MOST LIKELY BUG.** Add debug logging to verify:

```elixir
def handle_event("toggle_discard", %{"card" => card_key}, socket) do
  card = Cards.parse_card_key(card_key)
  IO.inspect(card, label: "PARSED CARD")
  IO.inspect(hd(socket.assigns.view.my_hand), label: "FIRST CARD IN HAND")
  IO.inspect(card == hd(socket.assigns.view.my_hand), label: "FORMATS MATCH?")
  # ... rest of handler
end
```

If `FORMATS MATCH?` prints `false`, that's the bug. The card format from `parse_card_key` doesn't match the format in the hand. Fix `parse_card_key` or fix how cards are stored in the hand.

### Step 4: Check the template

The card component during discard phase should:

```heex
<%!-- For each card in my_hand during discard phase --%>
<div
  :for={card <- @view.my_hand}
  phx-click="toggle_discard"
  phx-value-card={Cards.card_to_key(card)}
  class={[
    "card",
    card_selected?(card, @selected_discards) && "card--selected"
  ]}
>
  <%!-- card face rendering --%>
</div>
```

Where:
```elixir
defp card_selected?(card, selected_discards) do
  MapSet.member?(selected_discards, card)
end
```

**Check:**
- Is the CSS class `card--selected` actually defined with visible styles? (e.g., `transform: translateY(-12px); box-shadow: 0 0 0 2px blue;`)
- Is `@selected_discards` the correct assign name used in the template?
- Is the `:for` loop using `@view.my_hand`?
- Is the `phx-click="toggle_discard"` on the clickable element (not a parent div that might swallow it)?

### Step 5: Check confirm_discard handler

```elixir
def handle_event("confirm_discard", _params, socket) do
  selected = socket.assigns.selected_discards

  if MapSet.size(selected) == 2 do
    [card1, card2] = MapSet.to_list(selected)
    action = {:discard, card1, card2}

    case GameServer.submit_action(socket.assigns.game_id, socket.assigns.seat, action) do
      :ok ->
        {:noreply, assign(socket, :selected_discards, MapSet.new())}

      {:error, reason} ->
        IO.inspect(reason, label: "DISCARD ERROR")
        {:noreply, socket}
    end
  else
    # Not enough cards selected
    {:noreply, socket}
  end
end
```

**Check:**
- Does GameServer.submit_action expect `{:discard, card1, card2}` or some other format?
- Does MockEngine.apply_action match on `{:discard, card1, card2}`?
- After confirm, is `selected_discards` reset to empty MapSet?

### Step 6: Check the confirm button visibility

The confirm button should only appear when 2 cards are selected:

```heex
<button
  :if={MapSet.size(@selected_discards) == 2}
  phx-click="confirm_discard"
  class="btn-primary"
>
  Baci (Discard)
</button>
```

If the button uses `:if={length(@selected_discards) == 2}` but `selected_discards` is a MapSet, `length` won't work — use `MapSet.size/1`.

### Step 7: Check that state refresh doesn't clobber selection

When PubSub broadcasts `{:game_state_updated, _}`, the handler re-fetches the view and reassigns. Make sure it does NOT reset `selected_discards`:

```elixir
def handle_info({:game_state_updated, _game_id}, socket) do
  {:ok, view} = GameServer.get_player_view(socket.assigns.game_id, socket.assigns.seat)
  # ONLY update :view, do NOT touch :selected_discards
  {:noreply, assign(socket, :view, view)}
end
```

If this handler does `assign(socket, view: view, selected_discards: MapSet.new())`, it will reset the selection every time any state update comes in (including AI moves in other phases that trigger broadcasts).

## Quick Smoke Test

After fixing, test this exact sequence:
1. Start a new game
2. Win the bidding (AI should pass quickly)
3. See talon cards revealed
4. You should see 12 cards in your hand
5. Click one card → it should visually lift up or highlight
6. Click a second card → it should also highlight
7. "Baci" / "Discard" button should appear
8. Click the button → 2 cards removed, hand goes back to 10 cards
9. Game declaration options should appear

## Write Tests

Add a LiveView test that verifies the discard flow:

```elixir
test "discard phase — clicking cards toggles selection", %{conn: conn} do
  # Setup: create a game, advance to discard phase somehow
  # (may need to mock the game server or set up state directly)
  
  {:ok, view, _html} = live(conn, ~p"/game/#{game_id}")
  
  # Click first card
  html = view |> element("[phx-value-card='karo:ten']") |> render_click()
  assert html =~ "card--selected"  # or whatever the selected class is
  
  # Click second card
  html = view |> element("[phx-value-card='herc:ace']") |> render_click()
  
  # Confirm button should be visible
  assert html =~ "confirm_discard"
  
  # Click confirm
  html = view |> element("[phx-click='confirm_discard']") |> render_click()
  
  # Should transition to declare phase
  assert html =~ "declare"  # or whatever indicates the next phase
end
```
