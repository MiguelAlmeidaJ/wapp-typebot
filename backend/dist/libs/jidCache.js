"use strict";
const map = new Map(); // ticketId -> remoteJid (@lid, @s.whatsapp.net, etc)

function setTicketJid(ticketId, remoteJid) {
  if (!ticketId || !remoteJid) return;
  map.set(String(ticketId), String(remoteJid));
}
function getTicketJid(ticketId) {
  if (!ticketId) return null;
  return map.get(String(ticketId)) || null;
}
function clearTicketJid(ticketId) {
  if (!ticketId) return;
  map.delete(String(ticketId));
}

module.exports = { setTicketJid, getTicketJid, clearTicketJid };
