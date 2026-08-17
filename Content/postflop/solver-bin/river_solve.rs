// River-spot driver for b-inary/postflop-solver (build-time content tool).
//
// Takes one river spot spec as command-line flags, solves it with the locked
// solver, and writes the COMPLETE solved river subtree as JSON to stdout:
// both players' hand lists with their initial (range) reach weights, and every
// decision node's per-hand per-action frequencies keyed by the action path from
// the root. Terminal nodes are recorded by path only — their payoffs are a
// function of the fixed board and the bet amounts in the action labels, which
// the independent Python checker recomputes from scratch.
//
// Exporting the whole tree (not just the OOP root) is what lets a SEPARATE
// best-response calculator recompute exploitability = (mes_ev[0]+mes_ev[1])/2
// without sharing code with the solver. All numbers are the solver's raw units
// (chips, probabilities in [0,1]); no rounding policy lives here.
//
// This is an ADDED file copied into a pristine checkout's `src/bin/` by the
// generator; it never modifies the locked solver source, and does not use the
// `bincode` feature.

use postflop_solver::*;
use std::collections::HashMap;
use std::process::exit;

fn fail(msg: &str) -> ! {
    eprintln!("river_solve: {msg}");
    exit(2);
}

fn parse_flags() -> HashMap<String, String> {
    let mut map = HashMap::new();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        let key = &args[i];
        if let Some(name) = key.strip_prefix("--") {
            if i + 1 >= args.len() {
                fail(&format!("flag {key} has no value"));
            }
            map.insert(name.to_string(), args[i + 1].clone());
            i += 2;
        } else {
            fail(&format!("unexpected argument {key}"));
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
            '\n' => out.push_str("\\n"),
            _ => out.push(c),
        }
    }
    out
}

fn num(x: f64) -> String {
    format!("{x:.10}")
}

/// Depth-first walk of the solved tree. Each call re-navigates from the root
/// along `path` (river trees are shallow, so this is cheap) and emits one JSON
/// node object; decision nodes recurse into every child action.
fn walk(game: &mut PostFlopGame, path: &[usize], n_oop: usize, n_ip: usize, out: &mut Vec<String>) {
    game.back_to_root();
    for &a in path {
        game.play(a);
    }

    let path_json = format!(
        "[{}]",
        path.iter().map(|a| a.to_string()).collect::<Vec<_>>().join(",")
    );

    if game.is_terminal_node() {
        out.push(format!("{{\"path\":{path_json},\"type\":\"terminal\"}}"));
        return;
    }
    if game.is_chance_node() {
        // A river tree has no chance nodes; guard defensively rather than emit
        // an ambiguous node.
        fail("unexpected chance node in a river tree");
    }

    let player = game.current_player();
    let actions = game.available_actions();
    let n_actions = actions.len();
    let n_hands = if player == 0 { n_oop } else { n_ip };
    let strategy = game.strategy(); // [action * n_hands + hand]

    let action_labels: Vec<String> =
        actions.iter().map(|a| format!("\"{}\"", esc(&format!("{a:?}")))).collect();

    // strategy[action][hand]
    let per_action: Vec<String> = (0..n_actions)
        .map(|i| {
            let freqs: Vec<String> =
                (0..n_hands).map(|j| num(strategy[i * n_hands + j] as f64)).collect();
            format!("[{}]", freqs.join(","))
        })
        .collect();

    out.push(format!(
        "{{\"path\":{path_json},\"type\":\"decision\",\"player\":{player},\"actions\":[{}],\"strategy\":[{}]}}",
        action_labels.join(","),
        per_action.join(",")
    ));

    for i in 0..n_actions {
        let mut child = path.to_vec();
        child.push(i);
        walk(game, &child, n_oop, n_ip, out);
    }
}

fn main() {
    let m = parse_flags();
    let oop_range = req(&m, "oop-range").to_string();
    let ip_range = req(&m, "ip-range").to_string();
    let flop_str = req(&m, "flop").to_string();
    let turn_str = req(&m, "turn").to_string();
    let river_str = req(&m, "river").to_string();
    let starting_pot: i32 = req(&m, "starting-pot-chips").parse().unwrap_or_else(|_| fail("bad starting-pot-chips"));
    let effective_stack: i32 = req(&m, "effective-stack-chips").parse().unwrap_or_else(|_| fail("bad effective-stack-chips"));
    // BetSizeOptions::try_from((bet_sizes, raise_sizes)) — the tuple is
    // (bet, raise), shared by both players, NOT (oop, ip).
    let bet_sizes_str = req(&m, "bet-sizes").to_string();
    let raise_sizes_str = req(&m, "raise-sizes").to_string();
    let max_iters: u32 = req(&m, "max-iterations").parse().unwrap_or_else(|_| fail("bad max-iterations"));
    let target_frac: f32 = req(&m, "target-exploitability-fraction").parse().unwrap_or_else(|_| fail("bad target fraction"));

    let card_config = CardConfig {
        range: [
            oop_range.parse().unwrap_or_else(|_| fail("bad oop-range")),
            ip_range.parse().unwrap_or_else(|_| fail("bad ip-range")),
        ],
        flop: flop_from_str(&flop_str).unwrap_or_else(|_| fail("bad flop")),
        turn: card_from_str(&turn_str).unwrap_or_else(|_| fail("bad turn")),
        river: card_from_str(&river_str).unwrap_or_else(|_| fail("bad river")),
    };

    let bets = BetSizeOptions::try_from((bet_sizes_str.as_str(), raise_sizes_str.as_str()))
        .unwrap_or_else(|_| fail("bad bet/raise sizes"));
    let tree_config = TreeConfig {
        initial_state: BoardState::River,
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
    let exploitability = solve(&mut game, max_iters, target, false);
    game.cache_normalized_weights();

    // Fixed hand lists + initial range reach weights for both players.
    let oop_hands = holes_to_strings(game.private_cards(0)).unwrap_or_else(|_| fail("oop hole fmt"));
    let ip_hands = holes_to_strings(game.private_cards(1)).unwrap_or_else(|_| fail("ip hole fmt"));
    let oop_w = game.initial_weights(0).to_vec();
    let ip_w = game.initial_weights(1).to_vec();
    let n_oop = oop_hands.len();
    let n_ip = ip_hands.len();

    let hand_arr = |hands: &[String], w: &[f32]| -> String {
        let items: Vec<String> = (0..hands.len())
            .map(|j| format!("{{\"hand\":\"{}\",\"weight\":{}}}", esc(&hands[j]), num(w[j] as f64)))
            .collect();
        format!("[{}]", items.join(","))
    };

    // OOP root per-action EV (chips), needed so content range cells can carry an
    // EV per action for EV-loss grading. Captured at the root before the walk.
    // `back_to_root` clears the normalized-weight cache, so re-cache before
    // reading EVs.
    game.back_to_root();
    game.cache_normalized_weights();
    let root_actions = game.available_actions();
    let root_ev = game.expected_values_detail(0); // [action * n_oop + hand], chips
    let n_root_actions = root_actions.len();
    let root_ev_json: Vec<String> = (0..n_root_actions)
        .map(|i| {
            let per_hand: Vec<String> = (0..n_oop).map(|j| num(root_ev[i * n_oop + j] as f64)).collect();
            format!("[{}]", per_hand.join(","))
        })
        .collect();

    let mut nodes: Vec<String> = Vec::new();
    walk(&mut game, &[], n_oop, n_ip, &mut nodes);

    let out = format!(
        concat!(
            "{{\"solver\":\"b-inary/postflop-solver\",\"street\":\"river\",",
            "\"board\":\"{board}\",\"oopRange\":\"{oop}\",\"ipRange\":\"{ip}\",",
            "\"startingPotChips\":{pot},\"effectiveStackChips\":{stack},",
            "\"iterations\":{iters},\"exploitabilityChips\":{expl},",
            "\"players\":{{\"oop\":{{\"hands\":{oopn}}},\"ip\":{{\"hands\":{ipn}}}}},",
            "\"oopRootActionEVsChips\":[{rootev}],",
            "\"nodes\":[{nodes}]}}"
        ),
        board = esc(&format!("{flop_str}{turn_str}{river_str}")),
        oop = esc(&oop_range),
        ip = esc(&ip_range),
        pot = starting_pot,
        stack = effective_stack,
        iters = max_iters,
        expl = num(exploitability as f64),
        oopn = hand_arr(&oop_hands, &oop_w),
        ipn = hand_arr(&ip_hands, &ip_w),
        rootev = root_ev_json.join(","),
        nodes = nodes.join(","),
    );
    println!("{out}");
}
