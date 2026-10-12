const { Pool } = require('pg');
require('dotenv').config();

let pool = new Pool(
  process.env.DATABASE_URL
    ? { connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 5000 }
    : {
        user: process.env.DB_USER,
        host: process.env.DB_HOST,
        database: process.env.DB_NAME,
        password: process.env.DB_PASSWORD,
        port: process.env.DB_PORT,
      }
);

async function runAutoMigration() {
  let client;
  try {
    client = await pool.connect();
  } catch (connErr) {
    if (process.env.DATABASE_URL) {
      console.warn('[DATABASE WARNING] Gagal otentikasi Supabase Cloud (' + connErr.message + '). Beralih ke PostgreSQL Lokal...');
      pool = new Pool({
        user: process.env.DB_USER,
        host: process.env.DB_HOST,
        database: process.env.DB_NAME,
        password: process.env.DB_PASSWORD,
        port: process.env.DB_PORT,
      });
      client = await pool.connect();
    } else {
      throw connErr;
    }
  }
  try {
    console.log('[AUTO-MIGRATE] Memeriksa & Memperbarui Skema Akuntansi...');
    await client.query('BEGIN');

    await client.query(`
      CREATE TABLE IF NOT EXISTS users (
        id VARCHAR(36) PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        pin_hash VARCHAR(255),
        role VARCHAR(20) DEFAULT 'CASHIER',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS products (
        id VARCHAR(36) PRIMARY KEY,
        sku VARCHAR(50) UNIQUE,
        name VARCHAR(100) NOT NULL,
        cost_price INT DEFAULT 0,
        selling_price INT DEFAULT 0,
        stock INT DEFAULT 0,
        category VARCHAR(50),
        is_active BOOLEAN DEFAULT TRUE,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS orders (
        id VARCHAR(36) PRIMARY KEY,
        user_id VARCHAR(36),
        order_number VARCHAR(50),
        subtotal INT DEFAULT 0,
        discount_amount INT DEFAULT 0,
        tax_amount INT DEFAULT 0,
        service_amount INT DEFAULT 0,
        service_rate NUMERIC(7, 5) DEFAULT 0,
        total_price INT NOT NULL,
        paid_amount INT NOT NULL,
        change_amount INT NOT NULL,
        payment_method VARCHAR(20) NOT NULL,
        status VARCHAR(20) DEFAULT 'COMPLETED',
        created_at TIMESTAMP NOT NULL,
        synced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS order_items (
        id VARCHAR(36) PRIMARY KEY,
        order_id VARCHAR(36) REFERENCES orders(id) ON DELETE CASCADE,
        product_id VARCHAR(36),
        product_name VARCHAR(100) NOT NULL,
        cost_price INT DEFAULT 0,
        selling_price INT DEFAULT 0,
        quantity INT NOT NULL,
        subtotal INT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS accounts (
        code VARCHAR(20) PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        type VARCHAR(20) NOT NULL,
        normal_balance VARCHAR(10) NOT NULL
      );

      CREATE TABLE IF NOT EXISTS journal_entries (
        id VARCHAR(36) PRIMARY KEY,
        reference_id VARCHAR(36),
        transaction_date TIMESTAMP NOT NULL,
        description TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS journal_details (
        id SERIAL PRIMARY KEY,
        journal_id VARCHAR(36) REFERENCES journal_entries(id) ON DELETE CASCADE,
        account_code VARCHAR(20) REFERENCES accounts(code),
        debit INT DEFAULT 0,
        credit INT DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS ingredients (
        id VARCHAR(36) PRIMARY KEY,
        name VARCHAR(100) NOT NULL UNIQUE,
        base_unit VARCHAR(20) NOT NULL,
        stock_quantity NUMERIC(14, 3) NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
        low_stock_threshold NUMERIC(14, 3) NOT NULL DEFAULT 0 CHECK (low_stock_threshold >= 0),
        cost_per_base_unit NUMERIC(14, 4) NOT NULL DEFAULT 0 CHECK (cost_per_base_unit >= 0),
        is_manual_cost BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS ingredient_stock_movements (
        id VARCHAR(36) PRIMARY KEY,
        ingredient_id VARCHAR(36) NOT NULL REFERENCES ingredients(id),
        user_id VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
        movement_type VARCHAR(24) NOT NULL,
        quantity_delta NUMERIC(14, 3) NOT NULL,
        unit_cost NUMERIC(14, 4) NOT NULL DEFAULT 0,
        total_cost NUMERIC(14, 2) NOT NULL DEFAULT 0,
        reference_id VARCHAR(36),
        note TEXT,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS product_recipes (
        product_id VARCHAR(36) NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        ingredient_id VARCHAR(36) NOT NULL REFERENCES ingredients(id),
        quantity_per_product NUMERIC(14, 3) NOT NULL CHECK (quantity_per_product > 0),
        PRIMARY KEY (product_id, ingredient_id)
      );

      CREATE TABLE IF NOT EXISTS operating_expenses (
        id VARCHAR(36) PRIMARY KEY,
        expense_date DATE NOT NULL,
        category VARCHAR(100) NOT NULL,
        description TEXT NOT NULL,
        amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
        created_by VARCHAR(36) REFERENCES users(id) ON DELETE SET NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS store_settings (
        setting_key VARCHAR(80) PRIMARY KEY,
        setting_value JSONB NOT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );

      ALTER TABLE products ADD COLUMN IF NOT EXISTS image_url TEXT;
      ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS image_url TEXT;
      ALTER TABLE orders ADD COLUMN IF NOT EXISTS service_amount INT DEFAULT 0;
      ALTER TABLE orders ADD COLUMN IF NOT EXISTS service_rate NUMERIC(7, 5) DEFAULT 0;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(255);
      ALTER TABLE users DROP COLUMN IF EXISTS email;
      ALTER TABLE users DROP COLUMN IF EXISTS password_hash;
      CREATE INDEX IF NOT EXISTS idx_ingredient_movements_created_at
        ON ingredient_stock_movements (created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_ingredient_movements_reference
        ON ingredient_stock_movements (reference_id);
      CREATE INDEX IF NOT EXISTS idx_operating_expenses_date
        ON operating_expenses (expense_date DESC);
    `);

    await client.query(`
      INSERT INTO accounts (code, name, type, normal_balance) VALUES
        ('1101', 'Kas Kasir', 'ASSET', 'DEBIT'),
        ('1102', 'Bank / QRIS', 'ASSET', 'DEBIT'),
        ('1103', 'Persediaan Barang Dagang', 'ASSET', 'DEBIT'),
        ('1201', 'Peralatan & Mesin', 'ASSET', 'DEBIT'),
        ('3101', 'Modal Pemilik', 'EQUITY', 'CREDIT'),
        ('3201', 'Prive / Penarikan Modal', 'EQUITY', 'DEBIT'),
        ('4101', 'Pendapatan Penjualan', 'REVENUE', 'CREDIT'),
        ('5101', 'Beban HPP (Harga Pokok Penjualan)', 'EXPENSE', 'DEBIT')
      ON CONFLICT (code) DO NOTHING;
    `);

    await client.query(`
      INSERT INTO products (id, name, category, selling_price, cost_price, stock, is_active) VALUES
        ('1', 'Kopi Susu Gula Aren', 'Kopi', 22000, 8000, 99, TRUE),
        ('2', 'Americano', 'Kopi', 18000, 5000, 99, TRUE),
        ('3', 'Caramel Latte', 'Kopi', 28000, 10000, 99, TRUE),
        ('4', 'Es Teh Lemon', 'Teh', 12000, 4000, 99, TRUE),
        ('5', 'Thai Tea', 'Teh', 18000, 6000, 99, TRUE),
        ('6', 'Matcha Latte', 'Teh', 26000, 9000, 99, TRUE),
        ('7', 'Lemon Squash', 'Segar', 20000, 7000, 99, TRUE),
        ('8', 'Jus Alpukat', 'Segar', 24000, 9000, 99, TRUE),
        ('9', 'Mango Smoothie', 'Segar', 25000, 9000, 99, TRUE)
      ON CONFLICT (id) DO NOTHING;
    `);

    await client.query('ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS is_manual_cost BOOLEAN DEFAULT FALSE;');

    await client.query(`
      WITH renumbered AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY created_at ASC) as row_seq
        FROM orders
        WHERE order_number IS NULL OR LENGTH(order_number) > 10 OR order_number NOT LIKE 'A-%'
      )
      UPDATE orders o
      SET order_number = 'A-' || LPAD(r.row_seq::text, 5, '0')
      FROM renumbered r
      WHERE o.id = r.id;
    `);

    await client.query('COMMIT');
    console.log('[AUTO-MIGRATE] Berhasil!');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[AUTO-MIGRATE ERROR]', err);
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { pool, runAutoMigration };