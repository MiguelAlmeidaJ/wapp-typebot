import React, { useContext, useState } from "react";
import { useHistory } from "react-router-dom";
import { makeStyles } from "@material-ui/core/styles";
import { Tooltip } from "@material-ui/core";
import { Box } from '@mui/material';
import MonetizationOnIcon from '@mui/icons-material/MonetizationOn'; // Ícone do PIX
import ScheduleIcon from '@mui/icons-material/Schedule'; // Ícone de agendar
import DescriptionIcon from '@mui/icons-material/Description'; // Ícone de contrato
import CallEndIcon from '@mui/icons-material/CallEnd'; // Ícone de finalizar atendimento
import SwapHorizIcon from '@mui/icons-material/SwapHoriz'; // Ícone de transferência
import ButtonWithSpinner from "../ButtonWithSpinner";
import { AuthContext } from "../../context/Auth/AuthContext";
import FinanceiroTicketModal from "../FinanceiroTicketModal";
import ContratoTicketModal from "../ContratoTicketModal";
import AgendamentoTicketModal from "../AgendamentoTicketModal"; // Atualize o caminho
import TransferTicketModal from "../TransferTicketModal"; // Importa o modal de transferência
import toastError from "../../errors/toastError";
import api from "../../services/api";

const useStyles = makeStyles(theme => ({
    actionButtons: {
        marginRight: 6,
        flex: "none",
        alignSelf: "center",
        marginLeft: "auto",
        "& > *": {
            margin: theme.spacing(1),
        },
    },
}));

const TicketActionButtons = ({ ticket, handleClose, isMounted }) => {
    const [financeiroTicketModalOpen, setFinanceiroTicketModalOpen] = useState(false);
    const [contratoTicketModalOpen, setContratoTicketModalOpen] = useState(false); // Estado do modal de contrato
    const [agendamentoTicketModalOpen, setAgendamentoTicketModalOpen] = useState(false); // Estado para o novo modal
    const [transferTicketModalOpen, setTransferTicketModalOpen] = useState(false); // Estado para o modal de transferência

    const classes = useStyles();
    const history = useHistory();
    const [loading, setLoading] = useState(false);
    const { user } = useContext(AuthContext);

    const handleUpdateTicketStatus = async (e, status, userId) => {
        setLoading(true);
        try {
            await api.put(`/tickets/${ticket.id}`, {
                status: status,
                userId: userId || null,
            });

            setLoading(false);
            if (status === "open") {
                history.push(`/tickets/${ticket.id}`);
            } else {
                history.push("/tickets");
            }
        } catch (err) {
            setLoading(false);
            toastError(err);
        }
    };

    // Função para abrir modal de contrato
    const handleOpenContratoTicketModal = () => {
        setContratoTicketModalOpen(true);
    };

    // Função para fechar modal de contrato
    const handleCloseContratoTicketModal = () => {
        setContratoTicketModalOpen(false);
    };


    const buttonStyle = {
        minWidth: '48px',
        width: '30px',
        height: '48px',
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        borderRadius: '8px',
        backgroundColor: 'rgb(123 175 203)', // Cor do botão
        cursor: 'pointer',
        border: '1px solid #ccc', // Borda sutil
        transition: 'all 0.3s ease', // Efeito suave para transição
        '&:hover': {
          backgroundColor: 'info.dark', // Cor de fundo ao passar o mouse
          boxShadow: '0px 4px 12px rgba(0, 0, 0, 0.1)', // Efeito de sombra
          transform: 'scale(1.1)', // Efeito de aumentar um pouco ao passar o mouse
        },
        '&:active': {
          transform: 'scale(0.98)', // Efeito ao clicar no botão
        },
      };
      
      const iconStyle = {
        fontSize: '27px', // Aumenta o tamanho do ícone
        color: 'white',
      };
      
      const buttonContainerStyle = {
        display: 'flex',        // Torna o container flexível
        justifyContent: 'space-around', // Distribui os botões igualmente
        gap: '8px',             // Adiciona espaço entre os botões
        alignItems: 'center',   // Alinha os itens verticalmente no centro
        flexWrap: 'nowrap',     // Impede que os itens quebrem para a linha de baixo
      };
      

    return (
        <div className={classes.actionButtons}>
            {ticket.status === "open" && !ticket.isGroup && (
                <>
<Box sx={buttonContainerStyle}>
  <Tooltip title="Gerar PIX" arrow>
    <Box onClick={() => setFinanceiroTicketModalOpen(true)} sx={buttonStyle}>
      <MonetizationOnIcon sx={iconStyle} />
    </Box>
  </Tooltip>

  <Tooltip title="Agendar Mensagem" arrow>
    <Box onClick={() => setAgendamentoTicketModalOpen(true)} sx={buttonStyle}>
      <ScheduleIcon sx={iconStyle} />
    </Box>
  </Tooltip>

  <Tooltip title="Gerar Contrato" arrow>
    <Box onClick={handleOpenContratoTicketModal} sx={buttonStyle}>
      <DescriptionIcon sx={iconStyle} />
    </Box>
  </Tooltip>

  <Tooltip title="Transferir Atendimento" arrow>
    <Box onClick={() => setTransferTicketModalOpen(true)} sx={buttonStyle}>
      <SwapHorizIcon sx={iconStyle} />
    </Box>
  </Tooltip>

  <Tooltip title="Finalizar Atendimento" arrow>
    <Box onClick={e => handleUpdateTicketStatus(e, "closed", user?.id)} sx={buttonStyle}>
      <CallEndIcon sx={iconStyle} />
    </Box>
  </Tooltip>
</Box>
                    {/* Modais */}
                    <AgendamentoTicketModal
                        modalOpen={agendamentoTicketModalOpen}
                        onClose={() => setAgendamentoTicketModalOpen(false)}
                        ticketid={ticket.id}
                    />
                    <FinanceiroTicketModal
                        modalOpen={financeiroTicketModalOpen}
                        onClose={() => setFinanceiroTicketModalOpen(false)}
                        ticketid={ticket.id}
                    />
                    <ContratoTicketModal
                        modalOpen={contratoTicketModalOpen} // Verifica se o modal de contrato está aberto
                        onClose={handleCloseContratoTicketModal} // Função para fechar o modal de contrato
                        ticketid={ticket.id}
                    />
                    <TransferTicketModal
                        modalOpen={transferTicketModalOpen}
                        onClose={() => setTransferTicketModalOpen(false)}
                        ticketid={ticket.id}
                    />
                </>
            )}
        </div>
    );
};

export default TicketActionButtons;
