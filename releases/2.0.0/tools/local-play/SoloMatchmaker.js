'use strict';
// Deliberately not on 8080: the user's Cloudflare tunnel may still target it.
const http = require('node:http');
const crypto = require('node:crypto');

function createMatchmaker(owner, options = {}) {
  if (!/^[a-f0-9]{64}$/.test(owner)) throw new Error('A fresh local owner key is required');
  const clock = options.clock || Date.now;
  let active = null;
  const equal = (value) => {
    const supplied = Buffer.from(value || '');
    const expected = Buffer.from('Bearer ' + owner);
    return supplied.length === expected.length && crypto.timingSafeEqual(supplied, expected);
  };
  const server = http.createServer((req, res) => {
    const reply = (code, payload) => {
      res.writeHead(code, {'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Connection': 'close'});
      res.end(JSON.stringify(payload));
    };
    // No browser access, forwarding headers, remote interface or tunnel entry.
    if (req.socket.remoteAddress !== '127.0.0.1' || req.headers.origin || req.headers['x-forwarded-for'] || req.headers['cf-connecting-ip']) {
      return reply(403, {error: 'Local owner access only'});
    }
    const port = server.address().port;
    if (req.headers.host !== `127.0.0.1:${port}` || !equal(req.headers.authorization)) {
      return reply(403, {error: 'Local owner access only'});
    }
    if (req.method !== 'POST') return reply(405, {error: 'POST required'});
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > 2048) req.destroy();
    });
    req.on('end', () => {
      let data;
      try { data = JSON.parse(body || '{}'); } catch { return reply(400, {error: 'Invalid JSON'}); }
      if (!data || typeof data !== 'object' || Array.isArray(data)) return reply(400, {error: 'Invalid request'});
      if (active && active.expires_at <= clock()) active = null;
      if (req.url === '/queue') {
        if (!active) {
          active = {
            match_id: crypto.randomUUID(), player_id: crypto.randomUUID(),
            player_token: crypto.randomBytes(32).toString('hex'),
            state: 'allocated', capacity: 1, mode: 'Solo',
            levels: {'0': 'special/lobby.json', '32': 'big_betty.json', '16': 'contained.json', '8': 'claws.json', '4': 'eliminating.json'},
            expires_at: clock() + 30000
          };
        }
        return reply(200, active);
      }
      if (req.url === '/ready' || req.url === '/heartbeat' || req.url === '/cancel') {
        if (!active || data.match_id !== active.match_id) return reply(409, {error: 'Match expired or replaced'});
        if (req.url === '/cancel') { active = null; return reply(200, {state: 'cancelled'}); }
        if (req.url === '/ready') active.state = 'running';
        active.expires_at = clock() + 30000;
        return reply(200, {match_id: active.match_id, state: active.state});
      }
      reply(404, {error: 'Unknown operation'});
    });
  });
  server.requestTimeout = 5000;
  server.headersTimeout = 5000;
  return server;
}

if (require.main === module) {
  const owner = process.argv[2];
  const server = createMatchmaker(owner);
  server.on('error', () => { console.error('Solo matchmaker could not bind its local port.'); process.exitCode = 1; });
  server.listen(18080, '127.0.0.1', () => console.log('Solo matchmaker ready on loopback; capacity 1.'));
  process.on('SIGTERM', () => server.close());
}
module.exports = {createMatchmaker};
