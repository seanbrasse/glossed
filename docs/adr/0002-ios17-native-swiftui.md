# 0002. iOS 17 floor, SwiftUI, feature modules

Date: 2026-08-27 | Status: accepted

## Context
PRD decides iOS-only with native frameworks load-bearing: on-device background removal, Share Extension ingest, Sensitive Content Analysis (Phase 2). Handbook wants compiler-enforced layering.

## Options
1. iOS 17 floor — `VNGenerateForegroundInstanceMaskRequest` (any-subject cutouts) and SensitiveContentAnalysis both require 17; ~95%+ of the Gen-Z target is on 17+ by late 2026.
2. iOS 15/16 floor — person-only segmentation, no SCA; cutouts (the visual identity) degrade badly.
3. Cross-platform (RN/Flutter) — rejected in PRD; native APIs are the point.

## Decision
Swift 6 strict concurrency, SwiftUI, **iOS 17.0 minimum**, one local SPM package per feature slice, `DataKit` as the frozen data-access core, `DesignSystem` standalone.

## Consequences
Easy: cutouts + SCA on every supported device; SPM graph enforces "features never import features." Hard: no simulator for Vision mask requests (test on device); anything below iOS 17 is out of reach. Revisit if: adoption data from the pilot shows a meaningful 16.x cohort (unlikely).
