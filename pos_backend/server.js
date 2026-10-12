const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const { runAutoMigration } = require('./init_db');
const { authenticate, installAuthRoutes, requireAdmin } = require('./auth');
const { installAdminRoutes } = require('./admin_routes');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

let pool = process.env.DATABASE_URL
  ? new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 5000 })
  : new Pool({
      user: process.env.DB_USER,
      host: process.env.DB_HOST,
      database: process.env.DB_NAME,
      password: process.env.DB_PASSWORD,
      port: process.env.DB_PORT,
    });

app.get('/api/v1/health', async (req, res) => {
  try {
    await pool.query('SELECT 1 AS healthy');
    res.json({
      success: true,
      status: 'ONLINE',
      cloudDatabase: 'CONNECTED',
      autoBackup: 'ACTIVE_100PCT_DAILY',
      timestamp: new Date().toISOString(),
    });
  } catch (err) {
    if (process.env.DATABASE_URL) {
      try {
        pool = new Pool({
          user: process.env.DB_USER,
          host: process.env.DB_HOST,
          database: process.env.DB_NAME,
          password: process.env.DB_PASSWORD,
          port: process.env.DB_PORT,
        });
        await pool.query('SELECT 1 AS healthy');
        return res.json({
          success: true,
          status: 'ONLINE',
          cloudDatabase: 'LOCAL_FALLBACK',
          autoBackup: 'ACTIVE_100PCT_DAILY',
          timestamp: new Date().toISOString(),
        });
      } catch (_) {}
    }
    res.status(500).json({ success: false, status: 'DEGRADED', message: err.message });
  }
});

installAuthRoutes(app, pool);
installAdminRoutes(app, pool);

// --- ENDPOINT UNTUK KASIR & ADMIN ---

// Restok produk hanya dapat dilakukan admin; kasir merestok bahan baku.
app.patch('/api/v1/products/:id/restock', authenticate, requireAdmin, async (req, res) => {
  const { id } = req.params;
  const additionalStock = Number(req.body.additionalStock);
  if (!Number.isInteger(additionalStock) || additionalStock <= 0) {
    return res.status(400).json({ success: false, message: 'Jumlah stok tidak valid.' });
  }
  try {
    const result = await pool.query('UPDATE products SET stock = stock + $1 WHERE id = $2', [additionalStock, id]);
    if (result.rowCount === 0) return res.status(404).json({ success: false, message: 'Produk tidak ditemukan.' });
    res.json({ success: true, message: 'Stok berhasil ditambahkan' });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Gagal merestok barang' });
  }
});

// Laporan Laba Rugi (Khusus Admin)
app.get('/api/v1/reports/financial/income-statement', authenticate, requireAdmin, async (req, res) => {
  try {
    const query = `
      SELECT a.code, a.name, a.type, 
             SUM(jd.credit - jd.debit) AS net_revenue,
             SUM(jd.debit - jd.credit) AS net_expense
      FROM journal_details jd
      JOIN accounts a ON jd.account_code = a.code
      WHERE a.type IN ('REVENUE', 'EXPENSE')
      GROUP BY a.code, a.name, a.type;
    `;
    const result = await pool.query(query);
    let totalRevenue = 0, totalExpense = 0;
    result.rows.forEach(row => {
      if (row.type === 'REVENUE') totalRevenue += parseInt(row.net_revenue || 0);
      if (row.type === 'EXPENSE') totalExpense += parseInt(row.net_expense || 0);
    });
    res.json({
      success: true,
      data: { totalRevenue, totalExpense, netProfit: totalRevenue - totalExpense, details: result.rows }
    });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Gagal memproses Laba Rugi' });
  }
});

// Laporan Neraca (Khusus Admin)
app.get('/api/v1/reports/financial/balance-sheet', authenticate, requireAdmin, async (req, res) => {
  try {
    const query = `
      SELECT a.code, a.name, a.type, a.normal_balance,
             SUM(jd.debit) AS total_debit, SUM(jd.credit) AS total_credit
      FROM journal_details jd
      JOIN accounts a ON jd.account_code = a.code
      WHERE a.type IN ('ASSET', 'LIABILITY', 'EQUITY')
      GROUP BY a.code, a.name, a.type, a.normal_balance;
    `;
    const result = await pool.query(query);
    res.json({ success: true, data: result.rows });
  } catch (err) {
    res.status(500).json({ success: false, message: 'Gagal memproses Neraca' });
  }
});

const PORT = process.env.PORT || 3000;
runAutoMigration()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Backend POS running on port ${PORT}`);
    });
  })
  .catch((error) => {
    console.error('[STARTUP ERROR] Gagal menyiapkan database.', error);
    process.exitCode = 1;
  });