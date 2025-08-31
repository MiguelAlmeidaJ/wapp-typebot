import React, { useContext, useEffect, useState } from "react";
import { Link as RouterLink } from "react-router-dom";
import ListItem from "@material-ui/core/ListItem";
import ListItemIcon from "@material-ui/core/ListItemIcon";
import ListItemText from "@material-ui/core/ListItemText";
import ListSubheader from "@material-ui/core/ListSubheader";
import Divider from "@material-ui/core/Divider";
import { Badge, Menu, MenuItem } from "@material-ui/core";
import DashboardOutlinedIcon from "@material-ui/icons/DashboardOutlined";
import SyncAltIcon from "@material-ui/icons/SyncAlt";
import PeopleAltOutlinedIcon from "@material-ui/icons/PeopleAltOutlined";
import ContactPhoneOutlinedIcon from "@material-ui/icons/ContactPhoneOutlined";
import AccountTreeOutlinedIcon from "@material-ui/icons/AccountTreeOutlined";
import QuestionAnswerOutlinedIcon from "@material-ui/icons/QuestionAnswerOutlined";
import { i18n } from "../translate/i18n";
import { WhatsAppsContext } from "../context/WhatsApp/WhatsAppsContext";
import { AuthContext } from "../context/Auth/AuthContext";
import { Can } from "../components/Can";
import { ReactComponent as PixIcon } from '../icons/PixIcon-32.svg';
import { ReactComponent as WhatsIcon } from '../icons/WhatsappIcon-32.svg';
import { ReactComponent as ContactIcon } from '../icons/ContactIcon-32.svg';
import { ReactComponent as RespostasRapidasIcon } from '../icons/RespostasRapidasIcon-32.svg';
import { ReactComponent as DashboardIcon } from '../icons/DashboardIcon-32.svg';
import { ReactComponent as ConexaoIcon } from '../icons/ConexaoIcon-32.svg';
import { ReactComponent as UsiariosIcon } from '../icons/UsuariosIcon-32.svg';
import { ReactComponent as FilasIcon } from '../icons/FilasIcon-32.svg';
import { ReactComponent as AudioBotIcon } from '../icons/AudioBotIcon-32.svg';
import { ReactComponent as RelatorioIcon } from '../icons/RelatorioIcon-32.svg';
import { ReactComponent as AjustesIcon } from '../icons/AjustesIcon-32.svg';
import { ReactComponent as ContratoIcon } from '../icons/ContratoIcon-32.svg';
import { ReactComponent as RotinaIcon } from '../icons/RotinaIcon-32.svg';
import { ReactComponent as RotinaLogIcon } from '../icons/RotinaLogIcon-32.svg';

function ListItemLink(props) {
  const { icon, primary, to, className } = props;

  const renderLink = React.useMemo(
    () =>
      React.forwardRef((itemProps, ref) => (
        <RouterLink to={to} ref={ref} {...itemProps} />
      )),
    [to]
  );

  return (
    <li>
      <ListItem button component={renderLink} className={className}>
        {icon ? <ListItemIcon>{icon}</ListItemIcon> : null}
        <ListItemText primary={primary} />
      </ListItem>
    </li>
  );
}

const MainListItems = (props) => {
  const { drawerClose } = props;
  const { whatsApps } = useContext(WhatsAppsContext);
  const { user } = useContext(AuthContext);
  const [connectionWarning, setConnectionWarning] = useState(false);
  const [submenuAnchorEl, setSubmenuAnchorEl] = useState(null);

  useEffect(() => {
    const delayDebounceFn = setTimeout(() => {
      if (whatsApps.length > 0) {
        const offlineWhats = whatsApps.filter((whats) => {
          return (
            whats.status === "qrcode" ||
            whats.status === "PAIRING" ||
            whats.status === "DISCONNECTED" ||
            whats.status === "TIMEOUT" ||
            whats.status === "OPENING"
          );
        });
        if (offlineWhats.length > 0) {
          setConnectionWarning(true);
        } else {
          setConnectionWarning(false);
        }
      }
    }, 2000);
    return () => clearTimeout(delayDebounceFn);
  }, [whatsApps]);

  const handleSubmenuOpen = (event) => {
    setSubmenuAnchorEl(event.currentTarget);
  };

  const handleSubmenuClose = () => {
    setSubmenuAnchorEl(null);
  };

  return (
    <div onClick={drawerClose}>
      <ListItemLink
        to="/tickets"
        primary={i18n.t("mainDrawer.listItems.tickets")}
        icon={<WhatsIcon />}
      />

      <ListItemLink
        to="/contacts"
        primary={i18n.t("Contatos")}
        icon={<ContactIcon />}
      />

      <ListItemLink
        to="/quickanswers"
        primary={i18n.t("Respostas Rapidas")}
        icon={<RespostasRapidasIcon />}
      />

      {/* Seção Relatórios */}
      <Divider />
      
      <ListItemLink
        to="/Contratos"
        primary={i18n.t("Contratos")}
        icon={<ContratoIcon />}
      />

      <ListItemLink
        to="/Pix"
        primary={i18n.t("PIX")}
        icon={<PixIcon />}
      />

      <ListItemLink
        to="/Disparos"
        primary={i18n.t("Disparos")}
        icon={<RelatorioIcon />}
      />

      <ListItemLink
        to="/RotinasLog"
        primary={i18n.t("Rotinas")}
        icon={<RotinaLogIcon />}
      />

      {/* Seção Administração */}
      <Can
        role={user.profile}
        perform="drawer-admin-items:view"
        yes={() => (
          <>
            <Divider />
            <ListItemLink
              to="/Dashboard"
              primary={i18n.t("mainDrawer.listItems.dashboard")}
              icon={<DashboardIcon />}
            />

            <ListItemLink
              to="/AudioBot"
              primary={i18n.t("Audio BOT")}
              icon={<AudioBotIcon />}
            />

            <ListItemLink
              to="/ChatBot"
              primary={i18n.t("Chat BOT")}
              icon={<AudioBotIcon />}
            />

            <ListItemLink
              to="/connections"
              primary={i18n.t("mainDrawer.listItems.connections")}
              icon={
                <Badge badgeContent={connectionWarning ? "!" : 0} color="error">
                  <ConexaoIcon />
                </Badge>
              }
            />

            <ListItemLink
              to="/users"
              primary={i18n.t("mainDrawer.listItems.users")}
              icon={<UsiariosIcon />}
            />

            <ListItemLink
              to="/queues"
              primary={i18n.t("mainDrawer.listItems.queues")}
              icon={<FilasIcon />}
            />

            <ListItemLink
              to="/Rotinas"
              primary={i18n.t("Gerenciar Rotinas")}
              icon={<RotinaIcon />}
            />

            <ListItemLink
              to="/Ajustes"
              primary={i18n.t("Ajustes")}
              icon={<AjustesIcon />}
            />
          </>
        )}
      />
    </div>
  );
};

export default MainListItems;

