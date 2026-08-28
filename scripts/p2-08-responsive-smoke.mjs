import fs from "node:fs";

const page =
  fs.readFileSync(
    "apps/web/app/dashboard/conversations/page.tsx",
    "utf8"
  );

const css =
  fs.readFileSync(
    "apps/web/app/globals.css",
    "utf8"
  );

const requiredPageMarkers = [
  "inbox-screen--conversation-open",
  "inbox--conversation-open",
  'className="conversation-body"',
  'className="conversation-scroll"',
  'className="conversation-composer'
];

const requiredCssMarkers = [
  "WAPP P2.8 / RESPONSIVE PRODUCT PASS",
  "@media (max-width: 760px)",
  ".inbox--conversation-open .ticket-list",
  ".inbox--conversation-open .conversation-panel",
  ".conversation-composer",
  "100dvh",
  "safe-area-inset-bottom",
  ".sidebar",
  ".notification-center__panel"
];

for (
  const marker
  of requiredPageMarkers
) {
  if (
    !page.includes(
      marker
    )
  ) {
    throw new Error(
      `P2.8 page marker missing: ${marker}`
    );
  }
}

for (
  const marker
  of requiredCssMarkers
) {
  if (
    !css.includes(
      marker
    )
  ) {
    throw new Error(
      `P2.8 CSS marker missing: ${marker}`
    );
  }
}

const scrollIndex =
  page.indexOf(
    'className="conversation-scroll"'
  );

const composerIndex =
  page.indexOf(
    'className="conversation-composer'
  );

if (
  scrollIndex <
    0 ||
  composerIndex <
    0 ||
  composerIndex <
    scrollIndex
) {
  throw new Error(
    "Canonical conversation scroll/composer ordering changed."
  );
}

console.log(
  "[P2.8] responsive smoke PASS"
);
