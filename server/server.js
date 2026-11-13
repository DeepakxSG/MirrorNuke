'use strict';
// MirrorNuke signaling and room-scoped device directory server.
// Only relays validated signaling metadata and room presence; media streams and passwords never pass through.
const { WebSocketServer } = require('ws');
const crypto = require('crypto');

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';
const SERVER_TOKEN = process.env.MIRRORNUKE_TOKEN || '';
const TRUST_PROXY = process.env.TRUST_PROXY === '1';

const MAX_PAYLOAD = 64 * 1024;
const MAX_PEERS_PER_ROOM = 12;
const MAX_CONN_PER_IP = 30;
const MAX_ROOMS = 1000;
const MSG_LIMIT_PER_SEC = 120;
const JOIN_TIMEOUT_MS = 10000;

const ROOM_RE = /^[A-Za-z0-9_:-]{1,80}$/;
const NAME_RE = /^[A-Za-z0-9_-]{1,32}$/;
const ALLOWED_CAPS = new Set(['screen', 'audio', 'control', 'multidisplay', 'tv']);
const RELAY_TYPES = new Set(['hello', 'ready', 'offer', 'answer', 'candidate']);

const sha = (s) => crypto.createHash('sha256').update(String(s)).digest();
function tokenOk(t) {
  if (!SERVER_TOKEN) return true;
  return typeof t === 'string' && t.length <= 256 && crypto.timingSafeEqual(sha(t), sha(SERVER_TOKEN));
}

function cleanCapabilities(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const item of raw.slice(0, 8)) {
    if (typeof item === 'string' && ALLOWED_CAPS.has(item) && !out.includes(item)) {
      out.push(item);
    }
  }
  return out;
}

function cleanRelay(m) {
  if (!m || typeof m !== 'object' || Array.isArray(m) || !RELAY_TYPES.has(m.type)) return null;
  const out = { type: m.type };
  if (typeof m.from === 'string' && NAME_RE.test(m.from)) out.from = m.from;
  if (typeof m.to === 'string' && NAME_RE.test(m.to)) out.to = m.to;

  if (m.type === 'offer' || m.type === 'answer') {
    if (typeof m.sdp !== 'string' || m.sdp.length === 0 || m.sdp.length > 55000) return null;
    out.sdp = m.sdp;
  } else if (m.type === 'candidate') {
    const c = m.candidate;
    if (!c || typeof c !== 'object' || typeof c.candidate !== 'string' || c.candidate.length > 1000) return null;
    out.candidate = {
      candidate: c.candidate,
      sdpMid: typeof c.sdpMid === 'string' ? c.sdpMid.slice(0, 64) : null,
      sdpMLineIndex: Number.isInteger(c.sdpMLineIndex) && c.sdpMLineIndex >= 0 && c.sdpMLineIndex < 64 ? c.sdpMLineIndex : 0,
    };
  }
  return out;
}

const wss = new WebSocketServer({ port: PORT, host: HOST, maxPayload: MAX_PAYLOAD });
const rooms = new Map();
const perIp = new Map();

function ipOf(req) {
  if (TRUST_PROXY) {
    const xf = req.headers['x-forwarded-for'];
    if (typeof xf === 'string') return xf.split(',')[0].trim();
  }
  return req.socket.remoteAddress || 'unknown';
}

function reject(ws, reason) {
  try { ws.send(JSON.stringify({ type: 'error', reason })); } catch (_) {}
  ws.close(1008, reason);
}

function broadcastDirectory(baseRoom) {
  const peers = rooms.get(baseRoom);
  if (!peers) return;
  const devices = [];
  for (const p of peers) {
    if (p.deviceName) {
      devices.push({
        name: p.deviceName,
        platform: p.platform || 'unknown',
        caps: p.caps || [],
        sharing: Boolean(p.sharing),
      });
    }
  }
  const payload = JSON.stringify({ type: 'directory', devices });
  for (const p of peers) {
    if (p.readyState === 1 && p.deviceName) {
      p.send(payload);
    }
  }
}

wss.on('connection', (ws, req) => {
  const ip = ipOf(req);
  const n = (perIp.get(ip) || 0) + 1;
  if (n > MAX_CONN_PER_IP) return reject(ws, 'too_many_connections');
  perIp.set(ip, n);

  ws.isAlive = true;
  ws.room = null;
  ws.baseRoom = null;
  ws.deviceName = null;
  ws.platform = 'unknown';
  ws.caps = [];
  ws.sharing = false;

  let count = 0;
  let windowStart = Date.now();
  const joinTimer = setTimeout(() => { if (!ws.room) ws.close(1008, 'join_timeout'); }, JOIN_TIMEOUT_MS);

  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (raw, isBinary) => {
    if (isBinary) return ws.close(1003, 'text_only');
    const now = Date.now();
    if (now - windowStart > 1000) { windowStart = now; count = 0; }
    if (++count > MSG_LIMIT_PER_SEC) return ws.close(1008, 'rate_limited');

    let m;
    try { m = JSON.parse(raw.toString()); } catch (_) { return; }
    if (!m || typeof m !== 'object') return;

    if (m.type === 'join') {
      if (ws.room) return;
      if (typeof m.room !== 'string' || !ROOM_RE.test(m.room)) return reject(ws, 'bad_room');
      if (!tokenOk(m.token)) return reject(ws, 'denied');

      const baseRoom = m.room.split(':')[0];
      const set = rooms.get(m.room) || new Set();
      if (!rooms.has(m.room) && rooms.size >= MAX_ROOMS) return reject(ws, 'server_busy');
      if (set.size >= MAX_PEERS_PER_ROOM) return reject(ws, 'room_full');

      if (typeof m.name === 'string' && NAME_RE.test(m.name)) {
        for (const existing of set) {
          if (existing.deviceName === m.name) {
            return reject(ws, 'duplicate_name');
          }
        }
        ws.deviceName = m.name;
        ws.platform = (m.platform === 'windows' || m.platform === 'android') ? m.platform : 'unknown';
        ws.caps = cleanCapabilities(m.caps);
        ws.sharing = Boolean(m.sharing);
      }

      set.add(ws);
      rooms.set(m.room, set);
      ws.room = m.room;
      ws.baseRoom = baseRoom;
      clearTimeout(joinTimer);

      if (ws.deviceName) {
        broadcastDirectory(ws.room);
      }
      return;
    }

    if (!ws.room) return;

    if (m.type === 'presence') {
      if (ws.deviceName) {
        ws.caps = cleanCapabilities(m.caps);
        ws.sharing = Boolean(m.sharing);
        broadcastDirectory(ws.room);
      }
      return;
    }

    const msg = cleanRelay(m);
    if (!msg) return;
    const data = JSON.stringify(msg);
    for (const p of rooms.get(ws.room) || []) {
      if (p !== ws && p.readyState === 1) p.send(data);
    }
  });

  ws.on('close', () => {
    clearTimeout(joinTimer);
    const left = (perIp.get(ip) || 1) - 1;
    if (left <= 0) perIp.delete(ip); else perIp.set(ip, left);
    if (ws.room) {
      const closedRoom = ws.room;
      const hadName = Boolean(ws.deviceName);
      const set = rooms.get(closedRoom);
      if (set) {
        set.delete(ws);
        if (set.size === 0) rooms.delete(closedRoom);
        else if (hadName) broadcastDirectory(closedRoom);
      }
    }
  });
  ws.on('error', () => {});
});

const hb = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    try { ws.ping(); } catch (_) {}
  }
}, 30000);

function shutdown() {
  clearInterval(hb);
  wss.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 2000);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

console.log(`MirrorNuke signaling & discovery on ${HOST}:${PORT}${SERVER_TOKEN ? ' (token required)' : ''}`);
