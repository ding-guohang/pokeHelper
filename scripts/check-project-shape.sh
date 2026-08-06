#!/usr/bin/env bash
set -euo pipefail

test -f project.yml
test -f Config/Shared.xcconfig
test -f Packages/PokerCore/Package.swift
test -f Packages/StrategyContent/Package.swift
test -f Packages/TrainingDomain/Package.swift
test -f PokerCoach/App/PokerCoachApp.swift
