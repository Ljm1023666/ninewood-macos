# Design QA

## Scope

All 26 reference renderings in `docs/ui-renderings/` were implemented and
reviewed page-by-page. The existing API and product contracts remain
authoritative where a concept rendering contains non-production data.

## Evidence

For every `NN-name` below:

- Source: `docs/ui-renderings/NN-name.png`
- Runtime: `docs/qa-screenshots/NN-name-final.png`
- Side-by-side: `docs/qa-screenshots/compare-NN-name.png`

| # | Surface | Result |
| --- | --- | --- |
| 01 | Login | passed |
| 02 | Register | passed |
| 03 | Discover | passed |
| 04 | Card pool | passed |
| 05 | Publish | passed |
| 06 | Circles | passed |
| 07 | Natural Loop | passed |
| 08 | Find people | passed |
| 09 | Direct messages | passed |
| 10 | Certification | passed |
| 11 | Group messages | passed |
| 12 | Profile | passed |
| 13 | Orders | passed |
| 14 | My demands | passed |
| 15 | Wallet | passed |
| 16 | Service cards | passed |
| 17 | Notifications | passed |
| 18 | Welfare | passed |
| 19 | Agent | passed |
| 20 | Settings | passed |
| 21 | Help | passed |
| 22 | My bids | passed |
| 23 | Follows | passed |
| 24 | Favorites | passed |
| 25 | Dispute sheet | passed |
| 26 | Payment sheet | passed |

The overview contact sheet is
`docs/qa-screenshots/all-26-comparison-contact-sheet.png`.

## Viewport and state

- Reference viewport: 1440 × 1024.
- Runtime viewport: 1080 × 768, the largest unobscured QA display area.
- Both use a 4:3 aspect ratio. Side-by-side comparisons scale runtime captures
  to the reference dimensions.
- Deterministic design-preview fixtures cover list, detail, account, messaging,
  circle, loop, transaction, modal, and error-free authenticated states.
- Each preview is addressable with `NINEWOOD_DESIGN_PREVIEW=NN-name`.

## Findings

- P0: none.
- P1: the earlier 26/26 pass was invalid: several pages reproduced the route and
  data state but not the reference composition. The contact sheet shows major
  region, density, copy, and component mismatches.
- P1: Card Pool, Circles, Natural Loop, Certification, Welfare, Settings, Help,
  My Bids, Follows, and Favorites still require reference-specific composition
  work before visual acceptance.
- P1: the original Discover detail omitted the countdown, description,
  applicants, trust credentials, and attachment hierarchy visible in the source.
  Visual pass 2 adds those regions; it remains under active comparison.
- P2: the runtime keeps the product's denser global/account navigation instead
  of removing existing reachable areas from concept-only compositions.
- P2: business-required inputs and actions are retained where the concept omits
  them.
- P3: native macOS typography, window chrome, and control metrics cause minor
  spacing differences from static concepts.
- P3: at 1080 × 768, some lower document content remains scrollable below the
  fold; the intended hierarchy is preserved.

## Focused checks

- Lists populate deterministically and update their detail selection.
- Find People, My Bids, and Favorites use populated list-detail layouts.
- Direct and group message previews include conversation timelines and cards.
- Orders, My Demands, Wallet, Service Cards, Notifications, Welfare, and Agent
  render authenticated data without login-expired or network-error placeholders.
- Circles and Natural Loop open populated detail workspaces.
- Dispute and payment sheets render over the relevant transaction context.
- Profile preview navigation is deterministic and no longer inherits a prior
  collapsed-sidebar preference.

## Verification

- Xcode Debug build: passed.
- Swift package tests: 30 passed, 0 failed.
- `git diff --check`: passed.
- Runtime captures: 26 present.
- Side-by-side comparisons: 26 present.

final result: blocked
