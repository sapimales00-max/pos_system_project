const crypto = require('crypto');
const { promisify } = require('util');

const scrypt = promisify(crypto.scrypt);
const sessions = new Map();
const loginAttempts = new Map();
const sessionDurationMs = 12 * 60 * 60 * 1000;
const loginWindowMs = 15 * 60 * 1000;
const maxLoginAttempts = 5;
const bootstrapLockId = 732185;

async function hashPin(pin) {
  const salt = crypto.randomBytes(16).toString('hex');
  const derivedKey = await scrypt(pin, salt, 64);
  return `${salt}:${derivedKey.toString('hex')}`;
}

async function pinMatches(pin, storedHash) {
  const [salt, keyHex] = (storedHash || '').split(':');
  if (!salt || !keyHex) return false;
  const expected = Buffer.from(keyHex, 'hex');
  if (expected.length !== 64) return false;
  const actual = await scrypt(pin, salt, expected.length);
  return crypto.timingSafeEqual(expected, actual);
}

function validPin(pin) {
  return typeof pin === 'string' && /^\d{6}$/.test(pin);
}

function issueSession(user) {
  const token = crypto.randomBytes(32).toString('base64url');
  sessions.set(token, {
    id: user.id,
    name: user.name,
    role: user.role,
    expiresAt: Date.now() + sessionDurationMs,
  });
  return token;
}

function authenticate(req, res, next) {
  const token = req.get('authorization')?.replace(/^Bearer\s+/i, '');
  const user = token && sessions.get(token);
  if (!user || user.expiresAt <= Date.now()) {
    if (token) sessions.delete(token);
    return res.status(401).json({ success: false, message: 'Silakan masuk kembali.' });
  }
  req.user = user;
  next();
}

function requireAdmin(req, res, next) {
  if (!['ADMIN', 'OWNER'].includes(req.user?.role)) {
    return res.status(403).json({ success: false, message: 'Akses khusus admin.' });
  }
  next();
}

function safeSecretMatches(provided, expected) {
  if (typeof provided !== 'string' || !expected) return false;
  const providedBuffer = Buffer.from(provided);
  const expectedBuffer = Buffer.from(expected);
  return providedBuffer.length === expectedBuffer.length &&
    crypto.timingSafeEqual(providedBuffer, expectedBuffer);
}

function isLoginRateLimited(key) {
  const now = Date.now();
  const attempts = (loginAttempts.get(key) || [])
    .filter((attempt) => now - attempt < loginWindowMs);
  loginAttempts.set(key, attempts);
  return attempts.length >= maxLoginAttempts;
}

function recordFailedLogin(key) {
  const now = Date.now();
  const attempts = (loginAttempts.get(key) || [])
    .filter((attempt) => now - attempt < loginWindowMs);
  attempts.push(now);
  loginAttempts.set(key, attempts);
}

function clearFailedLogins(key) {
  loginAttempts.delete(key);
}

async function assertPinIsUnique(client, pin, excludeUserId = null) {
  const { rows } = await client.query(
    'SELECT id, pin_hash FROM users WHERE pin_hash IS NOT NULL AND id <> COALESCE($1, \'\')',
    [excludeUserId],
  );
  for (const user of rows) {
    if (await pinMatches(pin, user.pin_hash)) {
      throw Object.assign(new Error('PIN sudah dipakai akun lain.'), { status: 409 });
    }
  }
}

function installAuthRoutes(app, pool) {
  app.get('/api/v1/auth/status', async (req, res) => {
    try {
      const { rows } = await pool.query(`
        SELECT EXISTS (SELECT 1 FROM users) AS has_users,
               EXISTS (
                 SELECT 1 FROM users
                 WHERE role IN ('ADMIN', 'OWNER') AND pin_hash IS NOT NULL
               ) AS has_admin_pin
      `);
      res.json({
        success: true,
        needsSetup: !rows[0].has_users,
        needsPinSetup: !rows[0].has_admin_pin,
        bootstrapAvailable:
          typeof process.env.ADMIN_BOOTSTRAP_TOKEN === 'string' &&
          process.env.ADMIN_BOOTSTRAP_TOKEN.length >= 32,
      });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memeriksa status akun.' });
    }
  });

  app.post('/api/v1/auth/cashier-session', (req, res) => {
    const token = issueSession({ id: null, name: 'Kasir', role: 'CASHIER' });
    res.status(201).json({ success: true, token });
  });

  app.post('/api/v1/auth/bootstrap-pin', async (req, res) => {
    const { name, pin, bootstrapToken } = req.body ?? {};
    const attemptKey = `bootstrap:${req.ip || req.socket.remoteAddress || 'unknown'}`;
    if ((process.env.ADMIN_BOOTSTRAP_TOKEN || '').length < 32) {
      return res.status(503).json({ success: false, message: 'ADMIN_BOOTSTRAP_TOKEN harus dikonfigurasi dengan minimal 32 karakter.' });
    }
    if (isLoginRateLimited(attemptKey)) {
      return res.status(429).json({
        success: false,
        message: 'Terlalu banyak percobaan bootstrap. Coba lagi dalam 15 menit.',
      });
    }
    if (!safeSecretMatches(bootstrapToken, process.env.ADMIN_BOOTSTRAP_TOKEN)) {
      recordFailedLogin(attemptKey);
      return res.status(403).json({ success: false, message: 'Token bootstrap tidak valid.' });
    }
    clearFailedLogins(attemptKey);
    if (typeof name !== 'string' || !name.trim() || !validPin(pin)) {
      return res.status(400).json({ success: false, message: 'Nama admin dan PIN 6 digit wajib diisi.' });
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock($1)', [bootstrapLockId]);
      const { rows: adminRows } = await client.query(`
        SELECT id, name, role, pin_hash FROM users
        WHERE role IN ('ADMIN', 'OWNER')
        ORDER BY created_at ASC, id ASC
        FOR UPDATE
      `);
      if (adminRows.some((user) => user.pin_hash)) {
        await client.query('ROLLBACK');
        return res.status(409).json({ success: false, message: 'PIN admin sudah dikonfigurasi.' });
      }
      await assertPinIsUnique(client, pin);
      const pinHash = await hashPin(pin);
      let user;
      if (adminRows.length > 0) {
        const existingAdmin = adminRows[0];
        const { rows } = await client.query(`
          UPDATE users SET name = $2, pin_hash = $3
          WHERE id = $1 RETURNING id, name, role
        `, [existingAdmin.id, name.trim(), pinHash]);
        user = rows[0];
      } else {
        const id = crypto.randomUUID();
        const { rows } = await client.query(`
          INSERT INTO users (id, name, role, pin_hash)
          VALUES ($1, $2, 'ADMIN', $3)
          RETURNING id, name, role
        `, [id, name.trim(), pinHash]);
        user = rows[0];
      }
      await client.query('COMMIT');
      res.status(201).json({ success: true, token: issueSession(user), user });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(error.status || 500).json({
        success: false,
        message: error.status ? error.message : 'Gagal menyiapkan PIN admin.',
      });
    } finally {
      client.release();
    }
  });

  app.post('/api/v1/auth/login-pin', async (req, res) => {
    const { pin, role } = req.body ?? {};
    const attemptKey = req.ip || req.socket.remoteAddress || 'unknown';
    if (isLoginRateLimited(attemptKey)) {
      return res.status(429).json({
        success: false,
        message: 'Terlalu banyak percobaan. Coba lagi dalam 15 menit.',
      });
    }
    if (!validPin(pin) || !['ADMIN', 'CASHIER'].includes(role)) {
      recordFailedLogin(attemptKey);
      return res.status(400).json({ success: false, message: 'Pilih peran dan masukkan PIN 6 digit.' });
    }
    try {
      const { rows } = await pool.query(`
        SELECT id, name, role, pin_hash
        FROM users
        WHERE pin_hash IS NOT NULL
          AND (($1 = 'ADMIN' AND role IN ('ADMIN', 'OWNER')) OR role = $1)
        ORDER BY id ASC
      `, [role]);
      let match = null;
      let matchCount = 0;
      for (const user of rows) {
        if (await pinMatches(pin, user.pin_hash)) {
          match = user;
          matchCount++;
        }
      }
      if (matchCount !== 1) {
        recordFailedLogin(attemptKey);
        return res.status(401).json({ success: false, message: 'PIN atau peran tidak cocok.' });
      }
      clearFailedLogins(attemptKey);
      const user = { id: match.id, name: match.name, role: match.role };
      res.json({ success: true, token: issueSession(user), user });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal masuk dengan PIN.' });
    }
  });

  app.post('/api/v1/auth/logout', authenticate, (req, res) => {
    const token = req.get('authorization')?.replace(/^Bearer\s+/i, '');
    sessions.delete(token);
    res.json({ success: true });
  });

  app.put('/api/v1/auth/pin', authenticate, async (req, res) => {
    const { currentPin, newPin } = req.body ?? {};
    if (!validPin(currentPin) || !validPin(newPin)) {
      return res.status(400).json({ success: false, message: 'PIN lama dan baru harus terdiri dari 6 digit.' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock($1)', [bootstrapLockId]);
      const { rows } = await client.query(
        'SELECT pin_hash FROM users WHERE id = $1 FOR UPDATE',
        [req.user.id],
      );
      if (!rows[0]?.pin_hash || !(await pinMatches(currentPin, rows[0].pin_hash))) {
        await client.query('ROLLBACK');
        return res.status(401).json({ success: false, message: 'PIN saat ini salah.' });
      }
      await assertPinIsUnique(client, newPin, req.user.id);
      await client.query('UPDATE users SET pin_hash = $2 WHERE id = $1', [
        req.user.id,
        await hashPin(newPin),
      ]);
      await client.query('COMMIT');
      res.json({ success: true });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(error.status || 500).json({
        success: false,
        message: error.status ? error.message : 'Gagal mengubah PIN.',
      });
    } finally {
      client.release();
    }
  });

  app.get('/api/v1/users', authenticate, requireAdmin, async (req, res) => {
    try {
      const { rows } = await pool.query(
        'SELECT id, name, role, (pin_hash IS NOT NULL) AS has_pin, created_at FROM users ORDER BY created_at DESC',
      );
      res.json({ success: true, data: rows });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat akun.' });
    }
  });

  app.post('/api/v1/users', authenticate, requireAdmin, async (req, res) => {
    const { name, pin, role } = req.body ?? {};
    if (typeof name !== 'string' || !name.trim() || !validPin(pin) ||
        !['ADMIN', 'CASHIER'].includes(role)) {
      return res.status(400).json({ success: false, message: 'Nama, PIN 6 digit, dan peran wajib diisi.' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock($1)', [bootstrapLockId]);
      await assertPinIsUnique(client, pin);
      const { rows } = await client.query(`
        INSERT INTO users (id, name, role, pin_hash)
        VALUES ($1, $2, $3, $4)
        RETURNING id, name, role, TRUE AS has_pin
      `, [crypto.randomUUID(), name.trim(), role, await hashPin(pin)]);
      await client.query('COMMIT');
      res.status(201).json({ success: true, data: rows[0] });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(error.status || 500).json({
        success: false,
        message: error.status ? error.message : 'Gagal membuat akun.',
      });
    } finally {
      client.release();
    }
  });

  app.put('/api/v1/users/:id/pin', authenticate, requireAdmin, async (req, res) => {
    const { pin } = req.body ?? {};
    if (!validPin(pin)) {
      return res.status(400).json({ success: false, message: 'PIN harus terdiri dari 6 digit.' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT pg_advisory_xact_lock($1)', [bootstrapLockId]);
      const { rows } = await client.query(
        'SELECT id FROM users WHERE id = $1 FOR UPDATE',
        [req.params.id],
      );
      if (!rows[0]) {
        await client.query('ROLLBACK');
        return res.status(404).json({ success: false, message: 'Akun tidak ditemukan.' });
      }
      await assertPinIsUnique(client, pin, req.params.id);
      await client.query('UPDATE users SET pin_hash = $2 WHERE id = $1', [
        req.params.id,
        await hashPin(pin),
      ]);
      await client.query('COMMIT');
      res.json({ success: true });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(error.status || 500).json({
        success: false,
        message: error.status ? error.message : 'Gagal mengatur ulang PIN.',
      });
    } finally {
      client.release();
    }
  });
}

module.exports = { authenticate, installAuthRoutes, requireAdmin };
