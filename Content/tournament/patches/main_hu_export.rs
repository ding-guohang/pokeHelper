// Read-only export binary for heads-up push/fold content.
//
// This file is dropped into a hash-locked checkout of
// b-inary/poker-cfr@a5347082 by generate-hu-pushfold.py. It does NOT modify any
// locked source (cfr.rs / game_push_fold.rs / equity binary); it only consumes
// their public API (cfr::train + PushFoldNode + GameNode::evaluate) so the
// training update formulas and equilibrium are exactly upstream's.
//
// For each effective depth it:
//   1. trains CFR+ until NashConv <= threshold (checkpoint schedule),
//   2. reads the frozen average strategy,
//   3. computes, from that same snapshot, each combo's conditional pure-action
//      EV via the upstream terminal evaluator against equilibrium reach
//      (blocker/card-removal aware), and
//   4. aggregates 1326 combos into 169 canonical classes by ratio-of-sums and
//      quantizes to integer basis points and milli-BB.
//
// Output is a deterministic text block per depth on stdout; the Python driver
// assembles the normalized JSON and snapshot hash. Emitting integers here keeps
// the Rust side dependency-free (no serde_json / no sha2, preserving Cargo.lock).

#[allow(dead_code)]
mod cfr;
mod game_node;
mod game_push_fold;

use game_node::{GameNode, PublicInfoSet};
use game_push_fold::PushFoldNode;
use std::collections::BTreeMap;
use std::env;
use std::process::exit;

const RANKS: [&str; 13] = [
    "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A",
];

/// Rust's f64::round() is round-half-away-from-zero, which is the documented
/// quantization rule.
fn quantize(x: f64, scale: f64) -> i64 {
    (x * scale).round() as i64
}

/// Canonical 169 class notation for combo (card i < card j). Card index is
/// rank*4 + suit, so i < j implies rank(i) <= rank(j); the higher rank leads.
fn hand_class(i: usize, j: usize) -> String {
    let (r_lo, r_hi) = (i / 4, j / 4);
    let (s1, s2) = (i % 4, j % 4);
    if r_lo == r_hi {
        format!("{}{}", RANKS[r_hi], RANKS[r_lo])
    } else if s1 == s2 {
        format!("{}{}s", RANKS[r_hi], RANKS[r_lo])
    } else {
        format!("{}{}o", RANKS[r_hi], RANKS[r_lo])
    }
}

fn combo_count(class: &str) -> f64 {
    if class.ends_with('s') {
        4.0
    } else if class.ends_with('o') {
        12.0
    } else {
        6.0
    }
}

#[derive(Default, Clone)]
struct Accum {
    primary_freq_sum: f64, // Σ combo frequency of the aggressive action
    primary_num_sum: f64,  // Σ conditional-EV numerator of the aggressive action
    denom_sum: f64,        // Σ reach denominator
}

/// One 169-row table: (class, primary_bps, fold_bps, primary_ev_mb, fold_ev_mb).
struct Table {
    rows: Vec<(String, i64, i64, i64, i64)>,
}

/// Aggregates combo-level frequency + conditional EV into 169 classes.
///
/// `primary_freq[k]` and `primary_num[k]`/`denom[k]` are combo-indexed. The
/// aggressive action is jam (SB) or call (BB); fold is the complement with a
/// fixed terminal EV (`fold_ev_bb`).
fn aggregate(
    primary_freq: &[f64],
    primary_num: &[f64],
    denom: &[f64],
    fold_ev_bb: f64,
) -> Table {
    let mut classes: BTreeMap<String, Accum> = BTreeMap::new();
    let mut k = 0usize;
    for i in 0..51 {
        for j in (i + 1)..52 {
            let class = hand_class(i, j);
            let acc = classes.entry(class).or_default();
            acc.primary_freq_sum += primary_freq[k];
            acc.primary_num_sum += primary_num[k];
            acc.denom_sum += denom[k];
            k += 1;
        }
    }

    let mut rows = Vec::with_capacity(169);
    for (class, acc) in &classes {
        let count = combo_count(class);
        let mean_freq = acc.primary_freq_sum / count;
        let primary_bps = quantize(mean_freq, 10_000.0).clamp(0, 10_000);
        let fold_bps = 10_000 - primary_bps;

        // Ratio-of-sums, not an average of rounded combo EVs. A zero class-level
        // reach denominator is undefined EV, not zero.
        if acc.denom_sum == 0.0 {
            eprintln!("ERROR: zero reach denominator for class {}", class);
            exit(3);
        }
        let primary_ev = acc.primary_num_sum / acc.denom_sum;
        let primary_ev_mb = quantize(primary_ev, 1_000.0);
        let fold_ev_mb = quantize(fold_ev_bb, 1_000.0);
        rows.push((class.clone(), primary_bps, fold_bps, primary_ev_mb, fold_ev_mb));
    }
    Table { rows }
}

fn root(depth: f64) -> PushFoldNode {
    PushFoldNode::new(depth)
}

/// Trains at increasing checkpoints; returns (avg_sigma, nashconv, iterations)
/// for the first checkpoint reaching the threshold, or None.
fn solve(
    depth: f64,
    checkpoints: &[usize],
    threshold: f64,
) -> Option<(std::collections::HashMap<PublicInfoSet, Vec<Vec<f64>>>, f64, usize)> {
    for &n in checkpoints {
        let (sigma, _ev, nashconv) = cfr::train(&root(depth), n, false);
        if nashconv <= threshold {
            return Some((sigma, nashconv, n));
        }
    }
    None
}

fn ones(len: usize) -> Vec<f64> {
    vec![1.0; len]
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut depth: Option<f64> = None;
    let mut checkpoints: Vec<usize> = vec![10_000, 20_000, 40_000, 80_000, 160_000];
    let mut threshold = 0.001_f64;
    let mut test_only = false;

    let mut it = args.iter().skip(1);
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--depth" => depth = it.next().and_then(|v| v.parse().ok()),
            "--checkpoints" => {
                if let Some(v) = it.next() {
                    checkpoints = v.split(',').filter_map(|s| s.parse().ok()).collect();
                }
            }
            "--threshold" => {
                if let Some(v) = it.next() {
                    threshold = v.parse().unwrap_or(threshold);
                }
            }
            "--test-only" => test_only = true,
            other => {
                eprintln!("ERROR: unknown argument {}", other);
                exit(2);
            }
        }
    }

    let depth = match depth {
        Some(d) if d >= 1.0 => d,
        _ => {
            eprintln!("ERROR: --depth <bb> (>=1) required");
            exit(2);
        }
    };

    let (sigma, nashconv, iterations) = match solve(depth, &checkpoints, threshold) {
        Some(result) => result,
        None => {
            eprintln!(
                "ERROR: depth {} did not reach NashConv <= {} within {:?}",
                depth, threshold, checkpoints
            );
            exit(4);
        }
    };

    let sb = &sigma[&Vec::<u8>::new()]; // root: [fold, jam] x 1326
    let bb = &sigma[&vec![1u8]]; // after SB jam: [fold, call] x 1326
    let combos = sb[0].len();

    // --- SB Open-Jam ---
    // D_SB(h): SB folds before BB acts, so BB reach is full (ones).
    // evaluate([0], player0, ones) = -0.5 * q * (#compatible) = -0.5 * D_SB(h).
    let sb_fold_node = root(depth).play(0);
    let n_fold_sb = sb_fold_node.evaluate(0, &ones(combos));
    let d_sb: Vec<f64> = n_fold_sb.iter().map(|v| -2.0 * v).collect();

    // N_jam(h) = value of the [1] subtree for SB, i.e. BB folds (+1) plus BB
    // calls (showdown), each weighted by BB's equilibrium reach.
    let jam_fold_node = root(depth).play(1).play(0); // [1,0] BB folds
    let jam_call_node = root(depth).play(1).play(1); // [1,1] showdown
    let n_jam_fold = jam_fold_node.evaluate(0, &bb[0]); // BB fold reach
    let n_jam_call = jam_call_node.evaluate(0, &bb[1]); // BB call reach
    let n_jam: Vec<f64> = (0..combos).map(|k| n_jam_fold[k] + n_jam_call[k]).collect();

    // Invariant: SB fold EV is exactly -0.5 bb per combo.
    for k in 0..combos {
        if d_sb[k] > 0.0 {
            let fold_ev = n_fold_sb[k] / d_sb[k];
            if (fold_ev + 0.5).abs() > 1e-9 {
                eprintln!("ERROR: SB fold EV invariant violated: {}", fold_ev);
                exit(5);
            }
        }
    }

    let open_jam = aggregate(&sb[1], &n_jam, &d_sb, -0.5);
    if open_jam.rows.len() != 169 {
        eprintln!("ERROR: open-jam produced {} classes", open_jam.rows.len());
        exit(6);
    }

    // --- BB Call-Jam (only when the BB has chips behind, i.e. depth >= 2) ---
    let call_jam = if depth >= 2.0 {
        let sb_jam_reach = &sb[1]; // SB jam reach
        let bb_fold_node = root(depth).play(1).play(0); // [1,0] BB fold, player 1
        let bb_call_node = root(depth).play(1).play(1); // [1,1] showdown, player 1
        let n_fold_bb = bb_fold_node.evaluate(1, sb_jam_reach);
        let n_call_bb = bb_call_node.evaluate(1, sb_jam_reach);
        let d_bb: Vec<f64> = n_fold_bb.iter().map(|v| -v).collect(); // fold payoff is -1

        for k in 0..combos {
            if d_bb[k] == 0.0 {
                eprintln!("ERROR: BB zero reach denominator at combo {}", k);
                exit(3);
            }
            let fold_ev = n_fold_bb[k] / d_bb[k];
            if (fold_ev + 1.0).abs() > 1e-9 {
                eprintln!("ERROR: BB fold EV invariant violated: {}", fold_ev);
                exit(5);
            }
        }

        let table = aggregate(&bb[1], &n_call_bb, &d_bb, -1.0);
        if table.rows.len() != 169 {
            eprintln!("ERROR: call-jam produced {} classes", table.rows.len());
            exit(6);
        }
        Some(table)
    } else {
        None
    };

    // --- Deterministic text output; Python assembles JSON + snapshot hash. ---
    println!("DEPTH {}", depth as i64);
    println!("ITER {}", iterations);
    println!("NASHCONV {:.17e}", nashconv);
    println!("TESTONLY {}", if test_only { 1 } else { 0 });
    println!("OPENJAM");
    for (class, primary_bps, fold_bps, primary_ev, fold_ev) in &open_jam.rows {
        // handClass allIn_bps fold_bps allIn_ev_mb fold_ev_mb
        println!("{} {} {} {} {}", class, primary_bps, fold_bps, primary_ev, fold_ev);
    }
    if let Some(table) = call_jam {
        println!("CALLJAM");
        for (class, primary_bps, fold_bps, primary_ev, fold_ev) in &table.rows {
            // handClass call_bps fold_bps call_ev_mb fold_ev_mb
            println!("{} {} {} {} {}", class, primary_bps, fold_bps, primary_ev, fold_ev);
        }
    }
    println!("END");
}
