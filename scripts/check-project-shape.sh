#!/usr/bin/env bash
set -euo pipefail

test -f project.yml
test -f Config/Shared.xcconfig
test -f Packages/PokerCore/Package.swift
test -f Packages/StrategyContent/Package.swift
test -f Packages/TrainingDomain/Package.swift
test -f PokerCoach/App/PokerCoachApp.swift
grep -Fqx 'SWIFT_TREAT_WARNINGS_AS_ERRORS = YES' Config/Shared.xcconfig
test "$(grep -Fc -- '-warnings-as-errors' Packages/PokerCore/Package.swift)" -eq 2
test "$(grep -Fc -- '-warnings-as-errors' Packages/StrategyContent/Package.swift)" -eq 2
test "$(grep -Fc -- '-warnings-as-errors' Packages/TrainingDomain/Package.swift)" -eq 2
