// River-spot driver for b-inary/postflop-solver (build-time content tool).
//
// Takes one river spot spec as command-line flags, solves it with the locked
// solver, and writes the OOP root-node decision — per hand: the frequency and
// EV of each available action — plus the measured exploitability, as JSON to
// stdout. All numbers are the solver's raw units (chips for pot/stack/EV,
// probabilities in [0,1]); conversion to exact centi-BB / milli-BB / basis
// points happens downstream in Python, so this file carries no rounding policy
// and pulls in no serialization dependency.
//
// This is an ADDED file copied into a pristine checkout's `src/bin/` by the
// generator; it never modifies the locked solver source. It does not use the
// `bincode` feature (dropped at build time), reading everything from the
// in-memory game after `solve`.

use postflop_solver::*;
use std::collections::HashMap;
use std::process::exit;

fn fail(msg: &str) -> ! {
    eprintln!("river_solve: {msg}");
    exit(2);
}

/// Parse `--key value` pairs into a map.
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

/// Minimal JSON string escaping (labels are ASCII card/action text; escape the
/// characters JSON requires anyway).
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

/// Fixed-precision float formatting so the output is deterministic across runs.
fn num(x: f64) -> String {
    format!("{x:.10}")
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
    let oop_bets = req(&m, "oop-bet-sizes").to_string();
    let ip_bets = req(&m, "ip-bet-sizes").to_string();
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

    let bets = BetSizeOptions::try_from((oop_bets.as_str(), ip_bets.as_str()))
        .unwrap_or_else(|_| fail("bad bet sizes"));
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

    // Root node = OOP's first decision on the river.
    let actions = game.available_actions();
    let hands = game.private_cards(0);
    let hand_strs = holes_to_strings(hands).unwrap_or_else(|_| fail("hole formatting failed"));
    let strategy = game.strategy(); // [action * n_hands + hand] probability
    let ev_detail = game.expected_values_detail(0); // [action * n_hands + hand] EV (chips)
    let weights = game.normalized_weights(0);
    let n = hands.len();
    let n_actions = actions.len();

    let action_labels: Vec<String> = actions.iter().map(|a| format!("{a:?}")).collect();

    let mut hand_json: Vec<String> = Vec::new();
    for j in 0..n {
        // Skip hands overlapping the board (undefined strategy per the docs).
        if weights[j] <= 0.0 {
            continue;
        }
        let freqs: Vec<String> = (0..n_actions).map(|i| num(strategy[i * n + j] as f64)).collect();
        let evs: Vec<String> = (0..n_actions).map(|i| num(ev_detail[i * n + j] as f64)).collect();
        hand_json.push(format!(
            "{{\"hand\":\"{}\",\"weight\":{},\"actionFrequencies\":[{}],\"actionEVsChips\":[{}]}}",
            esc(&hand_strs[j]),
            num(weights[j] as f64),
            freqs.join(","),
            evs.join(","),
        ));
    }

    let actions_json: Vec<String> = action_labels.iter().map(|a| format!("\"{}\"", esc(a))).collect();

    let out = format!(
        concat!(
            "{{\"solver\":\"b-inary/postflop-solver\",\"street\":\"river\",",
            "\"board\":\"{board}\",\"oopRange\":\"{oop}\",\"ipRange\":\"{ip}\",",
            "\"startingPotChips\":{pot},\"effectiveStackChips\":{stack},",
            "\"iterations\":{iters},\"exploitabilityChips\":{expl},",
            "\"oopActions\":[{acts}],\"oopHands\":[{hands}]}}"
        ),
        board = esc(&format!("{flop_str}{turn_str}{river_str}")),
        oop = esc(&oop_range),
        ip = esc(&ip_range),
        pot = starting_pot,
        stack = effective_stack,
        iters = max_iters,
        expl = num(exploitability as f64),
        acts = actions_json.join(","),
        hands = hand_json.join(","),
    );
    println!("{out}");
}
