import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  recordAudit
} from "../audit/audit.service.js";
import {
  requirePermission
} from "../auth/auth.guard.js";
import {
  commitContactImport,
  exportContactsCsv,
  getDataQualityContext,
  inspectContactImportCsv,
  previewContactImport
} from "./data-quality.service.js";
import {
  MAX_IMPORT_CSV_CHARS
} from "./data-quality.policy.js";

const csvSchema =
  z.string()
    .min(1)
    .max(
      MAX_IMPORT_CSV_CHARS
    );

const mappingSchema =
  z.record(
    z.string()
      .min(1)
      .max(190),
    z.string()
      .min(1)
      .max(100)
  );

const countryCodeSchema =
  z.string()
    .regex(
      /^\d{1,3}$/
    )
    .default(
      "55"
    );

const previewSchema =
  z.object({
    csv:
      csvSchema,
    mapping:
      mappingSchema,
    defaultCountryCode:
      countryCodeSchema
  });

const commitSchema =
  previewSchema.extend({
    fingerprint:
      z.string()
        .regex(
          /^[a-f0-9]{64}$/
        ),
    mode:
      z.enum([
        "CREATE_ONLY",
        "CREATE_AND_UPDATE"
      ]),
    includedRowNumbers:
      z.array(
        z.number()
          .int()
          .min(2)
          .max(502)
      )
        .min(1)
        .max(500)
        .refine(
          rows =>
            new Set(
              rows
            ).size ===
            rows.length,
          {
            message:
              "Linhas selecionadas não podem se repetir."
          }
        ),
    confirmation:
      z.literal(
        "IMPORTAR CONTATOS"
      )
  });

const inspectSchema =
  z.object({
    csv:
      csvSchema
  });

const exportSchema =
  z.object({
    search:
      z.string()
        .trim()
        .max(100)
        .optional()
  });

function requestMetadata(
  request: {
    id:
      string;
    ip:
      string;
    headers:
      Record<
        string,
        string
        | string[]
        | undefined
      >;
  }
) {
  const rawUserAgent =
    request.headers[
      "user-agent"
    ];

  return {
    requestId:
      request.id,
    ipAddress:
      request.ip,
    userAgent:
      Array.isArray(
        rawUserAgent
      )
        ? rawUserAgent[
            0
          ]
        : rawUserAgent
  };
}

export async function dataQualityRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/data-quality/context",
    async request => {
      const auth =
        await requirePermission(
          request,
          "dataQuality.read"
        );

      return getDataQualityContext(
        auth.companyId
      );
    }
  );

  app.post(
    "/api/v1/data-quality/import/inspect",
    async request => {
      await requirePermission(
        request,
        "dataQuality.manage"
      );

      const input =
        inspectSchema.parse(
          request.body
        );

      return inspectContactImportCsv(
        input.csv
      );
    }
  );

  app.post(
    "/api/v1/data-quality/import/preview",
    async request => {
      const auth =
        await requirePermission(
          request,
          "dataQuality.manage"
        );

      const input =
        previewSchema.parse(
          request.body
        );

      return previewContactImport({
        companyId:
          auth.companyId,
        ...input
      });
    }
  );

  app.post(
    "/api/v1/data-quality/import/commit",
    async request => {
      const auth =
        await requirePermission(
          request,
          "dataQuality.manage"
        );

      const input =
        commitSchema.parse(
          request.body
        );

      const {
        confirmation:
          _confirmation,
        ...commitInput
      } =
        input;

      const result =
        await commitContactImport({
          companyId:
            auth.companyId,
          actorMembershipId:
            auth.membershipId,
          ...commitInput
        });

      await recordAudit({
        companyId:
          auth.companyId,
        actorMembershipId:
          auth.membershipId,
        action:
          "CONTACT_IMPORT",
        entityType:
          "CONTACT_DATA",
        metadata: {
          fingerprint:
            result.fingerprint,
          mode:
            input.mode,
          requested:
            result.requested,
          created:
            result.created,
          updated:
            result.updated,
          failed:
            result.failed
        },
        ...requestMetadata(
          request
        )
      });

      return result;
    }
  );

  app.post(
    "/api/v1/data-quality/export",
    async request => {
      const auth =
        await requirePermission(
          request,
          "dataQuality.manage"
        );

      const input =
        exportSchema.parse(
          request.body ??
          {}
        );

      const result =
        await exportContactsCsv({
          companyId:
            auth.companyId,
          search:
            input.search
        });

      await recordAudit({
        companyId:
          auth.companyId,
        actorMembershipId:
          auth.membershipId,
        action:
          "CONTACT_EXPORT",
        entityType:
          "CONTACT_DATA",
        metadata: {
          count:
            result.count,
          truncated:
            result.truncated,
          search:
            input.search ??
            null
        },
        ...requestMetadata(
          request
        )
      });

      return result;
    }
  );
}
