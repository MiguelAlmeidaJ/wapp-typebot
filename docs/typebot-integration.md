# Integração Typebot

O Typebot roda fora do Wapp. A API do Wapp mantém o fluxo e a sessão, chama o
Typebot e envia todas as respostas ao WhatsApp pela Evolution.

## Configuração

```env
TYPEBOT_ENABLED=true
TYPEBOT_API_URL=https://typebot.example.com/api
TYPEBOT_API_TOKEN=replace-with-a-typebot-api-token
TYPEBOT_WEBHOOK_SECRET=replace-with-at-least-32-random-characters
TYPEBOT_REQUEST_TIMEOUT_MS=15000
```

`TYPEBOT_API_URL` inclui o prefixo `/api`; o client acrescenta `/v1`.
Credenciais ficam somente na API do Wapp.

Depois de configurar o ambiente, aplique a migration:

```bash
pnpm db:migrate
```

## Criar um fluxo

Com um token de acesso Wapp de OWNER, ADMIN ou SUPERVISOR:

```http
POST /api/v1/chatbots
Authorization: Bearer <wapp-access-token>
Content-Type: application/json

{
  "name": "Atendimento inicial",
  "whatsappConnectionId": "<uuid-da-conexao>",
  "externalId": "<public-id-do-typebot>",
  "isActive": true
}
```

Só pode existir um fluxo ativo por conexão. `GET /api/v1/chatbots` lista os
fluxos e `PATCH /api/v1/chatbots/:id` altera ou desativa um fluxo.

O Wapp envia estas variáveis ao iniciar o Typebot:

- `nome`
- `telefone`
- `ticketId`
- `companyId`
- `chatbotSessionId`

Respostas numéricas a escolhas (`1`, `2`, ...) são convertidas ao valor do
botão antes do `continueChat`.

## Transferir para uma fila

No bloco HTTP do Typebot, configure:

```http
POST https://api.wapp.example/internal/chatbot/action
Content-Type: application/json
X-Wapp-Chatbot-Secret: <TYPEBOT_WEBHOOK_SECRET>

{
  "ticketId": "{{ticketId}}",
  "chatbotSessionId": "{{chatbotSessionId}}",
  "action": "TRANSFER_QUEUE",
  "queue": "suporte"
}
```

Guarde o segredo como credencial no Typebot; não o coloque em uma variável do
fluxo. O slug é retornado pelas rotas de filas do Wapp. A API valida a sessão,
o ticket e a fila na mesma empresa antes de encerrar o bot e transferir o
atendimento.

Quando uma pessoa assume ou encerra o ticket, a sessão de chatbot é finalizada
e respostas posteriores do bot deixam de ser enviadas.

## Convivência com automações

O Typebot processa a mensagem antes de as avaliações de automação serem
agendadas. O job recebe a informação de que a mensagem pertenceu ao chatbot e
aplica esta política:

- `ADD_TAG`: executa normalmente;
- `SET_QUEUE`: executa normalmente;
- `ASSIGN_MEMBERSHIP`: executa e encerra a sessão do chatbot;
- `SEND_TEXT`: é registrado como ignorado para não duplicar a resposta do bot.

Jobs antigos, sem esse contexto, também bloqueiam `SEND_TEXT` quando encontram
uma sessão de chatbot ativa no ticket.
