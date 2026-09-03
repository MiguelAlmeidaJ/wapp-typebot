# Wapp Visual QA

RH1–RH6 validate code, security and release readiness. Visual QA validates the
actual interface.

## VQ1 — Responsive baseline

Run the real Wapp interface in Chromium and capture:

- 1440×1000 desktop;
- 1280×800 laptop;
- 834×1112 tablet;
- 390×844 mobile;
- 360×800 small mobile.

The route list is discovered from the Next.js App Router.

Automated checks cover:

- horizontal overflow;
- page/runtime errors;
- HTTP 5xx responses;
- protected routes redirecting back to login;
- visually empty pages;
- mobile touch targets below 40px;
- the canonical `.conversation-composer` fitting inside the viewport.

Output is stored under:

```text
.runtime/visual-qa/<timestamp>/
```

with `report.md`, `report.json` and screenshots by viewport.

Use a dedicated QA account containing representative data.

Run:

```bash
pnpm visual:qa
```

The password is entered with terminal echo disabled.

Package the latest result with:

```bash
pnpm visual:qa:pack
```

## VQ2 — Manual aesthetic review

Mechanical PASS is not design approval.

Screenshots must still be reviewed for hierarchy, typography, spacing, density,
alignment, color/contrast, empty/loading/error states, tables/cards, navigation,
inbox usability and mobile adaptation.

## VQ3 — Corrections

Visual issues are fixed by UI surface in small patches. Avoid one global CSS
override that can regress unrelated screens.

The canonical conversation layout remains:

```text
.inbox-screen--contained
.conversation-panel
.conversation-body
.conversation-scroll
.conversation-composer
```

## VQ4 — Final regression

After all screenshots are approved, rerun VQ1 on the clean release candidate at
all five viewport sizes.
