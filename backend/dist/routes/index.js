"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const dotenv_1 = __importDefault(require("dotenv"));
const mysql = require('mysql2');

dotenv_1.default.config();  // Carrega variáveis de ambiente do .env

// Função para criar nova conexão
const createConnection = () => {
  return mysql.createConnection({
    host: process.env.DB_HOST,        // Usando a variável DB_HOST do .env
    user: process.env.DB_USER,        // Usando a variável DB_USER do .env
    password: process.env.DB_PASS,    // Usando a variável DB_PASSWORD do .env
    database: process.env.DB_NAME,    // Usando a variável DB_NAME do .env
    charset: process.env.DB_CHARSET   // Usando a variável DB_CHARSET do .env
  });
};

// Conexão inicial
let connection = createConnection();

// Verificar se a conexão foi bem-sucedida
const connectToDB = () => {
  connection.connect((err) => {
    if (err) {
      console.error('Erro ao conectar com o banco de dados:', err);
    } else {
      console.log('Conectado ao banco de dados com sucesso!');
    }
  });
};

// Função para garantir que a conexão esteja aberta
const checkConnection = (callback) => {
  if (connection.state === 'disconnected') {
    console.log('Reconectando ao banco de dados...');
    // Fecha a conexão atual e cria uma nova
    connection.end(); // Fecha a conexão existente
    connection = createConnection(); // Cria uma nova conexão
    connectToDB(); // Reconnect
    callback();
  } else {
    callback();
  }
};

const userRoutes_1 = __importDefault(require("./userRoutes"));
const authRoutes_1 = __importDefault(require("./authRoutes"));
const settingRoutes_1 = __importDefault(require("./settingRoutes"));
const contactRoutes_1 = __importDefault(require("./contactRoutes"));
const ticketRoutes_1 = __importDefault(require("./ticketRoutes"));
const whatsappRoutes_1 = __importDefault(require("./whatsappRoutes"));
const messageRoutes_1 = __importDefault(require("./messageRoutes"));
const whatsappSessionRoutes_1 = __importDefault(require("./whatsappSessionRoutes"));
const queueRoutes_1 = __importDefault(require("./queueRoutes"));
const quickAnswerRoutes_1 = __importDefault(require("./quickAnswerRoutes"));
const apiRoutes_1 = __importDefault(require("./apiRoutes"));

const routes = express_1.Router();

routes.use(userRoutes_1.default);
routes.use("/auth", authRoutes_1.default);
routes.use(settingRoutes_1.default);
routes.use(contactRoutes_1.default);
routes.use(ticketRoutes_1.default);
routes.use(whatsappRoutes_1.default);
routes.use(messageRoutes_1.default);
routes.use(whatsappSessionRoutes_1.default);
routes.use(queueRoutes_1.default);
routes.use(quickAnswerRoutes_1.default);
// routes.use("/bulkMessage", bulkMessageRoutes_1.default);
routes.use("/api/messages", apiRoutes_1.default);

// Rota para enviar mensagem e salvar no banco
routes.get("/api/playsms/index.php", (req, res) => {
  const { to, msg, p } = req.query;

  // Recupera o p esperado no arquivo .env
  const tkDisparos = process.env.TK_DISPAROS;

  // Validação do p
  if (!p) {
    return res.json({ error: "p não informado" });
  }

  if (p !== tkDisparos) {
    return res.json({ error: "p inválido" });
  }

  // Verificar se os parâmetros 'to' e 'msg' foram fornecidos
  if (!to || !msg) {
    return res.json({
      error: "Parâmetros 'to' e 'msg' são obrigatórios."
    });
  }

  // Verifica a conexão antes de realizar a consulta
  checkConnection(() => {
    const query = "INSERT INTO Disparos (number, msg) VALUES (?, ?)";
    connection.execute(query, [to, msg], (err, results) => {
      if (err) {
        console.error('Erro ao salvar dados no banco:', err.code, err.sqlMessage); // Logar o erro detalhado
        return res.json({ error: `Erro ao salvar os dados no banco: ${err.message}` });
      }

      res.json({ success: "Mensagem enviada com sucesso" });
    });
  });
});

routes.get("/send", (req, res) => {
  const { to, msg, token } = req.query;

  // Recupera o p esperado no arquivo .env
  const tkDisparos = process.env.TK_DISPAROS;

  // Validação do p
  if (!tkDisparos) {
    return res.json({ error: "p não informado" });
  }

  // Verificar se os parâmetros 'to' e 'msg' foram fornecidos
  if (!to || !msg) {
    return res.json({
      error: "Parâmetros 'to' e 'msg' são obrigatórios."
    });
  }

  // Verifica a conexão antes de realizar a consulta
  checkConnection(() => {
    // Caso o p seja válido e os parâmetros estejam presentes, salvar no banco de dados
    const query = "INSERT INTO Disparos (number, msg) VALUES (?, ?)";
    connection.execute(query, [to, msg], (err, results) => {
      if (err) {
        console.error('Erro ao salvar dados no banco:', err);
        return res.json({ error: 'Erro ao salvar os dados no banco' });
      }

      // Se a inserção for bem-sucedida, retorna uma resposta de sucesso
      res.json({ success: "Mensagem enviada com sucesso" });
    });
  });
});

exports.default = routes;
