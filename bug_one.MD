=== GAME DEBUG STATE ===
Phase: hand_over
Current Player: -1
Dealer: 1
Declarer: 2
Game Type: pik
Game Value: 2
Is Igra: false
Kontra Level: 1
Kontra Giver: 0

=== PLAYERS ===
Seat 0: password (Human)
Seat 1: Bot Duško (AI)
Seat 2: Bot Nikola (AI)

=== MY SEAT: 0 ===

=== HAND ===
["9C", "10C", "QC"]

=== TALON ===
["QD", "KH"]

=== LEGAL ACTIONS ===
nil

=== BID HISTORY ===
Seat 2: {:bid, 2}
Seat 0: :dalje
Seat 1: :dalje

=== DEFENSE RESPONSES ===
Seat 0: :poziv
Seat 1: :ne_dodjem
Defenders: [0]

=== TRICK STATE ===
Trick Number: 7
Tricks Won: [7, 1, 2]
Current Trick: []

=== ALL EVENTS ===
%{action: {:bid, 2}, player: 2}
%{action: :dalje, player: 0}
%{action: :dalje, player: 1}
%{action: {:discard, {:karo, :seven}, {:herc, :nine}}, player: 2}
%{action: {:declare, :pik}, player: 2}
%{action: :dodjem, player: 0}
%{action: :ne_dodjem, player: 1}
%{action: :poziv, player: 0}
%{action: :kontra, player: 0}
%{action: :moze, player: 2}
%{action: {:play, {:pik, :ace}}, player: 2}
%{action: {:play, {:pik, :seven}}, player: 0}
%{action: {:play, {:pik, :nine}}, player: 1}
%{action: {:play, {:pik, :jack}}, player: 2}
%{action: {:play, {:pik, :queen}}, player: 0}
%{action: {:play, {:karo, :eight}}, player: 1}
%{action: {:play, {:karo, :ace}}, player: 0}
%{action: {:play, {:karo, :jack}}, player: 1}
%{action: {:play, {:karo, :ten}}, player: 2}
%{action: {:play, {:karo, :nine}}, player: 0}
%{action: {:play, {:karo, :king}}, player: 1}
%{action: {:play, {:karo, :queen}}, player: 2}
%{action: {:play, {:herc, :eight}}, player: 1}
%{action: {:play, {:herc, :king}}, player: 2}
%{action: {:play, {:herc, :ace}}, player: 0}
%{action: {:play, {:herc, :seven}}, player: 0}
%{action: {:play, {:herc, :ten}}, player: 1}
%{action: {:play, {:pik, :eight}}, player: 2}
%{action: {:play, {:pik, :ten}}, player: 2}
%{action: {:play, {:pik, :king}}, player: 0}
%{action: {:play, {:herc, :jack}}, player: 1}

=== MATCH STATE ===
Bule: ~c"``t"
Refes: [2, 2, 2]
Supe Ledger: %{{0, 2} => 128}
Hands Played: 5
Max Refes: 2

=== SCORING RESULT ===
%{"bule_change" => [0, 0, 16], "declarer" => 2, "game_type" => "pik", "is_igra" => false, "passed" => [true, true, false], "refe_consumed" => true, "refe_recorded" => false, "supe_written" => [128, 0, 0], "tricks" => [7, 1, 2]}

=== RAW CPP STATE ===
%{
  "bidding" => %{
    "highest_bid" => 2,
    "highest_bidder" => 2,
    "passed" => [true, true, false]
  },
  "bule" => ~c"``d",
  "current_player" => -1,
  "dealer" => 1,
  "declared_game" => "pik",
  "declarer" => 2,
  "defense" => %{
    "called" => 1,
    "caller" => 0,
    "free_pass" => false,
    "num_active" => 3
  },
  "game_value" => 2,
  "hand" => ["9C", "10C", "QC"],
  "is_igra" => false,
  "kontra_giver" => 0,
  "kontra_level" => 1,
  "opponent_card_counts" => [
    %{"cards" => 3, "player" => 1},
    %{"cards" => 3, "player" => 2}
  ],
  "phase" => "hand_over",
  "refes" => [2, 2, 2],
  "result" => %{
    "bule_change" => [0, 0, 16],
    "declarer" => 2,
    "game_type" => "pik",
    "is_igra" => false,
    "passed" => [true, true, false],
    "refe_consumed" => true,
    "refe_recorded" => false,
    "supe_written" => [128, 0, 0],
    "tricks" => [7, 1, 2]
  },
  "talon" => ["QD", "KH"],
  "trick_play" => %{
    "current_trick" => [],
    "trick_number" => 7,
    "tricks_won" => [7, 1, 2]
  }
}
