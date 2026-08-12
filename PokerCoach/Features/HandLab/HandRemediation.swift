/// Turns a reviewed key node into the training scenario that would drill it, if
/// any.
///
/// Remediation only follows a *covered deviation*: the departure was measured
/// against a real range table, so there is a scenario to practise the same spot
/// against. An all-in carries no covering scenario — an uncovered commitment has
/// nothing authored to train against — so it offers no remediation, and neither
/// does a deviation that somehow lost its covering ID.
///
/// This is the whole bridge. It computes an identifier and nothing else: it
/// starts no session, grades nothing, and never reaches an event store. The
/// remediation drill it points at is the ordinary training flow reached through
/// `AppDependencies.makeDecisionSessionViewModel(scenarioID:)`, so a remediation
/// event is a plain training event — indistinguishable, by construction, from
/// one produced by starting the same scenario directly.
func remediationScenarioID(for node: KeyNode) -> String? {
    guard node.reason == .deviation else {
        return nil
    }
    return node.coveringScenarioID
}
