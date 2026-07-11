---
target: critique of the ExTauri showcase website
total_score: 30
p0_count: 0
p1_count: 2
timestamp: 2026-07-11T22-36-09Z
slug: website-priv-templates-index-html-eex
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Copy button confirms; nav has no scroll-spy active state |
| 2 | Match System / Real World | 4 | Benefit-led, audience-appropriate language |
| 3 | User Control and Freedom | 3 | Anchor nav + back work; n/a for a static page |
| 4 | Consistency and Standards | 3 | Two competing accents; eyebrow label repeated on every section |
| 5 | Error Prevention | 3 | Nothing to get wrong; clipboard copy can fail silently |
| 6 | Recognition Rather Than Recall | 4 | Text nav labels, labeled tabs, no icon-only traps |
| 7 | Flexibility and Efficiency | 3 | Anchor nav + copy; no skip link |
| 8 | Aesthetic and Minimalist Design | 2 | Decorative glows, gradient text, repeated eyebrows, competing accents |
| 9 | Error Recovery | 2 | Clipboard rejection produces no visible state |
| 10 | Help and Documentation | 3 | Links to guides, prereqs, demos |
| **Total** | | **30/40** | **Good** |

## Anti-Patterns Verdict

**LLM assessment: yes, it reads AI-generated.** Not because the craft is bad (it isn't), but because it lands squarely on the dev-tool training reflex: dark canvas + Phoenix-violet + amber, gradient headline text, a purple glow under the primary button, a six-up identical feature-card grid with rounded-corner icons, and a tiny uppercase tracked kicker above every section. First-order category reflex (Elixir/Phoenix tool -> dark + purple) is not avoided. Second-order (violet gradient hero with glow) is not avoided either.

The sharper tell: the author's sibling project **codrift** ships a committed, opinionated DESIGN.md (one monospace voice, one restrained amber accent capped at ~10%, flat surfaces, explicit bans on gradient text, glows, and gradient accents). This site does the opposite of the author's own established design language. It reads as a different, more generic hand.

**Deterministic scan: unavailable.** `detect.mjs` reported "bundled detector not found" and exited non-zero after a real attempt, so no automated overlay ran. Findings below are from source read + live browser inspection.

**Confirmed shared-law violations:**
- **Gradient text (banned):** `bg-clip-text text-transparent` on "Phoenix & Elixir" (hero) and "on the desktop" (final CTA). Live, the mid-gradient "&" and the tan letters wash out to low contrast.
- **Side-stripe border (banned):** the Desktop-APIs callout uses `border-l-[3px] border-grape-deep ... rounded-r-xl`, the exact colored left-stripe pattern.
- **Identical card grid + rounded-icon-above-heading (banned):** six same-size feature cards, each an icon-in-a-rounded-box over heading over text.
- **Repeated tiny uppercase tracked labels (brand ban):** FEATURES / GET STARTED / DESKTOP APIS / ARCHITECTURE / SHIP IT as section grammar.
- **Decorative glows:** purple glow on the logo mark and under the primary button; codrift explicitly rejects glows.

**Browser evidence:** the nav-over-CTA overlap visible in a full-page screenshot is a capture artifact of `position: sticky`, not a real bug (at scrollY 0: h1 top 161px, primary CTA top 403px, nav bottom 65px, no collision). Console is clean. Mobile (390px) reflows correctly.

## Overall Impression

Competent, honest, and well-structured, held back by decorative slop and a mismatch with the author's own design voice. The narrative arc (hero -> features -> get started -> APIs -> architecture -> ship -> CTA) is logical, the copy is tight, and the tabbed code examples are genuinely strong. But the visual language is the generic "dark purple dev-tool launch page," and the hero image (a VS Code terminal running `mix tauri dev`) never shows the actual payoff: a Phoenix LiveView UI rendered inside a native window. The single biggest opportunity is to adopt codrift's committed design language (or a deliberate sibling of it) and show the real product in the hero.

## What's Working

- **The Desktop-APIs tab section.** Real, idiomatic Elixir, showing the callback pattern that is the library's actual selling point. This is the most persuasive block on the page and the least templated.
- **Information architecture and copy.** "Keep writing Phoenix. Ship a desktop app." is a strong, honest promise; the three-step Get Started is concrete; the architecture diagram is hand-built, not a stock card.
- **Craft details.** A custom tiny syntax highlighter, OS-assigned-port explanation, and prereq links show real care.

## Priority Issues

**[P1] The page contradicts the author's own design system.** codrift commits to one monospace voice + one restrained amber accent and bans exactly the gradient text, glows, and gradient accents this page leans on. The two properties should read as one brand; today they read as two hands.
- *Why it matters:* an evaluating Elixir dev sees the generic version first and discounts the project before reading the (strong) technical content.
- *Fix:* pick one committed voice. Kill the gradient text (solid amber or solid violet, emphasis via weight/size), drop the glows, and unify accents so violet OR amber leads instead of both competing.
- *Suggested command:* `/impeccable bolder` (commit to a real voice) then `/impeccable colorize` (resolve the two-accent conflict).

**[P1] The hero image doesn't show the product.** The GIF is a terminal running the dev command, not a Phoenix UI inside a native window, which is the entire promise.
- *Why it matters:* the payoff is unshown; skeptics get no proof.
- *Fix:* replace with a real screenshot/GIF of a LiveView app rendered in a native desktop window, ideally with a desktop API (notification/dialog/tray) firing.
- *Suggested command:* content swap, then `/impeccable polish`.

**[P2] Gradient text + side-stripe callout + identical card grid.** Three shared-law bans in one page.
- *Why it matters:* these are the exact tells that make the AI-generated read instant.
- *Fix:* solid-color headline; rewrite the callout with a full border or background tint and a leading icon (no left stripe); differentiate the feature cards by weight/size/span or drop the icon-box scaffolding.
- *Suggested command:* `/impeccable distill`.

**[P2] Repeated eyebrow kickers as section grammar.** Five uppercase amber tracked labels above five headings is AI scaffolding.
- *Why it matters:* it signals template, and it dilutes the amber accent so it stops meaning anything (codrift's "quiet accent" rule).
- *Fix:* keep at most one kicker (the hero or a single anchor section); let the h2 carry the rest.
- *Suggested command:* `/impeccable typeset`.

**[P2] Accessibility gaps.** The tab widget has `role="tablist"` on the container but the buttons lack `role="tab"` / `aria-selected` / `aria-controls`, panels lack `role="tabpanel"`, and there's no arrow-key roving focus. `text-faint` (#6f6885) on `#0b0a10` is borderline for small body text. No skip-to-content link. Clipboard-copy failure is silent.
- *Why it matters:* keyboard and screen-reader users get a broken tab pattern and low-contrast captions.
- *Fix:* complete the ARIA tab pattern + roving tabindex; lift faint text one step; add a skip link; add a failure toast on copy.
- *Suggested command:* `/impeccable audit` then `/impeccable harden`.

## Persona Red Flags

**Priya (senior Elixir dev, evaluating seriously):** Pattern-matches the violet-gradient-glow hero as "another AI launch page" and trust dips before the content. Scrolls for proof and finds a terminal GIF, not the actual native window with a Phoenix UI. The strongest asset (the API code tabs) is below the fold; she may bounce before reaching it.

**Jordan (curious, not an Elixir expert):** Hits "sidecar," "Burrito-wrapped," "BEAM," "heartbeat over a local socket" with no one-line "why you care," and no picture of the end result. The concepts are real but unillustrated; likely bounce at the Architecture section.

## Minor Observations

- Two decorative accent colors (grape + amber) with no clear division of labor; pick lead vs support.
- Display type is bold `system-ui` with no personality; the one distinctive typographic moment (the headline) is spent on banned gradient text.
- Nav lacks an active/scroll-spy state, so location within the long page is invisible.
- Colors are defined as hex, not OKLCH; migrating would make tinting and accent-alpha steps easier to reason about.
- No PRODUCT.md/DESIGN.md for the website; the sibling `ex_tauri/` has PRODUCT.md and codrift has a full DESIGN.md to borrow from.

## Questions to Consider

- What would this look like if it shared codrift's voice instead of the generic dev-tool one?
- The API code tabs are your best asset. What if they moved up, closer to the hero?
- What is the one image that proves the promise, and why isn't it the hero?
- Does the page need two accent colors, or is one more confident?
