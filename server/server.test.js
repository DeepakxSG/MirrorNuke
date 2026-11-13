'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { tokenOk, cleanCapabilities, cleanRelay, routeRelay } = require('./server');

test('cleanRelay accepts valid offer and strips unknown fields', () => {
  const res = cleanRelay({
    type: 'offer',
    from: 'pc_1',
    to: 'phone_1',
    sdp: 'v=0\r\no=- 123 2 IN IP4 127.0.0.1\r\n',
    injected: 'drop-me',
  });
  assert.deepEqual(res, {
    type: 'offer',
    from: 'pc_1',
    to: 'phone_1',
    sdp: 'v=0\r\no=- 123 2 IN IP4 127.0.0.1\r\n',
  });
});

test('cleanRelay sanitizes ICE candidate payloads', () => {
  const res = cleanRelay({
    type: 'candidate',
    candidate: {
      candidate: 'candidate:1 1 UDP 2122252543 192.168.1.10 54321 typ host',
      sdpMid: '0',
      sdpMLineIndex: 0,
      extra: 99,
    },
  });
  assert.equal(res.candidate.sdpMid, '0');
  assert.equal(res.candidate.sdpMLineIndex, 0);
  assert.equal('extra' in res.candidate, false);
});

test('cleanRelay rejects invalid device names in from/to', () => {
  assert.equal(cleanRelay({ type: 'ready', from: '../bad' }), null);
  assert.equal(cleanRelay({ type: 'ready', to: 'bad name!' }), null);
});

test('cleanCapabilities filters unknown and duplicate capabilities', () => {
  const caps = cleanCapabilities(['screen', 'audio', 'screen', 'root_shell', 'control']);
  assert.deepEqual(caps, ['screen', 'audio', 'control']);
});

test('tokenOk validates shared token safely', () => {
  assert.equal(tokenOk('', ''), true);
  assert.equal(tokenOk('secret123', 'secret123'), true);
  assert.equal(tokenOk('wrong', 'secret123'), false);
});

test('routeRelay honors targeted `to` and skips sender and closed peers', () => {
  const sent = [];
  const makePeer = (name, readyState = 1) => ({
    deviceName: name,
    readyState,
    send: (msg) => sent.push({ name, msg }),
  });
  const pc = makePeer('pc');
  const phoneA = makePeer('phoneA');
  const phoneB = makePeer('phoneB');
  const offline = makePeer('phoneC', 3);

  const count = routeRelay([pc, phoneA, phoneB, offline], pc, {
    type: 'offer',
    from: 'pc',
    to: 'phoneB',
    sdp: 'v=0',
  });
  assert.equal(count, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].name, 'phoneB');
});
