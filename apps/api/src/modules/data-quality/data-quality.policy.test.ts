import assert from "node:assert/strict";
import {
  test
} from "node:test";

import {
  csvCell,
  normalizeImportPhone,
  parseCsv,
  parseImportTarget,
  planFingerprint,
  safeSpreadsheetCell
} from "./data-quality.policy.js";

test(
  "CSV parser supports semicolon and escaped quotes",
  () => {
    const parsed =
      parseCsv(
        'nome;telefone;observacao\n"Maria ""M""";11999998888;"Linha 1"\n'
      );

    assert.equal(
      parsed.delimiter,
      ";"
    );

    assert.equal(
      parsed.rows[
        0
      ]?.source.nome,
      'Maria "M"'
    );
  }
);

test(
  "Brazilian local phone becomes canonical WhatsApp jid",
  () => {
    const normalized =
      normalizeImportPhone({
        value:
          "(11) 99999-8888",
        defaultCountryCode:
          "55"
      });

    assert.deepEqual(
      normalized,
      {
        phoneNumber:
          "5511999998888",
        remoteJid:
          "5511999998888@s.whatsapp.net"
      }
    );
  }
);

test(
  "explicit international number is not prefixed again",
  () => {
    const normalized =
      normalizeImportPhone({
        value:
          "+1 415 555 2671",
        defaultCountryCode:
          "55"
      });

    assert.equal(
      "phoneNumber" in
        normalized
        ? normalized.phoneNumber
        : null,
      "14155552671"
    );
  }
);

test(
  "import targets do not expose campaign consent",
  () => {
    assert.equal(
      parseImportTarget(
        "campaignConsent"
      ),
      null
    );

    assert.equal(
      parseImportTarget(
        "custom:00000000-0000-0000-0000-000000000001"
      ),
      "custom:00000000-0000-0000-0000-000000000001"
    );
  }
);

test(
  "spreadsheet formula cells are escaped",
  () => {
    assert.equal(
      safeSpreadsheetCell(
        "=2+2"
      ),
      "'=2+2"
    );

    assert.equal(
      csvCell(
        'Empresa; "A"'
      ),
      '"Empresa; ""A"""'
    );
  }
);

test(
  "preview fingerprint is deterministic",
  () => {
    assert.equal(
      planFingerprint({
        rows: [
          1,
          2
        ]
      }),
      planFingerprint({
        rows: [
          1,
          2
        ]
      })
    );
  }
);
