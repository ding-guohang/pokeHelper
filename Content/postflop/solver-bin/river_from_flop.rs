// Betting-line river driver for b-inary/postflop-solver (build-time content tool).
//
// Solves a spot FROM THE FLOP, navigates a specified betting line (flop actions,
// turn card, turn actions, river card), and exports the river decision node that
// the line reaches: the river subtree strategy plus the NARROWED ranges at that
// node (normalized reach weights, i.e. the ranges after prior-street betting).
//
// This is what Batch B needs: the river ranges are shaped by the flop/turn
// action, not the raw preflop ranges. The exported reach lets a separate
// best-response checker confirm the river decision is optimal GIVEN those ranges
// (partial independence). The full flop-game convergence is the solver's self-
// reported exploitability (also emitted) plus byte-reproducibility — a flop-game
// from-scratch best response is intractable at this tree size, and the content
// discloses this boundary.
//
// Added file copied into a pristine checkout's src/bin/ by the generator; never
// modifies locked source; no bincode feature.

use postflop_solver::*;
use std::collections::HashMap;
use std::process::exit;

fn fail(msg: &str) -> ! {
    eprintln!("river_from_flop: {msg}");
    exit(2);
}

fn parse_flags() -> HashMap<String, String> {
    let mut map = HashMap::new();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        if let Some(name) = args[i].strip_prefix("--") {
            if i + 1 >= args.len() {
                fail(&format!("flag {} has no value", args[i]));
            }
            map.insert(name.to_string(), args[i + 1].clone());
            i += 2;
        } else {
            fail(&format!("unexpected argument {}", args[i]));
        }
    }
    map
}

fn req<'a>(m: &'a HashMap<String, String>, k: &str) -> &'a str {
    m.get(k).map(String::as_str).unwrap_or_else(|| fail(&format!("--{k} is required")))
}

fn esc(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            _ => out.push(c),
        }
    }
    out
}

fn num(x: f64) -> String {
    format!("{x:.10}")
}

/// Match a line token ("check"/"call"/"fold"/"bet"/"raise"/"allin") to the index
/// of the matching available action at the current node.
fn find_action(game: &PostFlopGame, token: &str) -> usize {
    for (i, a) in game.available_actions().iter().enumerate() {
        let kind = match a {
            Action::Check => "check",
            Action::Call => "call",
            Action::Fold => "fold",
            Action::Bet(_) => "bet",
            Action::Raise(_) => "raise",
            Action::AllIn(_) => "allin",
            _ => continue,
        };
        if kind == token {
            return i;
        }
    }
    fail(&format!("line token '{token}' not available at node; actions were {:?}", game.available_actions()))
}

/// Walk the river subtree, re-navigating from the game root along `prefix` (the
/// line to the river node) then the subtree-relative `sub` path each call.
fn walk(game: &mut PostFlopGame, prefix: &[usize], sub: &[usize], n_oop: usize, n_ip: usize, out: &mut Vec<String>) {
    game.back_to_root();
    for &a in prefix {
        game.play(a);
    }
    for &a in sub {
        game.play(a);
    }

    let sub_json = format!("[{}]", sub.iter().map(|a| a.to_string()).collect::<Vec<_>>().join(","));

    if game.is_terminal_node() {
        out.push(format!("{{\"path\":{sub_json},\"type\":\"terminal\"}}"));
        return;
    }
    if game.is_chance_node() {
        fail("unexpected chance node inside the river subtree");
    }

    let player = game.current_player();
    let actions = game.available_actions();
    let n_actions = actions.len();
    let n_hands = if player == 0 { n_oop } else { n_ip };
    let strategy = game.strategy();
    let labels: Vec<String> = actions.iter().map(|a| format!("\"{}\"", esc(&format!("{a:?}")))).collect();
    let per_action: Vec<String> = (0..n_actions)
        .map(|i| {
            let f: Vec<String> = (0..n_hands).map(|j| num(strategy[i * n_hands + j] as f64)).collect();
            format!("[{}]", f.join(","))
        })
        .collect();
    out.push(format!(
        "{{\"path\":{sub_json},\"type\":\"decision\",\"player\":{player},\"actions\":[{}],\"strategy\":[{}]}}",
        labels.join(","), per_action.join(",")
    ));

    for i in 0..n_actions {
        let mut child = sub.to_vec();
        child.push(i);
        walk(game, prefix, &child, n_oop, n_ip, out);
    }
}

fn main() {
    let m = parse_flags();
    let oop_range = req(&m, "oop-range").to_string();
    let ip_range = req(&m, "ip-range").to_string();
    let flop_str = req(&m, "flop").to_string();
    let starting_pot: i32 = req(&m, "starting-pot-chips").parse().unwrap_or_else(|_| fail("bad pot"));
    let effective_stack: i32 = req(&m, "effective-stack-chips").parse().unwrap_or_else(|_| fail("bad stack"));
    let bet_sizes_str = req(&m, "bet-sizes").to_string();
    let raise_sizes_str = req(&m, "raise-sizes").to_string();
    let max_iters: u32 = req(&m, "max-iterations").parse().unwrap_or_else(|_| fail("bad iters"));
    let target_frac: f32 = req(&m, "target-exploitability-fraction").parse().unwrap_or_else(|_| fail("bad target"));
    // Line: "flopActs;turnCard;turnActs;riverCard", betting segments comma-separated.
    let line = req(&m, "line").to_string();

    let card_config = CardConfig {
        range: [
            oop_range.parse().unwrap_or_else(|_| fail("bad oop-range")),
            ip_range.parse().unwrap_or_else(|_| fail("bad ip-range")),
        ],
        flop: flop_from_str(&flop_str).unwrap_or_else(|_| fail("bad flop")),
        turn: NOT_DEALT,
        river: NOT_DEALT,
    };
    let bets = BetSizeOptions::try_from((bet_sizes_str.as_str(), raise_sizes_str.as_str()))
        .unwrap_or_else(|_| fail("bad bet/raise sizes"));
    let tree_config = TreeConfig {
        initial_state: BoardState::Flop,
        starting_pot,
        effective_stack,
        rake_rate: 0.0,
        rake_cap: 0.0,
        flop_bet_sizes: [bets.clone(), bets.clone()],
        turn_bet_sizes: [bets.clone(), bets.clone()],
        river_bet_sizes: [bets.clone(), bets.clone()],
        turn_donk_sizes: None,
        river_donk_sizes: None,
        add_allin_threshold: 1.5,
        force_allin_threshold: 0.15,
        merging_threshold: 0.1,
    };
    let action_tree = ActionTree::new(tree_config).unwrap_or_else(|_| fail("action tree build failed"));
    let mut game = PostFlopGame::with_config(card_config, action_tree)
        .unwrap_or_else(|_| fail("game build failed"));
    game.allocate_memory(false);

    let target = starting_pot as f32 * target_frac;
    let full_game_exploitability = solve(&mut game, max_iters, target, false);

    // Navigate the betting line, recording the play-index prefix.
    game.back_to_root();
    let mut prefix: Vec<usize> = Vec::new();
    let segments: Vec<&str> = line.split(';').collect();
    for (seg_idx, seg) in segments.iter().enumerate() {
        if seg_idx % 2 == 0 {
            // Betting segment.
            for token in seg.split(',').filter(|t| !t.is_empty()) {
                let idx = find_action(&game, token);
                prefix.push(idx);
                game.play(idx);
            }
        } else {
            // Chance card (turn or river).
            if !game.is_chance_node() {
                fail("expected a chance node for the dealt card");
            }
            let card = card_from_str(seg).unwrap_or_else(|_| fail("bad line card"));
            prefix.push(card as usize);
            game.play(card as usize);
        }
    }

    if game.is_terminal_node() || game.is_chance_node() {
        fail("line did not end on a river decision node");
    }

    // Pot going INTO the river = flop starting pot + both players' prior-street
    // contributions. The checker needs this (not the flop pot) so river fold-vs-
    // call payoffs are correct.
    let tba = game.total_bet_amount();
    let river_pot = starting_pot + tba[0] + tba[1];

    game.cache_normalized_weights(); // required for expected_values_detail below
    let oop_hands = holes_to_strings(game.private_cards(0)).unwrap_or_else(|_| fail("oop fmt"));
    let ip_hands = holes_to_strings(game.private_cards(1)).unwrap_or_else(|_| fail("ip fmt"));
    // RAW reach (initial range weight x product of the player's action frequencies
    // along the line), NOT normalized_weights: the latter bakes in card-removal
    // marginalization, which the independent checker also applies -> double count.
    // Raw reach matches the Batch A initial_weights convention (checker applies
    // pairwise card removal itself).
    let oop_w = game.weights(0).to_vec();
    let ip_w = game.weights(1).to_vec();
    let n_oop = oop_hands.len();
    let n_ip = ip_hands.len();

    // Node-relative EV for the acting player at the river node.
    let node_player = game.current_player();
    let node_ev = game.expected_values_detail(node_player);
    let node_actions = game.available_actions();
    let n_node_actions = node_actions.len();
    let node_ev_json: Vec<String> = (0..n_node_actions)
        .map(|i| {
            let per: Vec<String> = (0..if node_player == 0 { n_oop } else { n_ip })
                .map(|j| num(node_ev[i * (if node_player == 0 { n_oop } else { n_ip }) + j] as f64))
                .collect();
            format!("[{}]", per.join(","))
        })
        .collect();

    let hand_arr = |hands: &[String], w: &[f32]| -> String {
        let items: Vec<String> = (0..hands.len())
            .map(|j| format!("{{\"hand\":\"{}\",\"weight\":{}}}", esc(&hands[j]), num(w[j] as f64)))
            .collect();
        format!("[{}]", items.join(","))
    };

    let mut nodes: Vec<String> = Vec::new();
    walk(&mut game, &prefix, &[], n_oop, n_ip, &mut nodes);

    // River card is the last segment.
    let river_card = segments.last().copied().unwrap_or("");
    let board = format!("{flop_str}{}{}", segments.get(1).copied().unwrap_or(""), river_card);

    let out = format!(
        concat!(
            "{{\"solver\":\"b-inary/postflop-solver\",\"street\":\"river\",\"mode\":\"from-flop\",",
            "\"board\":\"{board}\",\"flop\":\"{flop}\",\"line\":\"{line}\",",
            "\"oopRange\":\"{oop}\",\"ipRange\":\"{ip}\",",
            "\"startingPotChips\":{pot},\"riverPotChips\":{rpot},\"effectiveStackChips\":{stack},\"iterations\":{iters},",
            "\"fullGameExploitabilityChips\":{fge},\"nodePlayer\":{np},",
            "\"players\":{{\"oop\":{{\"hands\":{oopn}}},\"ip\":{{\"hands\":{ipn}}}}},",
            "\"nodeActionEVsChips\":[{nodeev}],\"nodes\":[{nodes}]}}"
        ),
        board = esc(&board),
        flop = esc(&flop_str),
        line = esc(&line),
        oop = esc(&oop_range),
        ip = esc(&ip_range),
        pot = starting_pot,
        rpot = river_pot,
        stack = effective_stack,
        iters = max_iters,
        fge = num(full_game_exploitability as f64),
        np = node_player,
        oopn = hand_arr(&oop_hands, &oop_w),
        ipn = hand_arr(&ip_hands, &ip_w),
        nodeev = node_ev_json.join(","),
        nodes = nodes.join(","),
    );
    println!("{out}");
}
