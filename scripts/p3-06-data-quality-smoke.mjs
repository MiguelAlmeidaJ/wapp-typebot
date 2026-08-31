import fs from "node:fs";

const app =
  fs.readFileSync(
    "apps/api/src/app.ts",
    "utf8"
  );

const policy =
  fs.readFileSync(
    "apps/api/src/modules/data-quality/data-quality.policy.ts",
    "utf8"
  );

const service =
  fs.readFileSync(
    "apps/api/src/modules/data-quality/data-quality.service.ts",
    "utf8"
  );

const routes =
  fs.readFileSync(
    "apps/api/src/modules/data-quality/data-quality.routes.ts",
    "utf8"
  );

const web =
  fs.readFileSync(
    "apps/web/app/dashboard/data-quality/page.tsx",
    "utf8"
  );

const permissions =
  fs.readFileSync(
    "apps/api/src/security/permissions.ts",
    "utf8"
  );

for (
  const marker
  of [
    "await app.register(dataQualityRoutes);",
    "normalizeImportPhone",
    "IMPORT_PREVIEW_CHANGED",
    "contactCampaignConsent",
    "safeSpreadsheetCell",
    "/api/v1/data-quality/import/preview",
    "IMPORTAR CONTATOS",
    '"dataQuality.manage"'
  ]
) {
  const source =
    marker.includes(
      "app.register"
    )
      ? app
      : marker ===
          "normalizeImportPhone" ||
        marker ===
          "safeSpreadsheetCell"
        ? policy
        : marker ===
            "IMPORT_PREVIEW_CHANGED" ||
          marker ===
            "contactCampaignConsent"
          ? service
          : marker.startsWith(
              "/api/"
            )
            ? routes
            : marker ===
                "IMPORTAR CONTATOS"
              ? web
              : permissions;

  if (
    !source.includes(
      marker
    )
  ) {
    throw new Error(
      `P3.6 marker missing: ${marker}`
    );
  }
}

if (
  /contactCampaignConsent\.(create|update|upsert)/.test(
    service
  ) ||
  service.includes(
    '"OPTED_IN"'
  )
) {
  throw new Error(
    "P3.6 service appears to mutate campaign consent."
  );
}

console.log(
  "[P3.6] data-quality smoke PASS"
);
