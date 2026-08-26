-- MySQL dump 10.13  Distrib 8.0.43, for Linux (x86_64)
--
-- Host: localhost    Database: dct
-- ------------------------------------------------------
-- Server version	8.0.43-0ubuntu0.24.04.1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `dct`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `dct` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `dct`;

--
-- Table structure for table `Ajustes`
--

DROP TABLE IF EXISTS `Ajustes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Ajustes` (
  `id` int NOT NULL AUTO_INCREMENT,
  `host` varchar(1000) DEFAULT NULL,
  `hostnotification` varchar(1000) DEFAULT NULL,
  `accesstoken` varchar(1000) DEFAULT NULL,
  `hostapizap` varchar(1000) DEFAULT NULL,
  `tokenapizap` varchar(1000) DEFAULT NULL,
  `liga_desliga_pix` int NOT NULL DEFAULT '2',
  `mail_Host` varchar(255) DEFAULT NULL,
  `mail_SMTPAuth` varchar(255) DEFAULT NULL,
  `mail_Username` varchar(255) DEFAULT NULL,
  `mail_Password` varchar(255) DEFAULT NULL,
  `mail_SMTPSecure` varchar(255) DEFAULT NULL,
  `mail_Port` varchar(255) DEFAULT NULL,
  `mail_Email` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Ajustes`
--

LOCK TABLES `Ajustes` WRITE;
/*!40000 ALTER TABLE `Ajustes` DISABLE KEYS */;
INSERT INTO `Ajustes` VALUES (1,'financeiro.skynetfibra.net.br/checkout','financeiro.skynetfibra.net.br/checkout/config/pix','APP_USR-2165415360614024-022614-650b34abe4ccc5fa1eac0e6e67101fb5-1544469494','https://apiatendimento.skynetfibra.net.br/','22f9292e-bce1-4de1-82f9-c447ee0cac20',1,'smtplw.com.br',NULL,'skynetfibra','ndGgmLfw2574',NULL,'587','financeiro@skynetfibra.net.br');
/*!40000 ALTER TABLE `Ajustes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Assinatura`
--

DROP TABLE IF EXISTS `Assinatura`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Assinatura` (
  `id` int NOT NULL AUTO_INCREMENT,
  `email` varchar(255) DEFAULT NULL,
  `doc` varchar(255) DEFAULT NULL,
  `titulo` varchar(255) DEFAULT NULL,
  `descricao` varchar(2000) DEFAULT NULL,
  `caminho` varchar(2000) DEFAULT NULL,
  `url` varchar(2000) DEFAULT NULL,
  `data_envio` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `data_assinado` timestamp NULL DEFAULT NULL,
  `status` varchar(255) DEFAULT 'Nao assinado',
  `hash` varchar(255) DEFAULT NULL,
  `token` varchar(255) DEFAULT NULL,
  `nome` varchar(255) DEFAULT NULL,
  `ticket` varchar(255) DEFAULT NULL,
  `atendente` varchar(255) DEFAULT NULL,
  `hash_assinado` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=431 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Assinatura`
--

LOCK TABLES `Assinatura` WRITE;
/*!40000 ALTER TABLE `Assinatura` DISABLE KEYS */;
/*!40000 ALTER TABLE `Assinatura` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `AudioBot`
--

DROP TABLE IF EXISTS `AudioBot`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `AudioBot` (
  `id` int NOT NULL AUTO_INCREMENT,
  `titulo` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `AudioBot`
--

LOCK TABLES `AudioBot` WRITE;
/*!40000 ALTER TABLE `AudioBot` DISABLE KEYS */;
INSERT INTO `AudioBot` VALUES (1,'MENU-INICIAL','assets/audioBot/MENU-INICIAL.mp3'),(2,'MENU-INICIAL-ERR1','assets/audioBot/MENU-INICIAL-ERR1.mp3'),(3,'MENU-INICIAL-ERR2','assets/audioBot/MENU-INICIAL-ERR2.mp3'),(4,'MENU-PLANOS','assets/audioBot/MENU-PLANOS.mp3'),(5,'MENU-PLANOS-ERR1','assets/audioBot/MENU-PLANOS-ERR1.mp3'),(6,'MENU-CLIENTE-ERR1','assets/audioBot/MENU-CLIENTE-ERR1.mp3'),(7,'TRANSFERINDO-ATENDIMENTO','assets/audioBot/TRANSFERINDO-ATENDIMENTO.mp3'),(8,'INFO-BLOQUEIO','assets/audioBot/INFO-BLOQUEIO.mp3');
/*!40000 ALTER TABLE `AudioBot` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `CampaignSettings`
--

DROP TABLE IF EXISTS `CampaignSettings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `CampaignSettings` (
  `id` int NOT NULL AUTO_INCREMENT,
  `key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `companyId` int DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `companyId` (`companyId`),
  CONSTRAINT `CampaignSettings_ibfk_1` FOREIGN KEY (`companyId`) REFERENCES `Companies` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `CampaignSettings`
--

LOCK TABLES `CampaignSettings` WRITE;
/*!40000 ALTER TABLE `CampaignSettings` DISABLE KEYS */;
/*!40000 ALTER TABLE `CampaignSettings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `CampaignShipping`
--

DROP TABLE IF EXISTS `CampaignShipping`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `CampaignShipping` (
  `id` int NOT NULL AUTO_INCREMENT,
  `jobId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `number` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `confirmationMessage` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `confirmation` tinyint(1) DEFAULT NULL,
  `contactId` int DEFAULT NULL,
  `campaignId` int NOT NULL,
  `confirmationRequestedAt` datetime DEFAULT NULL,
  `confirmedAt` datetime DEFAULT NULL,
  `deliveredAt` datetime DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `contactId` (`contactId`),
  KEY `campaignId` (`campaignId`),
  CONSTRAINT `CampaignShipping_ibfk_1` FOREIGN KEY (`contactId`) REFERENCES `ContactListItems` (`id`) ON DELETE SET NULL ON UPDATE SET NULL,
  CONSTRAINT `CampaignShipping_ibfk_2` FOREIGN KEY (`campaignId`) REFERENCES `Campaigns` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `CampaignShipping`
--

LOCK TABLES `CampaignShipping` WRITE;
/*!40000 ALTER TABLE `CampaignShipping` DISABLE KEYS */;
/*!40000 ALTER TABLE `CampaignShipping` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Campaigns`
--

DROP TABLE IF EXISTS `Campaigns`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Campaigns` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `message1` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `message2` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `message3` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `message4` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `message5` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `confirmationMessage1` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `confirmationMessage2` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `confirmationMessage3` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `confirmationMessage4` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `confirmationMessage5` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `status` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `confirmation` tinyint(1) DEFAULT '0',
  `mediaPath` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `mediaName` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `companyId` int NOT NULL,
  `contactListId` int DEFAULT NULL,
  `whatsappId` int DEFAULT NULL,
  `scheduledAt` datetime DEFAULT NULL,
  `completedAt` datetime DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `companyId` (`companyId`),
  KEY `contactListId` (`contactListId`),
  KEY `whatsappId` (`whatsappId`),
  CONSTRAINT `Campaigns_ibfk_1` FOREIGN KEY (`companyId`) REFERENCES `Companies` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `Campaigns_ibfk_2` FOREIGN KEY (`contactListId`) REFERENCES `ContactLists` (`id`) ON DELETE SET NULL ON UPDATE SET NULL,
  CONSTRAINT `Campaigns_ibfk_3` FOREIGN KEY (`whatsappId`) REFERENCES `Whatsapps` (`id`) ON DELETE SET NULL ON UPDATE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Campaigns`
--

LOCK TABLES `Campaigns` WRITE;
/*!40000 ALTER TABLE `Campaigns` DISABLE KEYS */;
/*!40000 ALTER TABLE `Campaigns` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Chatbot`
--

DROP TABLE IF EXISTS `Chatbot`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Chatbot` (
  `id` int NOT NULL AUTO_INCREMENT,
  `shortcut` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  `url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=22 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Chatbot`
--

LOCK TABLES `Chatbot` WRITE;
/*!40000 ALTER TABLE `Chatbot` DISABLE KEYS */;
INSERT INTO `Chatbot` VALUES (5,'BOT-INICIO','✅ *M E N U    P R I N C I P A L* \n\n1️⃣  Sou Cliente\n2️⃣  Planos\n3️⃣  Configurar CDNTV\n','2023-12-02 01:11:14','2024-05-23 21:15:20',NULL),(6,'BOT-INICIO-ERR1','✅ *M E N U    P R I N C I P A L* \n\n1️⃣  Sou Cliente\n2️⃣  Planos\n3️⃣  Configurar CDNTV\n','2023-12-02 22:34:30','2024-05-23 21:15:34',NULL),(7,'BOT-CPF-INV-FIM','☹️ O nosso atendimento está sendo encerrado porque você não me informou um documento válido.\n\nMas não se preocupe, você pode entrar em contato novamente por este canal.\n\nSe precisar é só me chamar! ','2023-12-02 22:35:15','2023-12-02 22:45:45',NULL),(8,'BOT-CPF-INV-1','☹ O documento que você me informou está incorreto.  \n\nDigite novamente todos os números do seu CPF/CNPJ para seguirmos com o atendimento.','2023-12-02 22:35:50','2023-12-02 22:39:16',NULL),(9,'BOT-CPF-INV-2','☹ Olha... ainda não entendi o documento informado.\n\nPor favor, me envia todos os números do seu CPF/CNPJ para seguirmos com o atendimento.','2023-12-02 22:36:39','2023-12-02 22:39:23',NULL),(10,'CPF-INV-FIM','☹ Olha... ainda não entendi o documento informado.\n\nPor favor, me envia todos os números do seu CPF/CNPJ para seguirmos com o atendimento.','2023-12-02 22:37:18','2023-12-02 22:37:18',NULL),(11,'BOT-PLANOS','SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA!\n\nPlanos em fibra óptica, pós-pago, telefone fixo ilimitado, aplicativo de canais de TV ao vivo, rastreador veicular e velocidade gamer.\n\nEscolha o melhor plano para você!\n\n➡ 100M_UpDown: R$59,99\n➡ 250M_UpDown: R$69,99\n➡ 350M_UpDown: R$79,99\n➡ 500M_UpDown: R$99,99\n➡ 600M_UpDown: R$109,99\n➡ Canais de TV ao vivo: R$13,00\n➡ Telefone fixo: R$10,00\n➡ Telemedicina: R$10,00\n➡ Rastreador veicular: R$20,00\n\n✅ TELEFONE FIXO ILIMITADO\n✅ MAIOR ESTABILIDADE\n✅ ULTRAVELOCIDADE\n✅ CANAIS DE TV AO VIVO\n✅ TELEMEDICINA\n✅ RASTREADOR VEICULAR COM LOCALIZAÇÃO EM TEMPO REAL\n\n⚙️ Instalação:\nCom equipamento(s) em comodato(s) e taxa de instalação.\n\n✔️ Consulte cobertura em sua área;\n✔️ Para ativação do telefone fixo é necessário ter aparelho próprio;\n✔️ App de canais ao vivo: verifique a compatibilidade da plataforma em seus dispositivos;\n✔️ A taxa de instalação deve ser paga com antecedência e não é reembolsável.\n✔️ Linhas VOIP para você ou para sua empresa.\n✔️ Rastreador veicular com acesso via aplicativo e suporte técnico.\n✔️ Telemedicina: plano básico e especializado\n\n⚠️ *IMPORTANTE*: A ANATEL estabelece que a velocidade média mensal entregue ao usuário deve ser de, no mínimo, 40% da velocidade contratada em pelo menos 90% das medições realizadas. A medição da velocidade deve ser feita de forma transparente e confiável, preferencialmente via cabo Ethernet, para evitar interferências comuns em conexões Wi-Fi. Resolução nº 574/2011 ANATEL.\n\n📝 Faça seu cadastro através do nosso site:\n https://skynetfibra.net.br/cadastro.hhvm','2023-12-02 22:38:00','2024-07-04 17:12:53','uploads/BOT-PLANOS.jpeg'),(12,'BOT-INFO-CPF','*Digite todos os números do CPF/CNPJ do titular para seguirmos com o atendimento.*','2023-12-02 22:42:47','2023-12-02 22:43:10',NULL),(13,'BOT-FINALIZAR','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*!\n\nAgradecemos pela preferência.\n\n*Siga-nos no Instagram*:\nhttps://www.instagram.com/skynet_fibra\n\nSempre que precisar estaremos aqui! ','2023-12-02 22:47:22','2023-12-02 22:47:22',NULL),(14,'BOT-INICIO-ERR2','✅ *M E N U    P R I N C I P A L* \n\n1️⃣  Sou Cliente\n2️⃣  Planos\n3️⃣  Configurar CDNTV\n','2024-05-23 13:57:04','2024-05-23 21:15:44',NULL),(16,'INFO-MENU-CLIENTE','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*! Internet rápida e estável para você navegar a vontade!\n\n✅ Aproveite e baixe nosso aplicativo para conhecer nossos serviços:\n\n*Android*: https://evolink.me/ZaBKZg\n*iOS*: https://evolink.me/HMpW8J \n\n','2024-11-14 12:00:00','2024-11-14 12:00:00',NULL),(17,'MENU-INFO-CONTRATOS','_Por favor, escolha um contrato para *Atendimento*._\n\n1️⃣  Internet | TV | Telefonia | Telemedicina\n2️⃣  Plataforma GPS','2025-04-25 01:23:48','2025-04-25 01:23:48',NULL),(18,'INFO-BLOQUEIO-MENU','❓ Ficou com alguma dúvida?  \nSe *sim*, responda com uma das opções do menu abaixo ⬇️\n','2025-07-07 12:41:59','2025-07-07 12:41:59',NULL),(19,'MENU-CDNTV','✅ *M E N U   C D N  T V* \n\n1️⃣  *Configurar na SMART-TV*\n2️⃣  *Configurar no Celular*\n3️⃣  *Falar com Comercial*\n\n0️⃣ *Encerrar Atendimento*','2025-07-09 20:58:42','2025-07-09 20:58:42',NULL),(20,'OP1-CDNTV','☑️ *CONFIGURAÇÃO CDNTV NA SMART TV*\n\n⚠️ Importante: Smart TV com Android ou que tenha loja de aplicativos\nNome do app: CDNTVPLAY (baixe na loja de aplicativo da sua TV)\n\n✔️ *DADOS PARA LOGIN*:\n*Dominio/Servidor*: 4streamtv.com\n*Usuário*: joao12345 (Exemplo: primeiro nome do titular + 4 ou 5 primeiros números do CPF/CNPJ)\n*Senha*: 1020\n\n✔️ *PASSOS*:\n1️⃣ Abra o app CDNTVPLAY na sua TV\n2️⃣ Digite os dados acima nos campos de login.\n3️⃣ Clique em *Entrar*.\n\nPronto! Os canais estarão disponíveis. \nAproveite ao máximo!\n','2025-07-09 21:12:54','2025-07-09 21:12:54',NULL),(21,'OP2-CDNTV','☑️ *CONFIGURAÇÃO CDNTV NO CELULAR* \n\n*EXEMPLO* 1️⃣\nDispositivo: Celular Android\nAplicativo: CDNTV (baixe o APK fornecido pela SKYNET ou via link)\n\n*EXEMPLO* 2️⃣\nIOS: Baixar na App Store\nAplicativo: Baixar APK  https://apps.apple.com/br/app/cdntv-play/id1346716760\n\n*EXEMPLO* 3️⃣\nAplicativo Mobile para Android (APK): Baixar APK\nPara TVs não Android: Na Play Store (da sua TV), procure pelo aplicativo de nome: CDNTVPLAY.\n\n✔️ *DADOS PARA LOGIN*:\n*Servidor/Portal*: 4streamtv.com\n*Usuário*: maria78901 (Exemplo: primeiro nome do titular + 4 ou 5 primeiros números do CPF/CNPJ)\n*Senha*: 1020\n\n✔️ *PASSOS*\n1️⃣ Instale e abra o app CDNTV no celular.\n2️⃣ Digite o servidor, usuário e senha nos campos.\n3️⃣ Clique em Login.\n\nPronto! Agora você pode assistir aos canais direto no celular.\n','2025-07-09 21:13:06','2025-07-09 21:13:06',NULL);
/*!40000 ALTER TABLE `Chatbot` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Checkout`
--

DROP TABLE IF EXISTS `Checkout`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Checkout` (
  `id` int NOT NULL AUTO_INCREMENT,
  `type` varchar(14) DEFAULT NULL,
  `doc` varchar(20) DEFAULT NULL,
  `email` varchar(1000) DEFAULT NULL,
  `descricao` varchar(1000) DEFAULT NULL,
  `referente` varchar(1000) DEFAULT NULL,
  `valor` varchar(1000) DEFAULT NULL,
  `linha` text CHARACTER SET latin1 COLLATE latin1_swedish_ci,
  `qrcode` text CHARACTER SET latin1 COLLATE latin1_swedish_ci,
  `codigo_transacao` varchar(1000) DEFAULT NULL,
  `status` varchar(50) DEFAULT 'pendente',
  `datetime` datetime DEFAULT CURRENT_TIMESTAMP,
  `hora` varchar(20) DEFAULT NULL,
  `minuto` varchar(50) DEFAULT NULL,
  `number` varchar(255) DEFAULT NULL,
  `hash` varchar(255) DEFAULT NULL,
  `nome` varchar(255) DEFAULT NULL,
  `atendente` varchar(255) DEFAULT NULL,
  `url` varchar(255) DEFAULT NULL,
  `pago_dia` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=324 DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Checkout`
--

LOCK TABLES `Checkout` WRITE;
/*!40000 ALTER TABLE `Checkout` DISABLE KEYS */;
/*!40000 ALTER TABLE `Checkout` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Companies`
--

DROP TABLE IF EXISTS `Companies`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Companies` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `phone` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  `status` tinyint(1) DEFAULT '1',
  `dueDate` datetime DEFAULT NULL,
  `recurrence` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Companies`
--

LOCK TABLES `Companies` WRITE;
/*!40000 ALTER TABLE `Companies` DISABLE KEYS */;
/*!40000 ALTER TABLE `Companies` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ContactCustomFields`
--

DROP TABLE IF EXISTS `ContactCustomFields`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ContactCustomFields` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `value` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `contactId` int NOT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `contactId` (`contactId`),
  CONSTRAINT `ContactCustomFields_ibfk_1` FOREIGN KEY (`contactId`) REFERENCES `Contacts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ContactCustomFields`
--

LOCK TABLES `ContactCustomFields` WRITE;
/*!40000 ALTER TABLE `ContactCustomFields` DISABLE KEYS */;
/*!40000 ALTER TABLE `ContactCustomFields` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ContactLists`
--

DROP TABLE IF EXISTS `ContactLists`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ContactLists` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `companyId` int DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `companyId` (`companyId`),
  CONSTRAINT `ContactLists_ibfk_1` FOREIGN KEY (`companyId`) REFERENCES `Companies` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ContactLists`
--

LOCK TABLES `ContactLists` WRITE;
/*!40000 ALTER TABLE `ContactLists` DISABLE KEYS */;
/*!40000 ALTER TABLE `ContactLists` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ContactTags`
--

DROP TABLE IF EXISTS `ContactTags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ContactTags` (
  `contactId` int NOT NULL,
  `tagId` int NOT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  KEY `contactId` (`contactId`),
  KEY `tagId` (`tagId`),
  CONSTRAINT `ContactTags_ibfk_1` FOREIGN KEY (`contactId`) REFERENCES `Contacts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ContactTags_ibfk_2` FOREIGN KEY (`tagId`) REFERENCES `Tags` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ContactTags`
--

LOCK TABLES `ContactTags` WRITE;
/*!40000 ALTER TABLE `ContactTags` DISABLE KEYS */;
/*!40000 ALTER TABLE `ContactTags` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Contacts`
--

DROP TABLE IF EXISTS `Contacts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Contacts` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `number` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `profilePicUrl` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT '',
  `isGroup` tinyint(1) NOT NULL DEFAULT '0',
  `nome` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `login` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `plano` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `bloqueado` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `cpfcnpj` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `titulo` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `linha_digitavel` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `copiacola` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `valor` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `data_vencimento` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `categoria` varchar(3) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT '0',
  `tentativas` varchar(3) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT '0',
  `liga_desliga_pix` int NOT NULL DEFAULT '2',
  `transferido` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT '0',
  `clienteId` int DEFAULT NULL,
  `conectado` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `acctstarttime` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `acctstoptime` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `uuid_suporte` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `fechamento` datetime DEFAULT NULL,
  `reply` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `tecnico` int DEFAULT NULL,
  `login_atend` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `motivo_fechar` text COLLATE utf8mb4_general_ci,
  `Assinatura` text COLLATE utf8mb4_general_ci,
  `obs` text COLLATE utf8mb4_general_ci,
  `Unid` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `Equipamento` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `Qtd` int DEFAULT NULL,
  `assunto` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `abertura` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `chamado` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `atendente` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `visita` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `prioridade` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ramal` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `id_cliente` int DEFAULT NULL,
  `nome_tecnico` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `id_equipamento` int DEFAULT NULL,
  `qtd_cabo` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `qtd_conector_verde` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `qtd_conector_azul` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `qtd_splitter` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `nome_cabo` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `nome_conector_verde` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `nome_conector_azul` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `nome_splitter` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `serial` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `number` (`number`)
) ENGINE=InnoDB AUTO_INCREMENT=135864 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Contacts`
--

LOCK TABLES `Contacts` WRITE;
/*!40000 ALTER TABLE `Contacts` DISABLE KEYS */;
/*!40000 ALTER TABLE `Contacts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Disparos`
--

DROP TABLE IF EXISTS `Disparos`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Disparos` (
  `id` int NOT NULL AUTO_INCREMENT,
  `number` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `msg` longtext COLLATE utf8mb4_general_ci,
  `url` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT 'a enviar',
  `datetime` datetime DEFAULT CURRENT_TIMESTAMP,
  `mimetype` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Disparos`
--

LOCK TABLES `Disparos` WRITE;
/*!40000 ALTER TABLE `Disparos` DISABLE KEYS */;
/*!40000 ALTER TABLE `Disparos` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Messages`
--

DROP TABLE IF EXISTS `Messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Messages` (
  `id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `body` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `ack` int NOT NULL DEFAULT '0',
  `read` tinyint(1) NOT NULL DEFAULT '0',
  `mediaType` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mediaUrl` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ticketId` int NOT NULL,
  `createdAt` datetime(6) NOT NULL,
  `updatedAt` datetime(6) NOT NULL,
  `fromMe` tinyint(1) NOT NULL DEFAULT '0',
  `isDeleted` tinyint(1) NOT NULL DEFAULT '0',
  `contactId` int DEFAULT NULL,
  `quotedMsgId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `companyId` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `ticketId` (`ticketId`),
  KEY `Messages_contactId_foreign_idx` (`contactId`),
  KEY `Messages_quotedMsgId_foreign_idx` (`quotedMsgId`),
  KEY `Messages_companyId_foreign_idx` (`companyId`),
  CONSTRAINT `Messages_contactId_foreign_idx` FOREIGN KEY (`contactId`) REFERENCES `Contacts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `Messages_ibfk_2` FOREIGN KEY (`ticketId`) REFERENCES `Tickets` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `Messages_quotedMsgId_foreign_idx` FOREIGN KEY (`quotedMsgId`) REFERENCES `Messages` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Messages`
--

LOCK TABLES `Messages` WRITE;
/*!40000 ALTER TABLE `Messages` DISABLE KEYS */;
/*!40000 ALTER TABLE `Messages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Queues`
--

DROP TABLE IF EXISTS `Queues`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Queues` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `color` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `greetingMessage` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  `startWork` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `endWork` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `absenceMessage` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `companyId` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`),
  UNIQUE KEY `color` (`color`),
  KEY `Queues_companyId_foreign_idx` (`companyId`),
  CONSTRAINT `Queues_companyId_foreign_idx` FOREIGN KEY (`companyId`) REFERENCES `Companies` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Queues`
--

LOCK TABLES `Queues` WRITE;
/*!40000 ALTER TABLE `Queues` DISABLE KEYS */;
INSERT INTO `Queues` VALUES (1,'COMERCIAL','#ffa500','','2023-11-08 07:50:45','2024-07-09 17:13:31','08:00','17:00','',NULL),(2,'FINACEIRO','#0000ff','','2023-11-08 07:51:17','2024-07-07 12:11:31','08:00','17:00','',NULL),(3,'SUPORTE','#ff0000','','2023-11-08 07:51:49','2024-07-07 11:42:39','','17:00','',NULL);
/*!40000 ALTER TABLE `Queues` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `QuickAnswers`
--

DROP TABLE IF EXISTS `QuickAnswers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `QuickAnswers` (
  `id` int NOT NULL AUTO_INCREMENT,
  `shortcut` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=54 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `QuickAnswers`
--

LOCK TABLES `QuickAnswers` WRITE;
/*!40000 ALTER TABLE `QuickAnswers` DISABLE KEYS */;
INSERT INTO `QuickAnswers` VALUES (17,'FINALIZAR CONVERSA','Estamos encerrando nossa conversa por agora, mas queremos lembrar que nossa equipe está sempre à disposição para ajudar com qualquer dúvida ou necessidade. Não hesite em nos procurar novamente!  \n\n\n💸 *Indique e ganhe R$30 no PIX*!\nConvide um amigo ou vizinho para aproveitar essa promoção imperdível e receba sua recompensa!  \n\n\n📲 *Baixe nosso aplicativo e aproveite nossos serviço*:\nAndroid: https://evolink.me/ZaBKZg\niOS: https://evolink.me/HMpW8J  \n\n\n📸 *Acompanhe todas as novidades no Instagram*:\nhttps://www.instagram.com/skynet_fibra  \n\n\n🤝 Obrigado por escolher a SKYNET FIBRA!','2024-11-16 08:38:13','2025-05-27 15:14:59'),(18,'ALTERAR SENHA','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA!*\n\nPara alteração de senha do WI-FI é necessário o envio de uma nova senha de, pelo menos, 8 caracteres. O prazo será de 72 horas, no mínimo, para atualizar a senha em todos os dispositivos que se conectam à sua rede. \n\n⚠️ *AVISO IMPORTANTE*: Para garantir mais segurança e estabilidade no acesso à internet, a alteração da sua senha pode ser feita, no máximo, uma vez a cada 90 dias\n\n✅ *ORIENTAÇÃO*: Proteja sua internet e não compartilhe a senha do seu WI-FI. Pode parecer inofensivo compartilhar a senha com um amigo ou vizinho, mas isso pode sobrecarregar sua rede, deixar sua conexão lenta e até comprometer sua segurança.\n\n✅ *FIQUE ATENTO*: Após a alteração da senha todos os dispositivos irão se desconectar do WI-FI e será necessário a inclusão da nova senha nesses dispositivos para acessar a rede. \n\n','2024-11-16 20:44:15','2025-04-02 14:26:54'),(19,'CONDIÇÕES DE ASSINATURA','*INFORMATIVO IMPORTANTE PARA VOCÊ LER: CONDIÇÕES DA ASSINATURA, USO DE EQUIPAMENTOS E SERVIÇOS OFERECIDOS*\n\n\nBem-vindo(a) à SKYNET FIBRA!\n\nQueremos garantir que você tenha recebido todas as informações sobre sua assinatura.\n\n\n*1. Equipamento em Comodato*:\n   O(s) equipamento(s) fornecido é de propriedade da SKYNET FIBRA e está em regime de comodato, ou seja, é cedido a você para uso durante o período contratado.\n\n*2. Proporcionalidade de Cobrança*: \n   Dependendo da data de instalação em relação à data de vencimento do pagamento, terá um valor proporcional referente aos dias de uso. Isso quer dizer que a primeira cobrança pode ser ajustada para incluir apenas os dias reais que você usou a internet no primeiro mês.\n\n*3. Atraso no Pagamento e Bloqueio de Serviço*: \n   Em caso de atraso no pagamento, o serviço será bloqueado após 10 dias corridos de inadimplência. Durante esse período, você será notificado sobre o bloqueio iminente.\n\n*4. Recolhimento de Equipamento*: \n   Se o pagamento não for regularizado dentro de um mês após o bloqueio, realizaremos o recolhimento do(s) equipamento(s) cedido em comodato. Este procedimento será realizado para garantir a integridade dos nossos ativos.\n\n*5. Plano com Aplicativo de TV*: \n   Para aproveitar todos os recursos e conteúdos oferecidos, é importante que seus dispositivos sejam compatíveis com a plataforma. Verifique se sua TV e/ou dispositivos tem o aplicativo pré-instalado ou disponível para download na loja de aplicativos do seu aparelho. *IMPORTANTE: Certifique-se que a versão do(s) seu(s) dispositivo(s) suporte a plataforma que nós estaremos disponibilizando para você*. \n\n*6. Plano com Telefone Fixo*: \n   É necessário ter aparelho de telefone fixo próprio. Seu número DEVE estar ativo para acontecer a portabilidade. O prazo para conclusão da portabilidade é de 7 dias úteis, conforme a liberação da antiga prestadora de serviço. Enquanto a portabilidade não for concluída, você poderá fazer ligações normalmente, mas não poderá receber ligações. \n\n*7. Aplicativo Cliente*: \n  2ª via de boleto, abertura de chamado, acompanhamento de dados, recibos de pagamento e muito mais.\n\n*Android*: https://evolink.me/ZaBKZg\n*iOS*: https://evolink.me/HMpW8J \n\nPrimeiro acesso? Segue esse passo a passo:\n\n1️⃣ Criar/recuperar senha\n2️⃣ Coloque seu CPF/CNPJ\n3️⃣ Crie uma nova senha \n4️⃣ Volte para tela inicial e acesse o aplicativo\n\n*8. Deseja Agregar mais Serviços ao seu Plano?*: \n\n✅ Telefone fixo ilimitado\n✅ Plataforma de canais ao vivo\n✅ Telemedicina para sua saúde\n✅ Rastreador veicular com aplicativo em tempo real\n\nFale conosco! \n\nDÚVIDAS? Pode perguntar, estamos aqui para melhor te atender. \n\nAtenciosamente,\n\n*SKYNET FIBRA* \nskynetfibra.net.br \n(71) 3016-6666 | 98790-8777\n','2024-11-16 20:46:13','2025-08-22 10:03:38'),(20,'ENIVAR CPF/CNPJ','Para que eu possa seguir com seu atendimento, me envie o CPF/CNPJ ou nome completo do titular da assinatura.','2024-11-16 20:46:59','2025-02-14 16:32:24'),(21,'ENVIO DE DOCUMENTOS ','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*!\n\n\n*Uma etapa a menos para você se tornar cliente da SKYNET FIBRA*\n\nPara que possamos seguir de maneira segura e eficiente, informamos que é necessário o envio de um documento com foto e uma selfie segurando o mesmo documento.\n\nA selfie é importante para garantir que a pessoa que está solicitando o serviço é a mesma que consta no documento com a foto. Dessa forma, evitamos possíveis fraudes e garantimos a segurança das informações fornecidas.\n\n✅ Priorizamos sua privacidade e segurança. A Lei Geral de Proteção de Dados (LGPD), Lei nº 13.709/2018, assegura que seus dados pessoais sejam tratados com segurança e transparência. As informações que você compartilha conosco, como nome, CPF, foto e endereço são protegidas e utilizadas exclusivamente para a prestação de nossos serviços, nunca sendo compartilhadas sem sua autorização.\n\n\nAgradecemos a sua compreensão e colaboração.\n\n\n','2024-11-16 20:47:24','2025-06-02 12:27:27'),(24,'REINICIAR EQUIPAMENTO','⚙️ Por favor, realize os procedimentos abaixo:\n\n1.	Desligue o equipamento da tomada, aguarde 30 segundos e ligue-o novamente. \n2.	Teste sua conexão abrindo, por exemplo, o navegador, Youtube ou Netflix. \n3.	Realize os seguintes testes: \n•	https://www.speedtest.net/pt (*O TESTE DE VELOCIDADE DEVE SER FEITO NA REDE 5G*)\n•	https://test-ipv6.com/index.html.pt_BR\n4.	Envie para nosso WhatsApp o print desses testes.\n\n⚠️ *Importante*: A ANATEL estabelece que a velocidade média mensal entregue ao usuário deve ser de, no mínimo, 40% da velocidade contratada em pelo menos 90% das medições realizadas. A medição da velocidade deve ser feita de forma transparente e confiável, preferencialmente via cabo Ethernet, para evitar interferências comuns em conexões Wi-Fi. Resolução nº 574/2011 ANATEL.\n\nFicaremos aguardando seu retorno para darmos a tratativa devida a sua demanda.\n\n','2024-11-16 20:49:20','2025-08-18 16:00:03'),(25,'RETORNO AO CLIENTE','Prezado(a) cliente,\n\nEspero que esteja aproveitando uma conexão mais estável após nossa recente visita de manutenção.\nEstamos entrando em contato para expressar nossa gratidão pela sua paciência e para assegurar que sua experiência com a SKYNET FIBRA seja a melhor possível.\n\n*Se houver qualquer outra preocupação ou feedback adicional que queira compartilhar, estamos aqui para ajudar. Valorizamos sua confiança em nossos serviços*.\n\n🤝 Agradecemos pela preferência.','2024-11-16 20:49:49','2024-11-18 19:09:46'),(26,'MANUTENÇÃO GERAL','Prezado,\n\nInformamos que houve um rompimento de fibra em um de nossos pontos de distribuição causando instabilidade na rede.\n\nEstamos trabalhando para solucionar o ocorrido o mais breve possível. \n\nAgradecemos a compreensão. \n\nSKYNET FIBRA','2024-11-16 20:50:20','2024-11-18 19:08:15'),(27,'PLANOS','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*!\n\nPlanos em fibra óptica, pós-pago, telefone fixo ilimitado, plataforma de canais de TV ao vivo, rastreador veicular e velocidade gamer.\n\nEscolha o melhor plano para você!\n\n➡ 100M_UpDown: R$59,99\n➡ 250M_UpDown: R$69,99\n➡ 350M_UpDown: R$79,99\n➡ 500M_UpDown: R$99,99\n➡ 600M_UpDown: R$109,99\n➡ Canais de TV ao vivo: R$13,00\n➡ Telefone fixo: R$10,00\n➡ Telemedicina: R$10,00\n➡ Rastreador veicular: R$20,00\n\n✅ TELEFONE FIXO ILIMITADO\n✅ MAIOR ESTABILIDADE\n✅ ULTRAVELOCIDADE\n✅ CANAIS DE TV AO VIVO\n✅ TELEMEDICINA\n✅ RASTREADOR VEICULAR COM LOCALIZAÇÃO EM TEMPO REAL\n\n\n⚙️ Instalação:\nCom equipamento(s) em comodato(s) e taxa de instalação.\n\n✔️ Consulte cobertura em sua área;\n✔️ Para ativação do telefone fixo é necessário ter aparelho próprio;\n✔️ App de canais ao vivo: verifique a compatibilidade da plataforma em seus dispositivos;\n✔️ A taxa de instalação deve ser paga com antecedência e não é reembolsável.\n✔️ Linhas VOIP para você ou para sua empresa.\n✔️ Rastreador veicular com acesso via aplicativo e suporte técnico.\n✔️ Telemedicina: plano básico e especializado\n\n⚠️ IMPORTANTE: A ANATEL estabelece que a velocidade média mensal entregue ao usuário deve ser de, no mínimo, 40% da velocidade contratada em pelo menos 90% das medições realizadas. A medição da velocidade deve ser feita de forma transparente e confiável, preferencialmente via cabo Ethernet, para evitar interferências comuns em conexões Wi-Fi. Resolução nº 574/2011 ANATEL.\n\n*Faça seu cadastro através do nosso site*:\n https://skynetfibra.net.br/cadastro.hhvm\n','2024-11-18 13:37:46','2025-07-04 12:23:59'),(28,'2A VIA DE BOLETO','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA!*\n\nPara solicitar o código de barras do boleto e/ou PIX copie e cole do boleto através do nosso atendimento automático, siga estes passos:\n\n1. Abra o menu digitando #menu.\n2. Selecione a opção 2.\n3. Digite o CPF ou CNPJ.\n4. Informe o número correspondente do boleto desejado.\n\nVocê receberá uma mensagem com o código de barras e informações do PIX para pagamento.\n\nÉ simples e conveniente obter o código de barras do boleto desejado utilizando nosso atendimento automático. Aproveite essa facilidade para efetuar seus pagamentos de forma rápida e segura.\n\n✅ BAIXE NOSSO APLICATIVO ATRAVÉS DO LINK ABAIXO PARA CONHECER NOSSOS SERVIÇOS: \n\nAndroid: https://evolink.me/ZaBKZg\niOS: https://evolink.me/HMpW8J \n\n🤝 Agradecemos pela preferência.\n\n\n','2024-11-18 14:03:39','2025-04-04 11:43:04'),(30,'TELEMEDICINA I','\n*SKYNET FIBRA E TELEMEDICINA* \n\n\nO *_Telemedicina_* é uma plataforma que permite consultas médicas a distância, utilizando tecnologias de vídeo, chat ou até mesmo telefone para conectar pacientes e profissionais de saúde. \n\n\nVeja abaixo como funciona: \n\n1. *Agendamento:* Consulta com um médico por meio de uma plataforma online, escolhendo a especialidade ou o profissional. \n2. *Consulta Remota:* No horário marcado, a consulta ocorre virtualmente, por videoconferência, chat ou chamada de voz. \n3. *Prescrições e Atestados:* Receitas e atestados digitais são emitidos após a consulta, com validade legal, acessíveis na plataforma ou por e-mail. \n4. *Exames:* Se necessário, o médico solicita exames digitalmente, com acompanhamento disponível na plataforma. \n5. *Acompanhamento e Histórico:* A plataforma armazena o histórico de consultas, receitas e exames, facilitando o monitoramento do tratamento. \n\n\n✅ *Benefícios da Telemedicina:*\n\n• *Praticidade:* Consultas de qualquer lugar, sem deslocamento.\n• *Rapidez:* Agendamento e consultas mais ágeis. \n• *Acessibilidade:* Acesso a especialistas, mesmo em áreas com pouca oferta. \n• *Clube de Vantagens:* Descontos e promoções exclusivas em produtos e serviços. \n\n\n✅ *Modalidades de Plano:*\n\n• *Plano Básico:* Consultas com clínico geral, por vídeo chamada, 24 horas por dia.\n\n*Mensalidade:* R$10,00 – Pode incluir dependentes, adicional de R$10,00 para cada dependente. \n\n• *Plano com Especialização:* Consultas com clinico e especializações: *Pediatria, Cardiologista, Ginecologista, Dermatologia, Geriatria, Gastroenterologista, Otorrinolaringologista, Ortopedia, Oftalmologista, Endocrinologia, Medicina da Família, Psiquiatria, Neurologia, Reumatologia, Pneumologista, Alergologista, Nutrólogo, Hematologia, Infectologia, Nefrologia, Urologia, Nutricionista, Psicologia, Fisioterapia.* Atendimento por vídeo chamada 24 horas por dia.\n\n*Mensalidade:* R$15,00 – Pode incluir dependentes, adicional de R$15,00 para cada dependente. \n\n\n✅ *Informações Adicionais:*\n\n• Pagamento antecipado para ativação da *_Telemedicina_*.\n• Carência de um mês para *_Especializações_*.\n• Prazo cinco dias para acesso à plataforma.\n• Acesso pelo aplicativo somente em sistema Android. \n\nAgradecemos a preferência. \n\n*SKYNET FIBRA* \nskynetfibra.net.br\n (71) 3016-6666 e (71) 987908777\n','2024-11-18 14:04:48','2024-12-09 15:25:49'),(31,'PÓS-CADASTRO I','Olá!\n\n😁 Obrigado por se cadastrar em nosso site! Ficaremos felizes em tê-lo conosco como cliente da SKYNET FIBRA, seu provedor de internet de confiança.\n\nAqui estão algumas informações importantes sobre o seu cadastro e que esperamos confirmar:\n\n✅ *Dados do Cadastro:*\nNome: \nE-mail: \nEndereço:\nCelular e WhatsApp:\nTelefone para recado:\nPlano:\nVencimento:\n\n✅ *Próximos Passos:*\nEnvio de documento de identificação pessoal e selfie com o mesmo documento;\nAssinatura de contrato;\nTaxa de instalação, se houver. \n\n*Dúvidas? Estamos à disposição para esclarecer maiores informações.*\n\n*SKYNET FIBRA*\n(71) 3016-6666 e (71) 987908777 \nskynetfibra.net.br','2024-11-18 14:06:44','2025-02-14 11:04:15'),(32,'PÓS-CADASTRO II','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA!*\n\nOlá!\n\n💬 Seja bem-vindo(a) à SKYNET FIBRA. Percebi que há um cadastro aberto em seu nome para instalação de internet em fibra óptica. \nAinda possui interesse? Deseja maiores informações? \n\n\n📶 Benefícios exclusivos para você ao tornar-se cliente:\n\n✅ Ultravelocidade e estabilidade\n✅ Down e UP iguais\n✅ Telefone fixo ilimitado\n✅ Aplicativo de TV \n✅ Telemedicina \n✅ Linha VOIP para empresas\n\nAtenciosamente, \n\n\n*SKYNET FIBRA*\nskynetfibra.net.br\n(71) 3016-6666 e (71) 98790-8777\n','2024-11-18 14:08:10','2025-06-18 16:29:28'),(33,'FALTA DE COMUNICAÇÃO','Estamos encerramento o atendimento por falta de comunicação. \n\nNossa equipe está sempre disponível para ajudá-lo em caso de dúvidas ou necessidades futuras.\n\nAtenciosamente, \n\nSKYNET FIBRA\n(71)3016-6666 e (71) 98790-8777\nskynetfibra.net.br','2024-11-18 14:19:10','2024-11-18 19:06:45'),(34,'APP CLIENTE','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*!\n\n\n✅ Segue link para baixar nosso aplicativo:\n\n*Android*: https://evolink.me/ZaBKZg\n*iOS*: https://evolink.me/HMpW8J \n\nPrimeiro acesso? Segue esse passo a passo:\n\n1️⃣ Criar/recuperar senha\n2️⃣ Coloque seu CPF/CNPJ\n3️⃣ Crie uma nova senha \n4️⃣ Volte para tela inicial e acesse o aplicativo \n\nSiga-nos no Instagram:\nhttps://www.instagram.com/skynet_fibra\n\n🤝 Agradecemos pela preferência. \n','2024-11-18 14:25:06','2025-05-23 16:02:35'),(40,'OFERTA PARA O CLIENTE','📣 *EVITE O CANCELAMENTO DA SUA INTERNET! TEMOS UMA OFERTA IMPERDÍVEL PARA VOCÊ*!  \n\n\nSabemos como a sua satisfação é importante para nós, por isso, queremos te oferecer algo especial:  \n\n\n🎁 *1 mês de assinatura GRÁTIS* para você continuar aproveitando os benefícios SKYNET FIBRA!  \n\n\n✅ Acesso ao *Paramount+*, com os melhores filmes e séries.  \n✅ *Telemedicina* para cuidar da sua saúde de forma prática e rápida.  \n✅ *Telefonia VoIP ilimitada*, para falar à vontade com quem quiser.  \n\n\n💡 Reconsidere e aproveite essa oferta exclusiva! Entre em contato com a gente e vamos juntos encontrar a melhor solução para você.\n  \n\n📞 Fale agora com nossa equipe! Não perca essa oportunidade. 💙','2024-11-27 16:23:21','2025-02-14 11:08:03'),(41,'SOBRE IPTV','SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA! \n\n\nLembramos que *serviços de IPTV não autorizados* estão sujeitos a bloqueios pela ANATEL por se tratarem de pirataria. Esses bloqueios não têm relação com a qualidade de sua internet. Para garantir uma experiência estável e segura, recomendamos o uso de plataformas legalizadas.\n\nAgradecemos pela preferência.\n\n','2024-11-28 14:53:53','2024-12-09 15:09:45'),(42,'TELEMEDICINA II','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA!*\n\n\nAgora você pode realizar consultas, terapias e solicitação de exames através do Telemedicina.\n\n👨‍💻 *Siga o passo a passo para ativação do Telemedicina*\n\n1º acesso através do link:\n\n\n1.	Clicar no link: https://meu.uniogroup.app/Account/Access\n2.	Criar nova conta em “*Ainda não possui conta. Clica aqui*”\n3.	Criar uma senha e confirmar\n4.	Volte a tela inicial e faça o *login com seu CPF e a senha criada*\n\n\n⚠️ *Importante*: Seu login de acesso sempre será seu CPF e a senha criada no 1º acesso. \n\n\n🤝 Agradecemos pela preferência. \n\n\nSKYNET FIBRA\nskynetfibra.net.br\n(71) 3016-6666 e (71) 98790-8777\n\n','2024-12-10 15:12:19','2025-04-02 14:43:13'),(43,'ALTERAR VENCIMENTO','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*\n\n*Alteração de vencimento*\n\n1.	A alteração de vencimento poderá ser solicitada *até 3 dias antes do seu vencimento ou do novo vencimento desejado*;\n2.	Informe a nova data desejada para o vencimento: 01, 05, 10 ou 17;\n3.	No seu próximo vencimento haverá ajuste proporcional no 1º pagamento referente a alteração. Exemplo:\n•	*Se você antecipar o vencimento*: o próximo pagamento incluirá apenas os dias de uso correspondentes até a nova data de vencimento, resultando em um valor proporcionalmente menor.\n•	*Se você adiar o vencimento*: o próximo pagamento incluirá os dias extras de uso até a nova data, podendo gerar um valor proporcionalmente maior.\n4.	Concluída a alteração, será gerado seu novo carnê e boleto proporcional e enviados para você por e-mail e/ou WhatsApp.\n5.     O prazo para uma nova solicitação de alteração de vencimento deve ser, no mínimo, de 90 dias. \n\nDúvidas? Estamos à disposição para ajudar!\n\nSKYNET FIBRA\nskynetfibra.net.br\n','2025-02-14 16:43:37','2025-07-16 16:54:41'),(45,'VOIP','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*!\n\n\n*DESCUBRA OS BENEFÍCIOS DA GLOBAL VOIP*:\n\n✅ *Para clientes*:\n\n1.	Custo acessível: apenas R$10,00 por número;\n2.	Chamadas ilimitadas para fixo e celular, para qualquer lugar do Brasil (sujeito à política de uso justo);\n3.	Portabilidade gratuita;\n4.	Necessário ter aparelho telefônico próprio.\n\n✔️ *Consulte condições*.\n\n✅  *Para seu negócio*: \n\n1.	DID’s disponíveis para seus clientes;\n2.	Chamadas ilimitadas para fixo e celular, para qualquer lugar do Brasil (sujeito à política de uso justo);\n3.	Plataforma intuitiva e relatórios acessíveis;\n4.	Cadastro rápido de novos números em minutos, sem burocracia;\n5.	PABX;\n6.	Gravações de chamadas;\n7.	Ramais adicionais;\n8.	Equipamentos.\n\n✔️ *Solicite sua proposta agora mesmo*!\n\nContate-nos para qualquer dúvida. \n\nAgradecemos sua confiança! \n\nSKYNET FIBRA\n(71) 3016-6666 e (71)98790-8777\nskynetfibra.net.br\n','2025-02-27 12:01:23','2025-05-23 16:03:13'),(46,'REGRA INDIQUE E GANHE','PROMOÇÃO INDIQUE E GANHE: DESCONTO OU PIX – VOCÊ ESCOLHE!\n\n✅ R$ 30,00 de desconto na mensalidade do plano de internet OU\n✅ R$ 30,00 via PIX transferidos para sua conta.\n\n\n✔️ Regras:\n\n1.    A promoção é válida para clientes ativos e adimplentes;\n2.    O desconto na mensalidade poderá ser aplicado na próxima fatura até a data do seu vencimento;\n3.    O pagamento via PIX será realizado em até 2 dias úteis após a solicitação*;\n4.    A conta destino do PIX deve ser a mesma do titular da assinatura;\n5.    A promoção é limitada a 1 utilização por cliente;\n6.    Para participar da oferta, o cliente e a pessoa indicada devem entrar em contato pelo WhatsApp da empresa e informar nomes e/ou CPF’s completos dos participantes, compreendendo que a instalação do indicado(a) que esteja sido realizada.\n\nREFORÇANDO O ENTENDIMENTO: O pagamento da indicação só será realizado após a instalação do serviço.\n\nSKYNET FIBRA sempre pensando em você!\n\n(71) 3016-6666 e (71) 98790-8777','2025-02-27 12:36:55','2025-08-29 09:56:19'),(47,'TERMO MUDANÇA DE ENDEREÇO','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*!\n\n\n*TERMO DE SERVIÇO – MUDANÇA DE ENDEREÇO*\n\nEste termo estabelece as condições para a solicitação e execução do serviço de *mudança de endereço* do plano de internet contratado junto à SKYNET FIBRA.\n\n*1. VALOR E PAGAMENTO*\n•	O custo da mudança de endereço é de *R$ 50,00 para cada ponto do endereço residencial e R$150 para cada ponto do endereço comercial*, e referem-se à mão de obra e materiais necessários para a reinstalação.\n•	O pagamento deverá ser *efetuado com antecedência ao serviço*, por PIX ou em espécie, sendo em espécie, o pagamento pode ser feito em nossa loja.\n\n*2. CONDIÇÕES PARA A MUDANÇA*\n•	O novo endereço deve estar dentro da *área de cobertura* da SKYNET FIBRA.\n•	A mudança está sujeita à *viabilidade técnica*, podendo ser necessário agendamento para avaliação.\n•	O titular da conta deve estar *em dia com os pagamentos* para que o serviço seja realizado.\n\n*3. PRAZO PARA EXECUÇÃO*\nO prazo para execução do serviço será de *até 2 dias úteis*, a partir da confirmação do pagamento e da disponibilidade técnica.\n\n*4. RESPONSABILIDADES DO CLIENTE*\n•	Informar corretamente o novo endereço e disponibilizar acesso ao local no dia agendado.\n•	Providenciar infraestrutura adequada, como pontos elétricos e espaço para instalação do equipamento.\n\n*5. CONSIDERAÇÕES FINAIS*\n•	Em caso de impossibilidade técnica para a mudança, o valor pago será *reembolsado integralmente*.\n•	Este serviço *não altera as condições do plano contratado*, apenas transfere a conexão para outro endereço.\n•	*Ao confirmar o serviço*, o cliente declara estar ciente e de acordo com os termos descritos acima.\n\nAgrademos sua compreensão.\n\nSKYNET FIBRA\n(71) 3016-6666 ou (71)98790-8777\nskynetfibra.net.br\n','2025-02-28 10:32:49','2025-08-18 15:59:23'),(48,'ALTERAR TITULARIDADE','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*!\n\n\nAbaixo *informações necessárias* para alteração de titularidade:\n\n*CONFIRMAÇÃO DO TITULAR ATUAL*\n\n✅ O titular atual deve entrar em contato com a nossa central através desse WhatsApp *solicitando alteração de titularidade*, confirmando o nome completo do novo responsável pela assinatura.\n\n*TERMO E CONDIÇÕES DO NOVO TITULAR*\n\n✅ Realizar o cadastro em nosso site. \n✅ Nos contatar pelo WhatsApp para seguimos com o processo de alteração.\n✅ Enviar fotos do documento de identificação pessoal e selfie com o mesmo documento.\n✅ Enviar um e-mail válido.\n✅ Assinatura do contrato de prestação de serviço e comodato.\n\n➡️ Site: https://skynetfibra.net.br/cadastro.hhvm\n➡️ WhatsApp: (71)98790-8777\n\n✔️ Será feito abertura de chamado para alteração de titularidade e o prazo para este serviço é de 1(um) dia útil.\n\n❗ *Importante*: A alteração de titularidade implica que o novo titular assume todas as responsabilidades financeiras e contratuais do serviço. \n\n\n\n✅ Priorizamos sua privacidade e segurança. A Lei Geral de Proteção de Dados (LGPD) assegura que seus dados pessoais sejam tratados com segurança e transparência. As informações que você compartilha conosco, como nome, CPF, foto e endereço são protegidas e utilizadas exclusivamente para a prestação de nossos serviços, nunca sendo compartilhadas sem sua autorização.\n\n\nSKYNET FIBRA\n(71) 3016-6666 e (71) 98790-8777\nskynetfibra.net.br','2025-04-02 14:25:39','2025-07-07 16:53:22'),(49,'RASTREAMENTO VEICULAR','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*! \n\n*RASTREAMENTO VEICULAR COM BLOQUEIO:*\n\nProteja seu veículo 24 horas por dia com nosso moderno *Sistema de Rastreamento e Bloqueio Veicular.* Com ele, você tem total controle sobre o seu carro, moto ou caminhão diretamente no seu celular.\n\n*Vantagens do nosso sistema:*\n\n✅ Localiza seu veículo em tempo real\n✅ Função de bloqueio remoto via aplicativo\n✅ Histórico de trajetos percorridos\n✅ Alerta de movimentação e velocidade\n✅ Monitoramento 100% online\n✅ Aplicativo disponível para *Android e iOS*\n✅ Suporte técnico especializado\n\n*Investimento acessível para sua segurança:*\n\n✔️ *Mensalidade:* R$ 20,00 para clientes da base SKYNET FIBRA.\n✔️ *Taxa de instalação:* R$100\n✔️ *Equipamento GPS:* R$ 130,00 (pagamento único no PIX, boleto ou cartão)\n\n🚗🚚🏍 Garanta agora mesmo a proteção do seu veículo com a *SKYNET FIBRA*! \n\n📞 *Fale conosco e instale já!\n','2025-04-02 14:28:09','2025-05-23 16:00:13'),(50,'LINK DEDICADO','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA!*\n\nO link dedicado da SKYNET FIBRA é uma solução de internet que oferece conexão exclusa e estável e de alta performance.\n\n✔️ *Principais Benefícios*:\n\n✅ *Velocidade Garantida* – Sem quedas ou variações.\n✅ *Conexão Simétrica* – Upload e download na mesma velocidade.\n✅ *Suporte Prioritário* – Atendimento técnico com SLA de *6h*.\n✅ *Escalabilidade* – Expansível conforme o crescimento do seu negócio.\n✅ *Baixa Latência* – Apenas *90ms*, ideal para videoconferências e jogos.\n✅ *Ideal para Empresas* – Suporta múltiplos acessos sem perda de qualidade.\n✅ *Estabilidade Total* – Link exclusivo, sem compartilhamento.\n\n\n*Velocidade a partir de 100megas ou conforme necessidade*. \n\n\n✔️ Peça já uma proposta personalizada para você. \n\n\nSKYNET FIBRA\n(71) 3016-6666 e (71) 98790-8777\nskynetfibra.net.br\n','2025-04-02 14:37:16','2025-04-02 14:37:16'),(51,'APÓS VER PLANOS','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*!\n\nVimos que você deu uma olhada em nossos planos e soluções. Que tal aproveitar toda essa ultravelocidade com estabilidade de verdade, além de extras incríveis como:\n\n✅ Telefone fixo ilimitado\n✅ Plataforma de canais ao vivo\n✅ Telemedicina para sua saúde\n✅ Rastreador veicular com aplicativo em tempo real\n\n💥 Temos planos a partir de R$59,99 com instalação rápida, equipamentos em comodato e suporte técnico de qualidade.\n\n📍 Verificamos a cobertura da sua região em minutos!\n🔗 Faça seu cadastro agora e damos prioridade no atendimento:\n👉 skynetfibra.net.br/cadastro.hhvm\n\nQualquer dúvida, estamos por aqui no WhatsApp!\n\n💬 Responda esta mensagem e vamos te ajudar a escolher o melhor plano! 😉\n\n','2025-05-04 17:58:00','2025-05-23 16:31:13'),(52,'APP CDN TV','*SKYNET FIBRA: SEU PROVEDOR DE CONFIANÇA*! \n\n📺 Aproveite agora a programação AO VIVO com a CDN TV Play!\nAssista onde e quando quiser, direto do seu celular, tablet ou smart TV!\n\n✅ Disponível para Android e iOS\n✅ Acesso fácil em vários dispositivos\n✅ Só precisa de conexão com a internet!\n\n*COMO ACESSAR*:\n1️⃣ Baixe o app CDN TV na loja de aplicativos do seu dispositivo\n2️⃣ No campo *URL*, digite: 4Streamtv.com\n3️⃣ No campo *Usuário*, digite: seu primeiro nome + os 4 ou 5 primeiros dígitos do seu CPF/CNPJ\n4️⃣ No campo *Senha*, digite: 1020\n\n🎉 Aproveite o melhor da programação ao vivo com a qualidade da SKYNET FIBRA!\n\n⚠️ *Importante*: Verifique se seu dispositivo é compatível com a plataforma.\n','2025-05-23 11:20:59','2025-07-11 16:17:30'),(53,'ENVIO DE NUMERO VOIP','Olá! \n\n☎️ O número do seu novo contato fixo é: (71) 0000-0000\n\nCom ele, você pode fazer ligações ilimitadas para qualquer telefone fixo ou celular em qualquer lugar do Brasil.\n\n🤝 Agradecemos a preferência. \n\nSKYNET FIBRA\nskynetfibra.net.br\n(71) 3016-6666','2025-08-28 15:41:35','2025-08-28 15:41:35');
/*!40000 ALTER TABLE `QuickAnswers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Rotinas`
--

DROP TABLE IF EXISTS `Rotinas`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Rotinas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `destinatario` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `mensagem` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `dia_mes` int NOT NULL,
  `hora` time NOT NULL,
  `ativa` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Rotinas`
--

LOCK TABLES `Rotinas` WRITE;
/*!40000 ALTER TABLE `Rotinas` DISABLE KEYS */;
INSERT INTO `Rotinas` VALUES (5,'71987908777, 71991114010 , 71988718872, 71988195752','Prezados colaboradores,\r\n\r\n❗ *Lembramos que é essencial*:\r\n\r\n✅ Visualizar o dashboard\r\n✅ Verifiquem as métricas e identificadores de qualidade de conexão\r\n✅ Monitorar quedas de conexão\r\n\r\n❗ *Se houver mais de 10 quedas em uma mesma conexão, sigam os próximos passos*:\r\n\r\n✅ Enviar mensagem: Entre em contato com os clientes afetados informando sobre o acompanhamento do problema\r\n✅ Ligar para o cliente: Confirme se há dificuldades percebidas na conexão e ofereça suporte imediato\r\n✅ Solicitar manutenção preventiva: Caso necessário, agende o envio de um técnico para solucionar possíveis falhas\r\n\r\n🤝 A colaboração de todos é essencial para garantir a satisfação e fidelidade de nossos clientes.',0,'10:00:00',0),(6,'71987908777, 71991114010 , 71988718872, 71988195752','Prezados colaboradores,\r\n\r\n❗ *Lembramos que é essencial*:\r\n\r\n✅ Visualizar o dashboard\r\n✅ Verifiquem as métricas e identificadores de qualidade de conexão\r\n✅ Monitorar quedas de conexão\r\n\r\n❗ *Se houver mais de 10 quedas em uma mesma conexão, sigam os próximos passos*:\r\n\r\n✅ Enviar mensagem: Entre em contato com os clientes afetados informando sobre o acompanhamento do problema\r\n✅ Ligar para o cliente: Confirme se há dificuldades percebidas na conexão e ofereça suporte imediato\r\n✅ Solicitar manutenção preventiva: Caso necessário, agende o envio de um técnico para solucionar possíveis falhas\r\n\r\n🤝 A colaboração de todos é essencial para garantir a satisfação e fidelidade de nossos clientes.',0,'15:00:00',0),(10,'71988718872, 71991114010,  71988195752','Lembrete de envo de NF para os clientes. no dia 01.',1,'09:30:00',0),(13,'71987908777, 71991114010 , 71988718872, 71988195752','Verificar se as mensagens de cobrança com vencimento no dia 01 estão sendo entregues aos clientes.',1,'10:30:00',0),(14,'71987908777, 71991114010 , 71988718872, 71988195752','Verificar se as mensagens de cobrança com vencimento no dia 05 estão sendo entregues aos clientes.',5,'10:30:00',0),(15,'71988718872, 71991114010,  71988195752','Verificar se as mensagens de cobrança com vencimento no dia 10 estão sendo entregues aos clientes.',10,'10:30:00',0),(16,'71987908777, 71991114010 , 71988718872, 71988195752','Verificar se as mensagens de cobrança com vencimento no dia 17 estão sendo entregues aos clientes.',17,'14:30:00',0),(17,'71987908777, 71991114010 , 71988718872, 71988195752','Verificar se as mensagens de bloqueio estão sendo entregues aos clientes que venceu no dia 01',10,'14:30:00',0),(18,'71987908777, 71991114010 , 71988718872, 71988195752','Verificar se as mensagens de bloqueio estão sendo entregues aos clientes que venceu no dia 05',15,'14:30:00',0),(19,'71987908777, 71991114010 , 71988718872, 71988195752','Verificar se as mensagens de bloqueio estão sendo entregues aos clientes que venceu no dia 10',20,'14:40:00',0),(20,'71987908777, 71991114010 , 71988718872, 71988195752','Verificar se as mensagens de bloqueio estão sendo entregues aos clientes que venceu no dia 17',27,'14:30:00',0),(21,'71987908777, 71991114010 , 71988718872, 71988195752, 71981725940, 71992864267, 71991465657','Colaborador, não esquecer de registrar o horário de entrada. Favor desconsiderar dias de folga de domingos e feriados.',0,'08:30:00',0),(23,'71987908777, 71991114010 , 71988718872, 71988195752, 71981725940, 71992864267, 71991465657','Colaborador, não esquecer de registrar o horário de início do almoço. Favor desconsiderar dias de folga de domingos e feriados.',0,'12:00:00',0),(24,'71987908777, 71991114010 , 71988718872, 71988195752, 71981725940, 71992864267, 71991465657','Colaborador, não esquecer de registrar o horário de volta do almoço. Favor desconsiderar dias de folga de domingos e feriados.',0,'13:00:00',0),(25,'71987908777, 71991114010 , 71988718872, 71988195752, 71981725940, 71992864267, 71991465657','Colaborador, não esquecer de registrar o horário de saída do serviço. Favor desconsiderar dias de folga de domingos e feriados.',0,'17:30:00',0);
/*!40000 ALTER TABLE `Rotinas` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Rotinas_log`
--

DROP TABLE IF EXISTS `Rotinas_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Rotinas_log` (
  `id` int NOT NULL AUTO_INCREMENT,
  `rotina_id` int DEFAULT NULL,
  `destinatario` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `mensagem` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `data_envio` datetime DEFAULT NULL,
  `status_envio` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1735 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Rotinas_log`
--

LOCK TABLES `Rotinas_log` WRITE;
/*!40000 ALTER TABLE `Rotinas_log` DISABLE KEYS */;
/*!40000 ALTER TABLE `Rotinas_log` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Schedules`
--

DROP TABLE IF EXISTS `Schedules`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Schedules` (
  `id` int NOT NULL AUTO_INCREMENT,
  `body` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `sendAt` datetime DEFAULT NULL,
  `sentAt` datetime DEFAULT NULL,
  `contactId` int DEFAULT NULL,
  `ticketId` int DEFAULT NULL,
  `userId` int DEFAULT NULL,
  `companyId` int DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  `status` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `contactId` (`contactId`),
  KEY `ticketId` (`ticketId`),
  KEY `userId` (`userId`),
  KEY `companyId` (`companyId`),
  CONSTRAINT `Schedules_ibfk_1` FOREIGN KEY (`contactId`) REFERENCES `Contacts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `Schedules_ibfk_2` FOREIGN KEY (`ticketId`) REFERENCES `Tickets` (`id`) ON DELETE SET NULL ON UPDATE SET NULL,
  CONSTRAINT `Schedules_ibfk_3` FOREIGN KEY (`userId`) REFERENCES `Users` (`id`) ON DELETE SET NULL ON UPDATE SET NULL,
  CONSTRAINT `Schedules_ibfk_4` FOREIGN KEY (`companyId`) REFERENCES `Companies` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Schedules`
--

LOCK TABLES `Schedules` WRITE;
/*!40000 ALTER TABLE `Schedules` DISABLE KEYS */;
/*!40000 ALTER TABLE `Schedules` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `SequelizeMeta`
--

DROP TABLE IF EXISTS `SequelizeMeta`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `SequelizeMeta` (
  `name` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci NOT NULL,
  PRIMARY KEY (`name`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `SequelizeMeta`
--

LOCK TABLES `SequelizeMeta` WRITE;
/*!40000 ALTER TABLE `SequelizeMeta` DISABLE KEYS */;
INSERT INTO `SequelizeMeta` VALUES ('20200717133438-create-users.js'),('20200717144403-create-contacts.js'),('20200717145643-create-tickets.js'),('20200717151645-create-messages.js'),('20200717170223-create-whatsapps.js'),('20200723200315-create-contacts-custom-fields.js'),('20200723202116-add-email-field-to-contacts.js'),('20200730153237-remove-user-association-from-messages.js'),('20200730153545-add-fromMe-to-messages.js'),('20200813114236-change-ticket-lastMessage-column-type.js'),('20200901235509-add-profile-column-to-users.js'),('20200903215941-create-settings.js'),('20200904220257-add-name-to-whatsapp.js'),('20200906122228-add-name-default-field-to-whatsapp.js'),('20200906155658-add-whatsapp-field-to-tickets.js'),('20200919124112-update-default-column-name-on-whatsappp.js'),('20200927220708-add-isDeleted-column-to-messages.js'),('20200929145451-add-user-tokenVersion-column.js'),('20200930162323-add-isGroup-column-to-tickets.js'),('20200930194808-add-isGroup-column-to-contacts.js'),('20201004150008-add-contactId-column-to-messages.js'),('20201004155719-add-vcardContactId-column-to-messages.js'),('20201004955719-remove-vcardContactId-column-to-messages.js'),('20201026215410-add-retries-to-whatsapps.js'),('20201028124427-add-quoted-msg-to-messages.js'),('20210108001431-add-unreadMessages-to-tickets.js'),('20210108164404-create-queues.js'),('20210108164504-add-queueId-to-tickets.js'),('20210108174594-associate-whatsapp-queue.js'),('20210108204708-associate-users-queue.js'),('20210109192513-add-greetingMessage-to-whatsapp.js'),('20210109192514-create-companies-table.js'),('20210109192515-add-column-companyId-to-Settings-table.js'),('20210109192516-add-column-companyId-to-Users-table.js'),('20210109192517-add-column-companyId-to-Contacts-table.js'),('20210109192518-add-column-companyId-to-Messages-table.js'),('20210109192519-add-column-companyId-to-Queues-table.js'),('20210818102605-create-quickAnswers.js'),('20211016014719-add-farewellMessage-to-whatsapp.js'),('20211227010200-create-schedules.js'),('20220122160900-add-status-to-schedules.js'),('20220223095932-add-whatsapp-to-user.js'),('20220315110000-create-ContactLists-table.js'),('20220315110001-create-ContactListItems-table.js'),('20220315110002-create-Campaigns-table.js'),('20220315110004-create-CampaignSettings-table.js'),('20220321130000-create-CampaignShipping.js'),('20220406000000-add-column-dueDate-to-Companies.js'),('20220406000001-add-column-recurrence-to-Companies.js'),('20220619203200-add-startwork-queues.js'),('20220619203500-add-endwork-queues.js'),('20220619203900-add-absencemessage-queues.js'),('20220906150400-create-tags.js'),('20220906150600-create-associate-contacttags.js'),('20221012212600-add-startwork-users.js'),('20221012212700-add-endwork-users.js'),('20221023085500-add-isdisplay-to-whatsapp.js'),('20221128234000-add-number-to-whatsapp.js');
/*!40000 ALTER TABLE `SequelizeMeta` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Settings`
--

DROP TABLE IF EXISTS `Settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Settings` (
  `key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `value` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  `companyId` int DEFAULT NULL,
  PRIMARY KEY (`key`),
  KEY `Settings_companyId_foreign_idx` (`companyId`),
  CONSTRAINT `Settings_companyId_foreign_idx` FOREIGN KEY (`companyId`) REFERENCES `Companies` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Settings`
--

LOCK TABLES `Settings` WRITE;
/*!40000 ALTER TABLE `Settings` DISABLE KEYS */;
INSERT INTO `Settings` VALUES ('allTicket','disabled','2023-11-07 21:51:19','2023-11-07 21:51:19',NULL),('ASC','disabled','2023-11-07 21:51:19','2023-11-07 21:51:19',NULL),('call','disabled','2023-11-07 21:51:18','2023-11-07 21:51:18',NULL),('CheckMsgIsGroup','disabled','2023-11-07 21:51:18','2024-05-26 21:33:18',NULL),('closeTicketApi','enabled','2023-11-07 21:51:18','2023-11-07 22:02:30',NULL),('created','disabled','2023-11-07 21:51:20','2023-11-07 21:51:20',NULL),('darkMode','disabled','2023-11-07 21:51:18','2023-11-07 21:51:18',NULL),('sideMenu','disabled','2023-11-07 21:51:18','2023-11-07 22:02:22',NULL),('timeCreateNewTicket','10','2023-11-07 21:51:18','2023-11-07 21:51:18',NULL),('urlContrato','https://url.do.contrato/gerar.php','2023-11-07 21:51:18','2023-11-07 21:51:18',NULL),('urlPix','https://url.do.pix/gerar.php','2023-11-07 21:51:18','2023-11-07 21:51:18',NULL),('userApiToken','22f9292e-bce1-4de1-82f9-c447ee0cac20','2023-11-07 21:51:19','2023-11-07 21:51:19',NULL),('userCreation','enabled','2023-11-07 21:51:18','2023-11-07 21:51:18',NULL);
/*!40000 ALTER TABLE `Settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Tags`
--

DROP TABLE IF EXISTS `Tags`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Tags` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `color` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Tags`
--

LOCK TABLES `Tags` WRITE;
/*!40000 ALTER TABLE `Tags` DISABLE KEYS */;
/*!40000 ALTER TABLE `Tags` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `TextBot`
--

DROP TABLE IF EXISTS `TextBot`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `TextBot` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `nome` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `img` varchar(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `msg` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `data` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `TextBot`
--

LOCK TABLES `TextBot` WRITE;
/*!40000 ALTER TABLE `TextBot` DISABLE KEYS */;
/*!40000 ALTER TABLE `TextBot` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Tickets`
--

DROP TABLE IF EXISTS `Tickets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Tickets` (
  `id` int NOT NULL AUTO_INCREMENT,
  `status` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending',
  `lastMessage` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `contactId` int DEFAULT NULL,
  `userId` int DEFAULT '1',
  `createdAt` datetime(6) NOT NULL,
  `updatedAt` datetime(6) NOT NULL,
  `whatsappId` int DEFAULT NULL,
  `isGroup` tinyint(1) NOT NULL DEFAULT '0',
  `unreadMessages` int DEFAULT NULL,
  `queueId` int DEFAULT NULL,
  `liga_desliga_pix` int NOT NULL DEFAULT '2',
  PRIMARY KEY (`id`),
  KEY `contactId` (`contactId`),
  KEY `userId` (`userId`),
  KEY `Tickets_whatsappId_foreign_idx` (`whatsappId`),
  KEY `Tickets_queueId_foreign_idx` (`queueId`),
  CONSTRAINT `Tickets_ibfk_1` FOREIGN KEY (`contactId`) REFERENCES `Contacts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `Tickets_queueId_foreign_idx` FOREIGN KEY (`queueId`) REFERENCES `Queues` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `Tickets_whatsappId_foreign_idx` FOREIGN KEY (`whatsappId`) REFERENCES `Whatsapps` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=64667 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Tickets`
--

LOCK TABLES `Tickets` WRITE;
/*!40000 ALTER TABLE `Tickets` DISABLE KEYS */;
/*!40000 ALTER TABLE `Tickets` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `UserQueues`
--

DROP TABLE IF EXISTS `UserQueues`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `UserQueues` (
  `userId` int NOT NULL,
  `queueId` int NOT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`userId`,`queueId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `UserQueues`
--

LOCK TABLES `UserQueues` WRITE;
/*!40000 ALTER TABLE `UserQueues` DISABLE KEYS */;
INSERT INTO `UserQueues` VALUES (1,1,'2023-11-08 08:14:38','2023-11-08 08:14:38'),(1,2,'2023-11-08 08:14:38','2023-11-08 08:14:38'),(1,3,'2023-11-08 08:14:38','2023-11-08 08:14:38'),(2,1,'2025-06-30 09:58:08','2025-06-30 09:58:08'),(2,2,'2025-06-30 09:58:08','2025-06-30 09:58:08'),(2,3,'2025-06-30 09:58:08','2025-06-30 09:58:08'),(3,1,'2023-11-12 18:42:52','2023-11-12 18:42:52'),(3,2,'2023-11-12 18:42:52','2023-11-12 18:42:52'),(3,3,'2023-11-12 18:42:52','2023-11-12 18:42:52'),(4,1,'2024-05-23 12:14:19','2024-05-23 12:14:19'),(4,2,'2024-05-23 12:14:19','2024-05-23 12:14:19'),(4,3,'2024-05-23 12:14:19','2024-05-23 12:14:19'),(5,1,'2024-05-24 16:02:34','2024-05-24 16:02:34'),(5,2,'2024-05-24 16:02:34','2024-05-24 16:02:34'),(5,3,'2024-05-24 16:02:34','2024-05-24 16:02:34'),(6,1,'2024-05-26 21:36:43','2024-05-26 21:36:43'),(6,2,'2024-05-26 21:36:43','2024-05-26 21:36:43'),(6,3,'2024-05-26 21:36:43','2024-05-26 21:36:43'),(10,1,'2024-06-22 22:40:19','2024-06-22 22:40:19'),(10,2,'2024-06-22 22:40:19','2024-06-22 22:40:19'),(10,3,'2024-06-22 22:40:19','2024-06-22 22:40:19'),(11,1,'2024-07-02 01:37:08','2024-07-02 01:37:08'),(11,2,'2024-07-02 01:37:08','2024-07-02 01:37:08'),(11,3,'2024-07-02 01:37:08','2024-07-02 01:37:08'),(12,1,'2024-07-02 21:59:27','2024-07-02 21:59:27'),(12,2,'2024-07-02 21:59:27','2024-07-02 21:59:27'),(12,3,'2024-07-02 21:59:27','2024-07-02 21:59:27'),(13,1,'2024-07-03 11:10:56','2024-07-03 11:10:56'),(13,2,'2024-07-03 11:10:56','2024-07-03 11:10:56'),(13,3,'2024-07-03 11:10:56','2024-07-03 11:10:56'),(14,1,'2024-07-10 16:01:12','2024-07-10 16:01:12'),(14,2,'2024-07-10 16:01:12','2024-07-10 16:01:12'),(14,3,'2024-07-10 16:01:12','2024-07-10 16:01:12'),(15,1,'2024-08-07 11:05:29','2024-08-07 11:05:29'),(15,2,'2024-08-07 11:05:29','2024-08-07 11:05:29'),(15,3,'2024-08-07 11:05:29','2024-08-07 11:05:29'),(16,1,'2024-11-15 23:07:29','2024-11-15 23:07:29'),(16,2,'2024-11-15 23:07:29','2024-11-15 23:07:29'),(16,3,'2024-11-15 23:07:29','2024-11-15 23:07:29'),(17,1,'2024-11-17 12:19:16','2024-11-17 12:19:16'),(17,2,'2024-11-17 12:19:16','2024-11-17 12:19:16'),(17,3,'2024-11-17 12:19:16','2024-11-17 12:19:16'),(18,1,'2024-11-17 12:32:20','2024-11-17 12:32:20'),(18,2,'2024-11-17 12:32:20','2024-11-17 12:32:20'),(18,3,'2024-11-17 12:32:20','2024-11-17 12:32:20'),(19,1,'2024-11-18 13:59:40','2024-11-18 13:59:40'),(19,2,'2024-11-18 13:59:40','2024-11-18 13:59:40'),(19,3,'2024-11-18 13:59:40','2024-11-18 13:59:40'),(20,1,'2025-04-03 07:56:51','2025-04-03 07:56:51'),(20,2,'2025-04-03 07:56:51','2025-04-03 07:56:51'),(20,3,'2025-04-03 07:56:51','2025-04-03 07:56:51'),(21,1,'2025-04-07 16:00:52','2025-04-07 16:00:52'),(21,2,'2025-04-07 16:00:52','2025-04-07 16:00:52'),(21,3,'2025-04-07 16:00:52','2025-04-07 16:00:52'),(22,1,'2025-08-15 09:22:57','2025-08-15 09:22:57'),(22,2,'2025-08-15 09:22:57','2025-08-15 09:22:57'),(22,3,'2025-08-15 09:22:57','2025-08-15 09:22:57');
/*!40000 ALTER TABLE `UserQueues` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Users`
--

DROP TABLE IF EXISTS `Users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `passwordHash` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  `profile` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'admin',
  `tokenVersion` int NOT NULL DEFAULT '0',
  `whatsappId` int DEFAULT NULL,
  `startWork` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT '00:00',
  `endWork` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT '23:59',
  `companyId` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `Users_whatsappId_foreign_idx` (`whatsappId`),
  KEY `Users_companyId_foreign_idx` (`companyId`),
  CONSTRAINT `Users_companyId_foreign_idx` FOREIGN KEY (`companyId`) REFERENCES `Companies` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `Users_whatsappId_foreign_idx` FOREIGN KEY (`whatsappId`) REFERENCES `Whatsapps` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=23 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Users`
--

LOCK TABLES `Users` WRITE;
/*!40000 ALTER TABLE `Users` DISABLE KEYS */;
INSERT INTO `Users` VALUES (2,'BOT','bot@dctsistemas.com','$2a$08$lev8EB3JGdWBB9u5ME/9SONQN4Yu5EzbwN8XcWaf75tlUKRjGDqBW','2023-11-12 18:42:52','2025-06-30 09:58:08','user',0,NULL,'','',NULL),(12,'Adriana','adrianaskynetfibra@gmail.com','$2a$08$sYoKs4hXW5uOiyXec3zWIePsT3VCgaONAe6t7JUlBdMx0tNfdtWKy','2024-07-02 21:59:27','2024-11-28 10:28:34','admin',0,NULL,'00:00','23:59',NULL),(14,'Anderson','anderson@skynetfibra.net.br','$2a$08$i3n3dnQmLgGmHh.2TINvrOjJq0/pXh.nqx6GBkFs5QL8IZLWdAJsO','2024-07-10 16:01:12','2025-05-28 16:50:36','admin',0,NULL,'00:00','23:59',NULL),(19,'Yasmin','yasmin@skynetfibra.net.br','$2a$08$bj0Mgt1SJkPzzhlsXIC3ku9PFpeFbc7VfMlPv/Ce6fL/v8WQr0HRa','2024-11-18 13:59:40','2025-04-07 13:37:30','admin',0,NULL,'00:00','23:59',NULL),(20,'Alisson','alisson@skynetfibra.net.br','$2a$08$kj4p5ICh5jFVt0W4v4vWQe9qjfxvrJJ.a.DfEYyKZ36lXddRJzV2e','2025-04-03 07:56:32','2025-04-03 07:56:51','admin',0,NULL,'00:00','23:59',NULL),(21,'Suporte Técnico','alexandro@skynetfibra.net.br','$2a$08$FK7uWJ8n870FWWzez.6qmOmyEl/1UBI33FXk3Z4VGF01EzTorOlnm','2025-04-07 16:00:52','2025-04-07 16:00:52','admin',0,NULL,'00:00','23:59',NULL),(22,'Stefane','stefaneskynet@GMAIL.COM','$2a$08$EuKBZSwImCKUU1d9ESH5J.Y/aefTZz.jH7ygOxBQzCfKrb8MjV0WO','2025-08-15 09:22:57','2025-08-15 09:23:07','admin',0,NULL,'00:00','23:59',NULL);
/*!40000 ALTER TABLE `Users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `WhatsappQueues`
--

DROP TABLE IF EXISTS `WhatsappQueues`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `WhatsappQueues` (
  `whatsappId` int NOT NULL,
  `queueId` int NOT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  PRIMARY KEY (`whatsappId`,`queueId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `WhatsappQueues`
--

LOCK TABLES `WhatsappQueues` WRITE;
/*!40000 ALTER TABLE `WhatsappQueues` DISABLE KEYS */;
INSERT INTO `WhatsappQueues` VALUES (72,1,'2025-08-15 07:38:31','2025-08-15 07:38:31'),(72,2,'2025-08-15 07:38:31','2025-08-15 07:38:31'),(72,3,'2025-08-15 07:38:31','2025-08-15 07:38:31');
/*!40000 ALTER TABLE `WhatsappQueues` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `Whatsapps`
--

DROP TABLE IF EXISTS `Whatsapps`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `Whatsapps` (
  `id` int NOT NULL AUTO_INCREMENT,
  `session` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `qrcode` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `status` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `battery` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `plugged` tinyint(1) DEFAULT NULL,
  `createdAt` datetime NOT NULL,
  `updatedAt` datetime NOT NULL,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `isDefault` tinyint(1) NOT NULL DEFAULT '0',
  `retries` int NOT NULL DEFAULT '0',
  `greetingMessage` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `farewellMessage` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `isDisplay` tinyint(1) NOT NULL DEFAULT '0',
  `number` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=94 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `Whatsapps`
--

LOCK TABLES `Whatsapps` WRITE;
/*!40000 ALTER TABLE `Whatsapps` DISABLE KEYS */;
/*!40000 ALTER TABLE `Whatsapps` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `mensagens_agendadas`
--

DROP TABLE IF EXISTS `mensagens_agendadas`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mensagens_agendadas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `contactId` int NOT NULL,
  `descricao` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('pendente','enviado','cancelado') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'pendente',
  `createdAt` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `data_envio` datetime NOT NULL,
  `ticketId` int DEFAULT NULL,
  `number` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `contactId` (`contactId`),
  KEY `ticketId` (`ticketId`),
  CONSTRAINT `mensagens_agendadas_ibfk_1` FOREIGN KEY (`contactId`) REFERENCES `Contacts` (`id`) ON DELETE CASCADE,
  CONSTRAINT `mensagens_agendadas_ibfk_2` FOREIGN KEY (`ticketId`) REFERENCES `Tickets` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=295 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `mensagens_agendadas`
--

LOCK TABLES `mensagens_agendadas` WRITE;
/*!40000 ALTER TABLE `mensagens_agendadas` DISABLE KEYS */;
/*!40000 ALTER TABLE `mensagens_agendadas` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `respostas`
--

DROP TABLE IF EXISTS `respostas`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `respostas` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `nome` varchar(50) NOT NULL,
  `img` varchar(300) DEFAULT NULL,
  `msg` varchar(2000) NOT NULL,
  `data` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=18 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `respostas`
--

LOCK TABLES `respostas` WRITE;
/*!40000 ALTER TABLE `respostas` DISABLE KEYS */;
INSERT INTO `respostas` VALUES (1,'INICIO','https://skynetfibra.net.br/ura/images/LOGO.jpg','Meu nome é *Heitor*, agente virtual da *SkyNet Fibra*.\n\nPara iniciar-mos, precisamos de algumas informações, ok? ☺️\n\nDigite o número da opção que corresponde ao seu perfil:\n\n1️⃣  *Sou Cliente*\n2️⃣  *Planos*','2020-07-09 07:01:28'),(2,'INICIO-S-IMG','','Opção inválida\n\nDigite o número da opção que corresponde ao seu perfil:\n\n1️⃣  *Sou Cliente*\n2️⃣  *Planos*','2020-07-09 07:01:28'),(3,'SEM-ATENDIMENTO','','_No momento não consigo te transferir_. \n\n*Nosso horário de atendimento é de Segunda à Sábado das 09:00h às 18:00Hs.*\n\nSe desejar fazer um cadastro clique no Link Abaixo...\n\nhttps://turbonet.rbfull.com.br/central/assinar\n\nAtenciosamente,\n*SkyNet Fibra*','2020-07-09 07:01:28'),(4,'INFORMA-CPF','','Agora, Digite todos os números do seu CPF ou CNPJ','2020-07-09 07:01:28'),(5,'INFORMA-CPF-INVALIDO-1','','Poxa! O documento  que você me informou está incorreto. ☹️ \n\nDigite novamente todos os números do seu CPF ou CNPJ','2020-07-09 07:01:28'),(6,'INFORMA-CPF-INVALIDO-2','','Olha... ainda não entendi o documento informado ☹️ \n\nPor favor, me envia todos os números do seu CPF ou CNPJ','2020-07-09 07:01:28'),(7,'INFORMA-CPF-INVALIDO-FIM','','Poxa! O nosso atendimento está sendo encerrado, pois você não me informou um documento válido ☹️\r\n\r\nMas não se preocupe, você pode entrar em contato novamente por este canal\r\n\r\nSempre que precisar é só me chamar. Tchau tchau!','2020-07-09 07:01:28'),(8,'FINALIZAR','','A equipe *SkyNet Fibra* agradece pelo seu contato!\nSempre que precisar estaremos aqui. Tchau tchau! ???? ????','2020-07-09 07:01:28'),(9,'TRANSFERINDO','','Só um instante que estou te direcionando para o Setor Responsável','2020-07-09 07:01:28'),(10,'COM-FATURA','','Segue abaixo a Segunda Via da sua Fatura....\n\nCaso seu *boleto* esteja em branco, favor pedir para falar com a *atendente.*','2020-07-09 07:01:28'),(11,'SEM-FATURA','','Voce nao possue faturas em aberto!!!','2020-07-09 07:01:28'),(12,'INFO-DESBLOQUEIO-NEGADO','','Não é possível realizar essa *Operação*...','2020-07-09 07:01:28'),(13,'SEM-ATENDIMENTO-COM','','_Será um prazer ter você como nosso cliente_. De momento estamos fora do horário de atendimento.\n\n*Nosso horário de atendimento é de Segunda à Sábado das 09:00h às 18:00Hs.*\n\nPara se tornar nosso cliente a qualquer momento, acessando:\nhttps://turbonet.rbfull.com.br/central/assinar\n\nAtenciosamente,\n*SkyNet Fibra*','2020-07-09 07:01:28'),(16,'PLANOS',NULL,'Planos em fibra óptica, pós-pago + fixo ilimitado: )\n\n➡ 60Mega: R$59,99\n➡ 60Mega+Fixo: R$74,99\n➡ 100Mega: R$69,99 \n➡ 150Mega: R$79,99 \n➡ 150Mega+Fixo: R$89,99 \n➡ 250Mega: R$89,99 \n➡ 250Mega+Fixo: R$99,99 \n➡ 300Mega+Fixo: R$109,99 \n➡ 300_Mega_Fixo+Tv Parmount : R$119,99\n\n✅ TELEFONE FIXO ILIMITADO\n✅ MAIOR ESTABILIDADE \n✅ ULTRAVELOCIDADE \n\nInstalação: \n\nCom equipamento(s) em comodato(s) e taxa única paga no ato já incluso a ativação do telefone fixo; \n\n- Haverá taxa de migração para clientes de base. Favor consultar. \n- Consulte cobertura em sua área. \n- Para ativação do telefone fixo é necessário ter aparelho próprio. \n- A taxa de instalação ou migração é paga no ato e não reembolsável. \n\nFaça seu cadastro através do nosso site: \n\nhttps://skynetfibra.net.br/cadastro.hhvm ','2023-11-11 06:41:53'),(17,'MENU-INFO-CONTRATOS',NULL,'encontramos 2 contratos','2025-04-25 01:20:34');
/*!40000 ALTER TABLE `respostas` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2025-08-31 18:01:57
