import assert from "node:assert/strict";
import {
  randomUUID
} from "node:crypto";
import {
  after,
  before,
  test
} from "node:test";

import type {
  FastifyInstance
} from "fastify";

import {
  buildApp
} from "../app.js";
import {
  prisma
} from "../lib/database.js";
import {
  hashPassword
} from "../lib/password.js";

const EMAIL =
  "data-quality.integration@wapp.test";

const PASSWORD =
  "IntegrationPassword!123";

const COMPANY_SLUG =
  "data-quality-integration";

let app:
  FastifyInstance;

let companyId =
  "";

async function login() {
  const response =
    await app.inject({
      method:
        "POST",
      url:
        "/api/v1/auth/login",
      payload: {
        email:
          EMAIL,
        password:
          PASSWORD,
        companySlug:
          COMPANY_SLUG
      }
    });

  assert.equal(
    response.statusCode,
    200,
    response.body
  );

  return response.json<{
    accessToken:
      string;
  }>();
}

before(async () => {
  const passwordHash =
    await hashPassword(
      PASSWORD
    );

  const company =
    await prisma.company.create({
      data: {
        name:
          "Data Quality Integration",
        slug:
          COMPANY_SLUG
      }
    });

  companyId =
    company.id;

  const user =
    await prisma.user.create({
      data: {
        name:
          "Data Quality Owner",
        email:
          EMAIL,
        passwordHash
      }
    });

  await prisma.companyMembership.create({
    data: {
      companyId:
        company.id,
      userId:
        user.id,
      role:
        "OWNER"
    }
  });

  await prisma.whatsAppConnection.create({
    data: {
      companyId:
        company.id,
      name:
        "Data Quality fixture",
      instanceName:
        `dq-${randomUUID()}`,
      provider:
        "META_CLOUD",
      status:
        "CONNECTED"
    }
  });

  app =
    await buildApp();

  await app.ready();
});

after(async () => {
  if (
    app
  ) {
    await app.close();
  }
});

test(
  "P3.6 CSV preview/commit maps CRM and pipeline without campaign opt-in",
  async () => {
    const {
      accessToken
    } =
      await login();

    const headers = {
      authorization:
        `Bearer ${accessToken}`
    };

    const fieldResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/contact-crm/fields",
        headers,
        payload: {
          label:
            "Origem importação",
          type:
            "TEXT",
          required:
            false
        }
      });

    assert.equal(
      fieldResponse.statusCode,
      201,
      fieldResponse.body
    );

    const field =
      fieldResponse.json<{
        field: {
          id:
            string;
        };
      }>().field;

    const pipelineResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/pipelines",
        headers,
        payload: {
          name:
            "Pipeline importação",
          stages: [
            "Novo",
            "Qualificado"
          ]
        }
      });

    assert.equal(
      pipelineResponse.statusCode,
      201,
      pipelineResponse.body
    );

    const pipeline =
      pipelineResponse.json<{
        pipeline: {
          id:
            string;
          stages:
            Array<{
              id:
                string;
            }>;
        };
      }>().pipeline;

    const csv =
      "nome;telefone;email;origem;etapa\n" +
      "Contato Importado;11988887777;importado@example.com;CSV;Qualificado\n";

    const mapping = {
      nome:
        "name",
      telefone:
        "phone",
      email:
        "email",
      origem:
        `custom:${field.id}`,
      etapa:
        `pipeline:${pipeline.id}`
    };

    const previewResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/data-quality/import/preview",
        headers,
        payload: {
          csv,
          mapping,
          defaultCountryCode:
            "55"
        }
      });

    assert.equal(
      previewResponse.statusCode,
      200,
      previewResponse.body
    );

    const preview =
      previewResponse.json<{
        fingerprint:
          string;
        summary: {
          create:
            number;
          update:
            number;
          conflict:
            number;
          invalid:
            number;
        };
        rows:
          Array<{
            rowNumber:
              number;
            status:
              string;
          }>;
      }>();

    assert.equal(
      preview.summary.create,
      1
    );

    assert.equal(
      preview.summary.update,
      0
    );

    assert.equal(
      preview.summary.conflict,
      0
    );

    assert.equal(
      preview.summary.invalid,
      0
    );

    const rowNumber =
      preview.rows[
        0
      ]!.rowNumber;

    const commitResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/data-quality/import/commit",
        headers,
        payload: {
          csv,
          mapping,
          defaultCountryCode:
            "55",
          fingerprint:
            preview.fingerprint,
          mode:
            "CREATE_AND_UPDATE",
          includedRowNumbers: [
            rowNumber
          ],
          confirmation:
            "IMPORTAR CONTATOS"
        }
      });

    assert.equal(
      commitResponse.statusCode,
      200,
      commitResponse.body
    );

    const commit =
      commitResponse.json<{
        created:
          number;
        updated:
          number;
        failed:
          number;
      }>();

    assert.equal(
      commit.created,
      1
    );

    assert.equal(
      commit.updated,
      0
    );

    assert.equal(
      commit.failed,
      0
    );

    const contact =
      await prisma.contact.findUniqueOrThrow({
        where: {
          companyId_remoteJid: {
            companyId,
            remoteJid:
              "5511988887777@s.whatsapp.net"
          }
        },
        include: {
          campaignConsent:
            true,
          customFieldValues:
            true,
          pipelineStates:
            true
        }
      });

    assert.equal(
      contact.name,
      "Contato Importado"
    );

    assert.equal(
      contact.campaignConsent,
      null,
      "CSV import must never create campaign consent."
    );

    assert.equal(
      contact.customFieldValues[
        0
      ]?.value,
      "CSV"
    );

    assert.equal(
      contact.pipelineStates[
        0
      ]?.stageId,
      pipeline.stages[
        1
      ]?.id
    );

    const previewAgain =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/data-quality/import/preview",
        headers,
        payload: {
          csv,
          mapping,
          defaultCountryCode:
            "55"
        }
      });

    assert.equal(
      previewAgain.statusCode,
      200,
      previewAgain.body
    );

    assert.equal(
      previewAgain.json<{
        summary: {
          update:
            number;
        };
      }>().summary.update,
      1
    );

    await prisma.contact.create({
      data: {
        companyId,
        remoteJid:
          "5511977776666@s.whatsapp.net",
        phoneNumber:
          "5511977776666",
        name:
          "=SUM(1,1)"
      }
    });

    const exportResponse =
      await app.inject({
        method:
          "POST",
        url:
          "/api/v1/data-quality/export",
        headers,
        payload: {}
      });

    assert.equal(
      exportResponse.statusCode,
      200,
      exportResponse.body
    );

    const exported =
      exportResponse.json<{
        csv:
          string;
      }>().csv;

    assert.match(
      exported,
      /custom:origem_importacao/
    );

    assert.match(
      exported,
      /pipeline:Pipeline importação/
    );

    assert.match(
      exported,
      /'=SUM\(1,1\)/
    );
  }
);
