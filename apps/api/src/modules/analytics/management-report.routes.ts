import type {
  FastifyInstance
} from "fastify";
import {
  z
} from "zod";

import {
  AppError
} from "../../errors/app-error.js";
import {
  requirePermission
} from "../auth/auth.guard.js";
import {
  getManagementReport
} from "./management-report.service.js";

const querySchema =
  z.object({
    days:
      z.coerce
        .number()
        .int()
        .refine(
          (
            value
          ): value is
            | 7
            | 30
            | 90 =>
            [
              7,
              30,
              90
            ].includes(
              value
            ),
          {
            message:
              "days deve ser 7, 30 ou 90."
          }
        )
        .default(
          30
        ),
    queueId:
      z.string()
        .uuid()
        .optional()
  });

export async function managementReportRoutes(
  app:
    FastifyInstance
) {
  app.get(
    "/api/v1/reports/management",
    async request => {
      const auth =
        await requirePermission(
          request,
          "reports.read"
        );

      const query =
        querySchema.parse(
          request.query
        );

      try {
        return await getManagementReport({
          companyId:
            auth.companyId,
          days:
            query.days,
          queueId:
            query.queueId
        });
      } catch (error) {
        if (
          error instanceof
            Error &&
          error.message ===
            "REPORT_QUEUE_NOT_FOUND"
        ) {
          throw new AppError(
            "Fila não encontrada para este relatório.",
            404,
            "REPORT_QUEUE_NOT_FOUND"
          );
        }

        throw error;
      }
    }
  );
}
