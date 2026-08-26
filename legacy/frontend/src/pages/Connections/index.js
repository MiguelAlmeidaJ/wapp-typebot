// src/pages/Connections/index.js
import React, { useState, useCallback, useContext } from "react";
import { toast } from "react-toastify";
import { format, parseISO } from "date-fns";

import { makeStyles } from "@material-ui/core/styles";
import { green, red, grey } from "@material-ui/core/colors";
import {
  Button,
  IconButton,
  Paper,
  Tooltip,
  Typography,
  CircularProgress,
  Grid,
  Card,
  CardContent,
  CardActions,
  Chip,
  Divider,
  Box,
} from "@material-ui/core";
import {
  Edit,
  CheckCircle,
  SignalCellularConnectedNoInternet2Bar,
  SignalCellularConnectedNoInternet0Bar,
  SignalCellular4Bar,
  BatteryChargingFull,
  CropFree,
  DeleteOutline,
  PowerSettingsNew,
  Link as LinkIcon,
  QrCode as QrCodeIcon, // se não existir no seu @material-ui/icons, troque por CropFree
} from "@material-ui/icons";

import MainContainer from "../../components/MainContainer";
import MainHeader from "../../components/MainHeader";
import MainHeaderButtonsWrapper from "../../components/MainHeaderButtonsWrapper";
import Title from "../../components/Title";

import api from "../../services/api";
import WhatsAppModal from "../../components/WhatsAppModal";
import ConfirmationModal from "../../components/ConfirmationModal";
import QrcodeModal from "../../components/QrcodeModal";
import { i18n } from "../../translate/i18n";
import { WhatsAppsContext } from "../../context/WhatsApp/WhatsAppsContext";
import toastError from "../../errors/toastError";

const useStyles = makeStyles(theme => ({
  mainPaper: {
    flex: 1,
    padding: theme.spacing(2),
    overflowY: "auto",
    background: theme.palette.background.default,
    ...theme.scrollbarStyles,
  },
  card: {
    borderRadius: 16,
    boxShadow: "0 6px 18px rgba(0,0,0,0.08)",
  },
  headerRow: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: theme.spacing(1),
  },
  badgeRow: {
    display: "flex",
    alignItems: "center",
    gap: theme.spacing(1),
    flexWrap: "wrap",
    marginTop: theme.spacing(1),
  },
  statusIcon: {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
  },
  batteryIcon: {
    color: green[500],
  },
  batteryLow: {
    color: red[500],
  },
  meta: {
    color: grey[600],
    fontSize: 13,
  },
  bigQR: {
    marginTop: theme.spacing(1.5),
  },
}));

const StatusIcon = ({ status }) => {
  if (status === "DISCONNECTED")
    return <SignalCellularConnectedNoInternet0Bar color="secondary" />;
  if (status === "OPENING")
    return <CircularProgress size={20} />;
  if (status === "qrcode")
    return <CropFree />;
  if (status === "CONNECTED")
    return <SignalCellular4Bar style={{ color: green[500] }} />;
  if (status === "TIMEOUT" || status === "PAIRING")
    return <SignalCellularConnectedNoInternet2Bar color="secondary" />;
  return <SignalCellularConnectedNoInternet0Bar color="disabled" />;
};

const BatteryIcon = ({ battery }) => {
  const classes = useStyles();
  if (battery === null || battery === undefined) return null;
  const low = Number(battery) < 20;
  return (
    <Tooltip title={`${battery}%`}>
      <BatteryChargingFull className={low ? classes.batteryLow : classes.batteryIcon} />
    </Tooltip>
  );
};

const Connections = () => {
  const classes = useStyles();

  const { whatsApps, loading } = useContext(WhatsAppsContext);
  const [whatsAppModalOpen, setWhatsAppModalOpen] = useState(false);
  const [qrModalOpen, setQrModalOpen] = useState(false);
  const [selectedWhatsApp, setSelectedWhatsApp] = useState(null);
  const [confirmModalOpen, setConfirmModalOpen] = useState(false);
  const [confirmModalInfo, setConfirmModalInfo] = useState({
    action: "",
    title: "",
    message: "",
    whatsAppId: "",
    open: false,
  });

  const handleStartWhatsAppSession = async whatsAppId => {
    try {
      await api.post(`/whatsappsession/${whatsAppId}`);
    } catch (err) {
      toastError(err);
    }
  };

  const handleRequestNewQrCode = async whatsAppId => {
    try {
      await api.put(`/whatsappsession/${whatsAppId}`);
    } catch (err) {
      toastError(err);
    }
  };

  const handleOpenWhatsAppModal = () => {
    setSelectedWhatsApp(null);
    setWhatsAppModalOpen(true);
  };

  const handleCloseWhatsAppModal = useCallback(() => {
    setWhatsAppModalOpen(false);
    setSelectedWhatsApp(null);
  }, []);

  const handleOpenQrModal = whatsApp => {
    setSelectedWhatsApp(whatsApp);
    setQrModalOpen(true);
  };

  const handleCloseQrModal = useCallback(() => {
    setSelectedWhatsApp(null);
    setQrModalOpen(false);
  }, []);

  const handleEditWhatsApp = whatsApp => {
    setSelectedWhatsApp(whatsApp);
    setWhatsAppModalOpen(true);
  };

  const handleOpenConfirmationModal = (action, whatsAppId) => {
    if (action === "disconnect") {
      setConfirmModalInfo({
        action,
        title: i18n.t("connections.confirmationModal.disconnectTitle"),
        message: i18n.t("connections.confirmationModal.disconnectMessage"),
        whatsAppId,
      });
    }
    if (action === "delete") {
      setConfirmModalInfo({
        action,
        title: i18n.t("connections.confirmationModal.deleteTitle"),
        message: i18n.t("connections.confirmationModal.deleteMessage"),
        whatsAppId,
      });
    }
    setConfirmModalOpen(true);
  };

  const handleSubmitConfirmationModal = async () => {
    if (confirmModalInfo.action === "disconnect") {
      try {
        await api.delete(`/whatsappsession/${confirmModalInfo.whatsAppId}`);
      } catch (err) {
        toastError(err);
      }
    }
    if (confirmModalInfo.action === "delete") {
      try {
        await api.delete(`/whatsapp/${confirmModalInfo.whatsAppId}`);
        toast.success(i18n.t("connections.toasts.deleted"));
      } catch (err) {
        toastError(err);
      }
    }
    setConfirmModalInfo({ action: "", title: "", message: "", whatsAppId: "", open: false });
  };

  return (
    <MainContainer>
      <ConfirmationModal
        title={confirmModalInfo.title}
        open={confirmModalOpen}
        onClose={setConfirmModalOpen}
        onConfirm={handleSubmitConfirmationModal}
      >
        {confirmModalInfo.message}
      </ConfirmationModal>

      <QrcodeModal
        open={qrModalOpen}
        onClose={handleCloseQrModal}
        whatsAppId={!whatsAppModalOpen && selectedWhatsApp?.id}
      />

      <WhatsAppModal
        open={whatsAppModalOpen}
        onClose={handleCloseWhatsAppModal}
        whatsAppId={!qrModalOpen && selectedWhatsApp?.id}
      />

      <MainHeader>
        <Title>{i18n.t("connections.title")}</Title>
        <MainHeaderButtonsWrapper>
          <Button variant="contained" color="primary" onClick={handleOpenWhatsAppModal}>
            {i18n.t("connections.buttons.add")}
          </Button>
        </MainHeaderButtonsWrapper>
      </MainHeader>

      <Paper className={classes.mainPaper} variant="outlined">
        {loading ? (
          <Box display="flex" justifyContent="center" py={6}>
            <CircularProgress />
          </Box>
        ) : (
          <Grid container spacing={2}>
            {whatsApps?.map(wa => (
              <Grid item xs={12} sm={6} md={4} key={wa.id}>
                <Card className={classes.card} variant="outlined">
                  <CardContent>
                    <div className={classes.headerRow}>
                      <Typography variant="h6">{wa.name}</Typography>
                      <div className={classes.statusIcon}>
                        <StatusIcon status={wa.status} />
                      </div>
                    </div>

                    <div className={classes.badgeRow}>
                      {wa.isDefault && (
                        <Chip
                          size="small"
                          icon={<CheckCircle style={{ color: green[500] }} />}
                          label={i18n.t("connections.table.default")}
                          style={{ background: "#e8f5e9" }}
                        />
                      )}
                      <Chip
                        size="small"
                        label={
                          wa.status === "CONNECTED"
                            ? i18n.t("connections.toolTips.connected.title")
                            : wa.status === "qrcode"
                            ? i18n.t("connections.toolTips.qrcode.title")
                            : wa.status
                        }
                      />
                      <Chip
                        size="small"
                        icon={<BatteryChargingFull />}
                        label={`${wa.battery ?? "--"}%`}
                        variant="outlined"
                      />
                    </div>

                    <Box mt={1.5} className={classes.meta}>
                      <span>
                        {i18n.t("connections.table.lastUpdate")}:{" "}
                        {wa.updatedAt ? format(parseISO(wa.updatedAt), "dd/MM/yy HH:mm") : "--"}
                      </span>
                    </Box>

                    {wa.status === "qrcode" && (
                      <Box className={classes.bigQR}>
                        <Button
                          fullWidth
                          variant="contained"
                          color="primary"
                          startIcon={<CropFree />}
                          onClick={() => handleOpenQrModal(wa)}
                        >
                          {i18n.t("connections.buttons.qrcode")}
                        </Button>
                      </Box>
                    )}
                  </CardContent>

                  <Divider />

                  <CardActions>
                    {wa.status === "DISCONNECTED" && (
                      <>
                        <Button
                          size="small"
                          variant="outlined"
                          color="primary"
                          startIcon={<LinkIcon />}
                          onClick={() => handleStartWhatsAppSession(wa.id)}
                        >
                          {i18n.t("connections.buttons.tryAgain")}
                        </Button>
                        <Button
                          size="small"
                          variant="outlined"
                          color="secondary"
                          onClick={() => handleRequestNewQrCode(wa.id)}
                        >
                          {i18n.t("connections.buttons.newQr")}
                        </Button>
                      </>
                    )}

                    {(wa.status === "CONNECTED" ||
                      wa.status === "PAIRING" ||
                      wa.status === "TIMEOUT") && (
                      <Button
                        size="small"
                        variant="outlined"
                        color="secondary"
                        startIcon={<PowerSettingsNew />}
                        onClick={() => handleOpenConfirmationModal("disconnect", wa.id)}
                      >
                        {i18n.t("connections.buttons.disconnect")}
                      </Button>
                    )}

                    {wa.status === "OPENING" && (
                      <Button size="small" variant="outlined" disabled>
                        {i18n.t("connections.buttons.connecting")}
                      </Button>
                    )}

                    <Box flexGrow={1} />

                    <IconButton size="small" onClick={() => handleEditWhatsApp(wa)}>
                      <Edit />
                    </IconButton>
                    <IconButton
                      size="small"
                      onClick={() => handleOpenConfirmationModal("delete", wa.id)}
                    >
                      <DeleteOutline />
                    </IconButton>
                  </CardActions>
                </Card>
              </Grid>
            ))}

            {!whatsApps?.length && (
              <Grid item xs={12}>
                <Box textAlign="center" py={6}>
                  <Typography variant="body1" color="textSecondary">
                    {i18n.t("connections.noConnections") || "Nenhuma conexão cadastrada."}
                  </Typography>
                </Box>
              </Grid>
            )}
          </Grid>
        )}
      </Paper>
    </MainContainer>
  );
};

export default Connections;
