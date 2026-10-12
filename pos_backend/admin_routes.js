const crypto = require('crypto');
const ExcelJS = require('exceljs');
const { authenticate, requireAdmin } = require('./auth');

const allowedSettings = new Set([
  'store_profile',
  'tax_and_service',
  'receipt',
]);

function installAdminRoutes(app, pool) {
  app.get('/api/v1/settings/public', authenticate, async (req, res) => {
    try {
      const { rows } = await pool.query(`
        SELECT setting_key, setting_value FROM store_settings
        WHERE setting_key IN ('store_profile', 'tax_and_service', 'receipt')
      `);
      res.json({
        success: true,
        data: Object.fromEntries(rows.map((row) => [row.setting_key, row.setting_value])),
      });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat pengaturan kasir.' });
    }
  });

  app.get('/api/v1/dashboard', authenticate, requireAdmin, async (req, res) => {
    try {
      const [sales, salesYesterday, ingredients, recent, hourlySales, topToday, topWeek, topMonth] = await Promise.all([
        pool.query(`
          SELECT COUNT(*)::int AS transaction_count,
                 COALESCE(SUM(o.total_price), 0)::numeric AS sales_total,
                 COALESCE(SUM(
                   (SELECT COALESCE(SUM(r.quantity_per_product * i.cost_per_base_unit), p.cost_price, 0)
                    FROM product_recipes r
                    JOIN ingredients i ON i.id = r.ingredient_id
                    WHERE r.product_id = p.id) * oi.quantity
                 ), 0)::numeric AS cost_total
          FROM orders o
          LEFT JOIN order_items oi ON oi.order_id = o.id
          LEFT JOIN products p ON p.id = oi.product_id
          WHERE o.created_at::date = CURRENT_DATE AND o.status <> 'CANCELLED'
        `),
        pool.query(`
          SELECT COALESCE(SUM(total_price), 0)::numeric AS sales_total
          FROM orders
          WHERE created_at::date = CURRENT_DATE - INTERVAL '1 day' AND status <> 'CANCELLED'
        `),
        pool.query(`
          SELECT id, name, stock_quantity, base_unit, low_stock_threshold
          FROM ingredients
          WHERE stock_quantity <= low_stock_threshold
          ORDER BY stock_quantity ASC, name ASC
        `),
        pool.query(`
          SELECT o.id, o.order_number, o.created_at, o.total_price,
                 o.payment_method, o.status,
                 COALESCE(json_agg(json_build_object(
                   'name', oi.product_name, 'quantity', oi.quantity
                 ) ORDER BY oi.product_name) FILTER (WHERE oi.id IS NOT NULL), '[]') AS items
          FROM orders o
          LEFT JOIN order_items oi ON oi.order_id = o.id
          GROUP BY o.id
          ORDER BY o.created_at DESC
          LIMIT 8
        `),
        pool.query(`
          SELECT EXTRACT(HOUR FROM created_at)::int AS hour,
                 COALESCE(SUM(total_price), 0)::numeric AS total
          FROM orders
          WHERE created_at::date = CURRENT_DATE AND status <> 'CANCELLED'
          GROUP BY EXTRACT(HOUR FROM created_at)
          ORDER BY hour ASC
        `),
        pool.query(`
          SELECT oi.product_name AS name,
                 SUM(oi.quantity)::int AS total_quantity
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
          WHERE o.created_at::date = CURRENT_DATE AND o.status <> 'CANCELLED'
          GROUP BY oi.product_name
          ORDER BY total_quantity DESC
          LIMIT 5
        `),
        pool.query(`
          SELECT oi.product_name AS name,
                 SUM(oi.quantity)::int AS total_quantity
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
          WHERE o.created_at >= CURRENT_DATE - INTERVAL '7 days' AND o.status <> 'CANCELLED'
          GROUP BY oi.product_name
          ORDER BY total_quantity DESC
          LIMIT 5
        `),
        pool.query(`
          SELECT oi.product_name AS name,
                 SUM(oi.quantity)::int AS total_quantity
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
          WHERE o.created_at >= CURRENT_DATE - INTERVAL '30 days' AND o.status <> 'CANCELLED'
          GROUP BY oi.product_name
          ORDER BY total_quantity DESC
          LIMIT 5
        `),
      ]);

      const salesTodayVal = Number(sales.rows[0].sales_total);
      const salesYesterdayVal = Number(salesYesterday.rows[0].sales_total);
      const costTodayVal = Number(sales.rows[0].cost_total);
      const grossProfitToday = Math.max(0, salesTodayVal - costTodayVal);
      const marginRatio = salesTodayVal > 0 ? (grossProfitToday / salesTodayVal) : 0.65;

      res.json({
        success: true,
        data: {
          salesToday: salesTodayVal,
          salesYesterday: salesYesterdayVal,
          transactionsToday: sales.rows[0].transaction_count,
          grossProfitToday: grossProfitToday,
          marginPercent: Math.round(marginRatio * 100),
          lowStockCount: ingredients.rowCount,
          lowStockIngredients: ingredients.rows,
          recentTransactions: recent.rows,
          hourlySales: hourlySales.rows,
          topSelling: {
            today: topToday.rows,
            week: topWeek.rows,
            month: topMonth.rows,
          },
        },
      });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat dashboard.' });
    }
  });

  app.get('/api/v1/ingredients/restock-history', authenticate, async (req, res) => {
    try {
      const { rows } = await pool.query(`
        SELECT m.id, m.ingredient_id, m.movement_type, m.quantity_delta,
               m.unit_cost, m.total_cost, m.note, m.created_at,
               i.name AS ingredient_name, i.base_unit,
               COALESCE(u.name, 'Admin/Kasir') AS user_name
        FROM ingredient_stock_movements m
        JOIN ingredients i ON i.id = m.ingredient_id
        LEFT JOIN users u ON u.id = m.user_id
        ORDER BY m.created_at DESC
        LIMIT 100
      `);

      const monthlySummary = await pool.query(`
        SELECT COUNT(*)::int AS count,
               COALESCE(SUM(total_cost), 0)::numeric AS total_purchase_value
        FROM ingredient_stock_movements
        WHERE movement_type IN ('RESTOCK', 'INITIAL')
          AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
      `);

      res.json({
        success: true,
        data: {
          history: rows,
          summary: {
            restockCountMonth: monthlySummary.rows[0].count,
            totalPurchaseMonth: Number(monthlySummary.rows[0].total_purchase_value),
          },
        },
      });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat riwayat restock.' });
    }
  });

  app.get('/api/v1/ingredients', authenticate, async (req, res) => {
    try {
      const { rows } = await pool.query(`
        SELECT id, name, base_unit, stock_quantity, low_stock_threshold,
               cost_per_base_unit, image_url, stock_quantity <= low_stock_threshold AS is_low_stock
        FROM ingredients ORDER BY name ASC
      `);
      res.json({ success: true, data: rows });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat stok bahan.' });
    }
  });

  app.post('/api/v1/ingredients', authenticate, async (req, res) => {
    const { name, baseUnit, stockQuantity = 0, lowStockThreshold = 0, costPerBaseUnit = 0, imageUrl } = req.body;
    if (!name || !baseUnit || !Number.isFinite(Number(lowStockThreshold)) || Number(lowStockThreshold) < 0) {
      return res.status(400).json({ success: false, message: 'Data bahan tidak valid.' });
    }
    const initialStock = Number.isFinite(Number(stockQuantity)) ? Number(stockQuantity) : 0;
    const initialCost = Number.isFinite(Number(costPerBaseUnit)) ? Number(costPerBaseUnit) : 0;
    try {
      const id = crypto.randomUUID();
      const { rows } = await pool.query(`
        INSERT INTO ingredients (id, name, base_unit, stock_quantity, low_stock_threshold, cost_per_base_unit, is_manual_cost, image_url)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id, name, base_unit, stock_quantity, low_stock_threshold, cost_per_base_unit, is_manual_cost, image_url
      `, [id, name.trim(), baseUnit.trim(), initialStock, Number(lowStockThreshold), initialCost, initialCost > 0, imageUrl?.trim() || null]);

      if (initialStock > 0) {
        await pool.query(`
          INSERT INTO ingredient_stock_movements
            (id, ingredient_id, user_id, movement_type, quantity_delta, unit_cost, total_cost, note)
          VALUES ($1, $2, $3, 'INITIAL', $4, $5, $6, 'Stok awal')
        `, [crypto.randomUUID(), id, req.user.id, initialStock, initialCost, initialStock * initialCost]);
      }

      res.status(201).json({ success: true, data: rows[0] });
    } catch (error) {
      res.status(error.code === '23505' ? 409 : 500).json({
        success: false,
        message: error.code === '23505' ? 'Nama bahan sudah digunakan.' : 'Gagal menambah bahan.',
      });
    }
  });

  app.patch('/api/v1/ingredients/:id', authenticate, async (req, res) => {
    const { name, baseUnit, lowStockThreshold, imageUrl, costPerBaseUnit } = req.body;
    if (lowStockThreshold !== undefined &&
        (!Number.isFinite(Number(lowStockThreshold)) || Number(lowStockThreshold) < 0)) {
      return res.status(400).json({ success: false, message: 'Ambang stok tidak valid.' });
    }
    const hasManualCost = costPerBaseUnit !== undefined && costPerBaseUnit !== null && Number(costPerBaseUnit) > 0;
    try {
      const { rows } = await pool.query(`
        UPDATE ingredients SET
          name = COALESCE($2, name),
          base_unit = COALESCE($3, base_unit),
          low_stock_threshold = COALESCE($4, low_stock_threshold),
          image_url = COALESCE($5, image_url),
          cost_per_base_unit = CASE WHEN $6::numeric IS NOT NULL THEN $6::numeric ELSE cost_per_base_unit END,
          is_manual_cost = CASE WHEN $6::numeric IS NOT NULL AND $6::numeric > 0 THEN TRUE ELSE is_manual_cost END,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = $1
        RETURNING id, name, base_unit, stock_quantity, low_stock_threshold, cost_per_base_unit, is_manual_cost, image_url
      `, [req.params.id, name?.trim() || null, baseUnit?.trim() || null,
        lowStockThreshold === undefined ? null : Number(lowStockThreshold),
        imageUrl === undefined ? null : (imageUrl?.trim() || null),
        costPerBaseUnit === undefined || costPerBaseUnit === null ? null : Number(costPerBaseUnit)]);
      if (!rows[0]) return res.status(404).json({ success: false, message: 'Bahan tidak ditemukan.' });

      // Recalculate HPP for recipes
      await pool.query(`
        UPDATE products p SET cost_price = COALESCE((
          SELECT ROUND(SUM(i.cost_per_base_unit * r.quantity_per_product))
          FROM product_recipes r JOIN ingredients i ON i.id = r.ingredient_id
          WHERE r.product_id = p.id
        ), 0)::int
        WHERE EXISTS (
          SELECT 1 FROM product_recipes r
          WHERE r.product_id = p.id AND r.ingredient_id = $1
        )
      `, [req.params.id]);

      res.json({ success: true, data: rows[0] });
    } catch (error) {
      res.status(error.code === '23505' ? 409 : 500).json({ success: false, message: 'Gagal memperbarui bahan.' });
    }
  });

  app.post('/api/v1/ingredients/:id/restock', authenticate, async (req, res) => {
    const quantityAdded = Number(req.body.quantityAdded);
    const totalCost = Number(req.body.totalCost);
    if (!Number.isFinite(quantityAdded) || quantityAdded <= 0 ||
        !Number.isFinite(totalCost) || totalCost < 0) {
      return res.status(400).json({ success: false, message: 'Jumlah dan total harga pembelian tidak valid.' });
    }
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const locked = await client.query(
        'SELECT stock_quantity, cost_per_base_unit, is_manual_cost FROM ingredients WHERE id = $1 FOR UPDATE',
        [req.params.id],
      );
      if (!locked.rows[0]) {
        await client.query('ROLLBACK');
        return res.status(404).json({ success: false, message: 'Bahan tidak ditemukan.' });
      }
      const current = locked.rows[0];
      const oldValue = Number(current.stock_quantity) * Number(current.cost_per_base_unit);
      const newStock = Number(current.stock_quantity) + quantityAdded;
      const unitCost = (oldValue + totalCost) / newStock;

      // If manual cost was set in Edit, keep cost_per_base_unit as-is for HPP calculations!
      const finalCost = current.is_manual_cost ? Number(current.cost_per_base_unit) : unitCost;

      const updated = await client.query(`
        UPDATE ingredients SET stock_quantity = $2, cost_per_base_unit = $3,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = $1
        RETURNING id, name, base_unit, stock_quantity, low_stock_threshold, cost_per_base_unit, is_manual_cost
      `, [req.params.id, newStock, finalCost]);
      await client.query(`
        INSERT INTO ingredient_stock_movements
          (id, ingredient_id, user_id, movement_type, quantity_delta, unit_cost, total_cost, note)
        VALUES ($1, $2, $3, 'RESTOCK', $4, $5, $6, $7)
      `, [crypto.randomUUID(), req.params.id, req.user.id, quantityAdded,
        totalCost / quantityAdded, totalCost, req.body.note || null]);
      await client.query(`
        UPDATE products p SET cost_price = COALESCE((
          SELECT ROUND(SUM(i.cost_per_base_unit * r.quantity_per_product))
          FROM product_recipes r JOIN ingredients i ON i.id = r.ingredient_id
          WHERE r.product_id = p.id
        ), 0)::int
        WHERE EXISTS (
          SELECT 1 FROM product_recipes r
          WHERE r.product_id = p.id AND r.ingredient_id = $1
        )
      `, [req.params.id]);
      await client.query('COMMIT');
      res.json({ success: true, data: updated.rows[0] });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(500).json({ success: false, message: 'Gagal menambah stok bahan.' });
    } finally {
      client.release();
    }
  });

  app.delete('/api/v1/ingredients/:id', authenticate, async (req, res) => {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('DELETE FROM product_recipes WHERE ingredient_id = $1', [req.params.id]);
      await client.query('DELETE FROM ingredient_stock_movements WHERE ingredient_id = $1', [req.params.id]);
      const { rowCount } = await client.query('DELETE FROM ingredients WHERE id = $1', [req.params.id]);
      if (rowCount === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ success: false, message: 'Bahan tidak ditemukan.' });
      }
      await client.query('COMMIT');
      res.json({ success: true, message: 'Bahan berhasil dihapus.' });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(500).json({ success: false, message: 'Gagal menghapus bahan.' });
    } finally {
      client.release();
    }
  });

  app.get('/api/v1/products', authenticate, async (req, res) => {
    try {
      const { rows } = await pool.query(`
        SELECT p.id, p.name, p.category, p.selling_price, p.sku,
               COALESCE((
                 SELECT MIN(FLOOR(i.stock_quantity / r.quantity_per_product))
                 FROM product_recipes r JOIN ingredients i ON i.id = r.ingredient_id
                 WHERE r.product_id = p.id
               ), p.stock)::int AS stock,
               p.image_url,
               p.is_active,
               COALESCE(
                 (
                   SELECT ROUND(SUM(i.cost_per_base_unit * r.quantity_per_product))
                   FROM product_recipes r JOIN ingredients i ON i.id = r.ingredient_id
                   WHERE r.product_id = p.id
                 ),
                 p.cost_price,
                 0
               )::numeric AS cost_price,
               COALESCE(json_agg(json_build_object(
                 'ingredientId', i.id, 'name', i.name, 'quantity', r.quantity_per_product,
                 'unit', i.base_unit, 'unitCost', i.cost_per_base_unit,
                 'lineCost', i.cost_per_base_unit * r.quantity_per_product
               )) FILTER (WHERE i.id IS NOT NULL), '[]') AS recipe
        FROM products p
        LEFT JOIN product_recipes r ON r.product_id = p.id
        LEFT JOIN ingredients i ON i.id = r.ingredient_id
        WHERE ($1::boolean OR p.is_active = TRUE)
        GROUP BY p.id
        ORDER BY p.name ASC
      `, [req.user.role === 'ADMIN' || req.user.role === 'OWNER']);
      res.json({ success: true, data: rows.map((product) => ({
        ...product,
        margin: Number(product.selling_price) - Number(product.cost_price),
      })) });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat produk.' });
    }
  });

  app.post('/api/v1/products', authenticate, requireAdmin, async (req, res) => {
    await saveProduct(req, res, pool, false);
  });

  app.put('/api/v1/products/:id', authenticate, requireAdmin, async (req, res) => {
    await saveProduct(req, res, pool, true);
  });

  app.delete('/api/v1/products/:id', authenticate, requireAdmin, async (req, res) => {
    const { id } = req.params;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('DELETE FROM product_recipes WHERE product_id = $1', [id]);
      await client.query('DELETE FROM order_items WHERE product_id = $1', [id]);
      const { rowCount } = await client.query('DELETE FROM products WHERE id = $1', [id]);
      await client.query('COMMIT');
      if (rowCount === 0) {
        return res.status(404).json({ success: false, message: 'Produk tidak ditemukan.' });
      }
      res.json({ success: true, message: 'Produk berhasil dihapus.' });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(500).json({ success: false, message: 'Gagal menghapus produk: ' + error.message });
    } finally {
      client.release();
    }
  });

  app.post('/api/v1/sync/transactions', authenticate, async (req, res) => {
    const order = req.body;
    if (!order.id || !Array.isArray(order.items) || order.items.length === 0 ||
        !Number.isFinite(Number(order.totalPrice)) ||
        !Number.isFinite(Number(order.paidAmount)) ||
        Number(order.paidAmount) < Number(order.totalPrice)) {
      return res.status(400).json({ success: false, message: 'Data transaksi tidak valid.' });
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const existing = await client.query('SELECT id FROM orders WHERE id = $1', [order.id]);
      if (existing.rows[0]) {
        await client.query('COMMIT');
        return res.json({ success: true, duplicate: true });
      }

      const orderItems = new Map();
      for (const item of order.items) {
        const quantity = Number(item.quantity);
        if (!item.productId || !Number.isInteger(quantity) || quantity <= 0) {
          throw Object.assign(new Error('Item transaksi tidak valid.'), { statusCode: 400 });
        }
        const existing = orderItems.get(item.productId);
        orderItems.set(item.productId, {
          productId: item.productId,
          quantity: (existing?.quantity || 0) + quantity,
        });
      }
      const productIds = [...orderItems.keys()];
      let productResult = await client.query(`
        SELECT id, name, selling_price, cost_price, stock FROM products
        WHERE id = ANY($1::varchar[]) AND is_active = TRUE
        ORDER BY id FOR UPDATE
      `, [productIds]);
      if (productResult.rowCount !== productIds.length) {
        const foundIds = new Set(productResult.rows.map((p) => p.id));
        for (const item of order.items) {
          if (!foundIds.has(item.productId)) {
            const name = item.productName || item.name || 'Produk';
            const price = Number(item.price || item.unitPrice || 0);
            await client.query(`
              INSERT INTO products (id, name, category, selling_price, cost_price, stock, is_active)
              VALUES ($1, $2, $3, $4, $5, $6, TRUE)
              ON CONFLICT (id) DO UPDATE SET is_active = TRUE
            `, [item.productId, name, 'Umum', price, Math.round(price * 0.5), 99]);
          }
        }
        productResult = await client.query(`
          SELECT id, name, selling_price, cost_price, stock FROM products
          WHERE id = ANY($1::varchar[])
          ORDER BY id FOR UPDATE
        `, [productIds]);
      }
      const products = new Map(productResult.rows.map((product) => [product.id, product]));
      const recipeResult = await client.query(`
        SELECT r.product_id, r.ingredient_id, r.quantity_per_product,
               i.name, i.stock_quantity, i.cost_per_base_unit
        FROM product_recipes r JOIN ingredients i ON i.id = r.ingredient_id
        WHERE r.product_id = ANY($1::varchar[])
        ORDER BY r.ingredient_id FOR UPDATE OF i
      `, [productIds]);
      const productsWithRecipes = new Set(recipeResult.rows.map((row) => row.product_id));
      const insufficientProduct = [...orderItems.values()].find((item) =>
        !productsWithRecipes.has(item.productId) &&
        Number(products.get(item.productId).stock) < item.quantity,
      );
      if (insufficientProduct) {
        throw Object.assign(
          new Error(`Stok ${products.get(insufficientProduct.productId).name} tidak cukup.`),
          { statusCode: 409 },
        );
      }
      const requiredIngredients = new Map();
      for (const recipe of recipeResult.rows) {
        const amount = Number(recipe.quantity_per_product) * orderItems.get(recipe.product_id).quantity;
        const required = requiredIngredients.get(recipe.ingredient_id) || {
          id: recipe.ingredient_id,
          name: recipe.name,
          stock: Number(recipe.stock_quantity),
          unitCost: Number(recipe.cost_per_base_unit),
          quantity: 0,
        };
        required.quantity += amount;
        requiredIngredients.set(recipe.ingredient_id, required);
      }
      const insufficient = [...requiredIngredients.values()].find(
        (ingredient) => ingredient.quantity > ingredient.stock,
      );
      if (insufficient) {
        throw Object.assign(
          new Error(`Stok ${insufficient.name} tidak cukup untuk pesanan ini.`),
          { statusCode: 409 },
        );
      }

      let finalOrderNumber = order.orderNumber || order.order_number;
      if (!finalOrderNumber || finalOrderNumber.length > 10 || !/^A-\d+$/i.test(finalOrderNumber)) {
        const seqRes = await client.query(`
          SELECT order_number FROM orders WHERE order_number ~ '^A-\\d+$' ORDER BY created_at DESC LIMIT 1
        `);
        let lastSeq = 0;
        if (seqRes.rows[0]) {
          const digits = seqRes.rows[0].order_number.replace(/\D/g, '');
          lastSeq = parseInt(digits, 10) || 0;
        }
        finalOrderNumber = `A-${String(lastSeq + 1).padStart(5, '0')}`;
      }

      const createdAt = order.createdAt ? new Date(order.createdAt) : new Date();
      await client.query(`
        INSERT INTO orders
          (id, user_id, order_number, subtotal, discount_amount, tax_amount,
           service_amount, service_rate,
           total_price, paid_amount, change_amount, payment_method, status, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'COMPLETED', $13)
      `, [order.id, req.user.id, finalOrderNumber,
        Number(order.subtotal ?? order.totalPrice), Number(order.discountAmount || 0),
        Number(order.tax || 0), Number(order.serviceAmount || 0),
        Number(order.serviceRate || 0), Number(order.totalPrice),
        Number(order.paidAmount), Number(order.changeAmount || 0),
        order.paymentMethod || 'CASH', createdAt]);

      for (const item of orderItems.values()) {
        const product = products.get(item.productId);
        const itemSubtotal = Number(product.selling_price) * item.quantity;
        await client.query(`
          INSERT INTO order_items
            (id, order_id, product_id, product_name, cost_price, selling_price, quantity, subtotal)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        `, [crypto.randomUUID(), order.id, product.id, product.name,
          Number(product.cost_price || 0), Number(product.selling_price), item.quantity, itemSubtotal]);
        await client.query('UPDATE products SET stock = GREATEST(stock - $2, 0) WHERE id = $1',
          [product.id, item.quantity]);
      }

      for (const ingredient of requiredIngredients.values()) {
        await client.query(`
          UPDATE ingredients SET stock_quantity = stock_quantity - $2,
            updated_at = CURRENT_TIMESTAMP WHERE id = $1
        `, [ingredient.id, ingredient.quantity]);
        await client.query(`
          INSERT INTO ingredient_stock_movements
            (id, ingredient_id, user_id, movement_type, quantity_delta,
             unit_cost, total_cost, reference_id, note)
          VALUES ($1, $2, $3, 'SALE', $4, $5, $6, $7, $8)
        `, [crypto.randomUUID(), ingredient.id, req.user.id, -ingredient.quantity,
          ingredient.unitCost, ingredient.quantity * ingredient.unitCost,
          order.id, 'Pemakaian resep transaksi']);
      }

      await client.query('COMMIT');
      res.status(201).json({ success: true, data: { id: order.id } });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(error.statusCode || 500).json({
        success: false,
        message: error.statusCode ? error.message : 'Gagal menyimpan transaksi.',
      });
    } finally {
      client.release();
    }
  });

  app.get('/api/v1/transactions', authenticate, async (req, res) => {
    try {
      const { rows } = await pool.query(`
        SELECT o.id, o.order_number, o.created_at, o.total_price, o.paid_amount,
               o.change_amount, o.payment_method, o.status,
               COALESCE(json_agg(json_build_object(
                 'productId', oi.product_id, 'name', oi.product_name,
                 'quantity', oi.quantity, 'unitPrice', oi.selling_price,
                 'subtotal', oi.subtotal
               ) ORDER BY oi.product_name) FILTER (WHERE oi.id IS NOT NULL), '[]') AS items
        FROM orders o
        LEFT JOIN order_items oi ON oi.order_id = o.id
        GROUP BY o.id
        ORDER BY o.created_at DESC
        LIMIT 200
      `);
      res.json({ success: true, data: rows });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat transaksi.' });
    }
  });

  app.post('/api/v1/transactions/:id/cancel', authenticate, async (req, res) => {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const orderResult = await client.query(
        'SELECT id, status FROM orders WHERE id = $1 FOR UPDATE', [req.params.id],
      );
      const order = orderResult.rows[0];
      if (!order) {
        await client.query('ROLLBACK');
        return res.status(404).json({ success: false, message: 'Transaksi tidak ditemukan.' });
      }
      if (order.status === 'CANCELLED') {
        await client.query('ROLLBACK');
        return res.status(409).json({ success: false, message: 'Transaksi sudah dibatalkan.' });
      }
      const used = await client.query(`
        SELECT ingredient_id, -SUM(quantity_delta) AS quantity
        FROM ingredient_stock_movements
        WHERE reference_id = $1 AND movement_type = 'SALE'
        GROUP BY ingredient_id
      `, [order.id]);
      for (const item of used.rows) {
        await client.query(`
          UPDATE ingredients SET stock_quantity = stock_quantity + $2,
            updated_at = CURRENT_TIMESTAMP WHERE id = $1
        `, [item.ingredient_id, item.quantity]);
        await client.query(`
          INSERT INTO ingredient_stock_movements
            (id, ingredient_id, user_id, movement_type, quantity_delta, reference_id, note)
          VALUES ($1, $2, $3, 'CANCELLATION', $4, $5, $6)
        `, [crypto.randomUUID(), item.ingredient_id, req.user.id, item.quantity,
          order.id, req.body.note || 'Pembatalan transaksi']);
      }
      const soldProducts = await client.query(`
        SELECT product_id, SUM(quantity)::int AS quantity
        FROM order_items WHERE order_id = $1 AND product_id IS NOT NULL
        GROUP BY product_id
      `, [order.id]);
      for (const item of soldProducts.rows) {
        await client.query('UPDATE products SET stock = stock + $2 WHERE id = $1',
          [item.product_id, item.quantity]);
      }
      await client.query("UPDATE orders SET status = 'CANCELLED' WHERE id = $1", [order.id]);
      await client.query('COMMIT');
      res.json({ success: true });
    } catch (error) {
      await client.query('ROLLBACK');
      res.status(500).json({ success: false, message: 'Gagal membatalkan transaksi.' });
    } finally {
      client.release();
    }
  });

  app.get('/api/v1/reports/financial/summary', authenticate, requireAdmin, async (req, res) => {
    const from = req.query.from || new Date().toISOString().slice(0, 10);
    const to = req.query.to || new Date().toISOString().slice(0, 10);
    try {
      const [summaryResult, paymentResult, prevSummaryResult, expenseCategoryResult, ingredientsResult] = await Promise.all([
        pool.query(`
          SELECT COUNT(*)::int AS transaction_count,
                 COALESCE(SUM(o.total_price), 0)::numeric AS sales_total,
                 COALESCE(SUM((
                   SELECT SUM(oi.cost_price * oi.quantity)
                   FROM order_items oi WHERE oi.order_id = o.id
                 )), 0)::numeric AS cost_total,
                 (SELECT COALESCE(SUM(e.amount), 0)::numeric
                  FROM operating_expenses e
                  WHERE e.expense_date BETWEEN $1::date AND $2::date
                    AND e.category NOT LIKE 'Modal Usaha%') AS expense_total
          FROM orders o
          WHERE o.created_at::date BETWEEN $1::date AND $2::date
            AND o.status <> 'CANCELLED'
        `, [from, to]),
        pool.query(`
          SELECT payment_method,
                 COUNT(*)::int AS count,
                 COALESCE(SUM(total_price), 0)::numeric AS total
          FROM orders
          WHERE created_at::date BETWEEN $1::date AND $2::date
            AND status <> 'CANCELLED'
          GROUP BY payment_method
        `, [from, to]),
        pool.query(`
          SELECT COALESCE(SUM(o.total_price), 0)::numeric AS sales_total,
                 COALESCE(SUM((
                   SELECT SUM(oi.cost_price * oi.quantity)
                   FROM order_items oi WHERE oi.order_id = o.id
                 )), 0)::numeric AS cost_total,
                 (SELECT COALESCE(SUM(e.amount), 0)::numeric
                  FROM operating_expenses e
                  WHERE e.expense_date BETWEEN ($1::date - INTERVAL '30 days')::date AND ($2::date - INTERVAL '30 days')::date
                    AND e.category NOT LIKE 'Modal Usaha%') AS expense_total
          FROM orders o
          WHERE o.created_at::date BETWEEN ($1::date - INTERVAL '30 days')::date AND ($2::date - INTERVAL '30 days')::date
            AND o.status <> 'CANCELLED'
        `, [from, to]),
        pool.query(`
          SELECT category, COALESCE(SUM(amount), 0)::numeric AS total
          FROM operating_expenses
          WHERE expense_date BETWEEN $1::date AND $2::date
          GROUP BY category
          ORDER BY total DESC
        `, [from, to]),
        pool.query(`
          SELECT id, name, base_unit, stock_quantity, cost_per_base_unit, low_stock_threshold, created_at, updated_at
          FROM ingredients
          ORDER BY name ASC
        `),
      ]);

      const result = summaryResult.rows[0];
      result.gross_profit = Number(result.sales_total) - Number(result.cost_total);
      result.net_profit = result.gross_profit - Number(result.expense_total);
      result.payment_methods = paymentResult.rows;

      const prev = prevSummaryResult.rows[0];
      result.prev_sales_total = Number(prev.sales_total || 0);
      result.prev_cost_total = Number(prev.cost_total || 0);
      result.prev_expense_total = Number(prev.expense_total || 0);
      result.prev_gross_profit = result.prev_sales_total - result.prev_cost_total;
      result.prev_net_profit = result.prev_gross_profit - result.prev_expense_total;
      result.ingredients = ingredientsResult.rows;
      result.expense_categories = expenseCategoryResult.rows;

      res.json({ success: true, data: result });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat laporan keuangan.' });
    }
  });

  app.get('/api/v1/reports/financial/audit-trail', authenticate, requireAdmin, async (req, res) => {
    const from = req.query.from || new Date().toISOString().slice(0, 10);
    const to = req.query.to || new Date().toISOString().slice(0, 10);
    try {
      const { rows } = await pool.query(`
        (
          SELECT o.id, 'MASUK' AS type,
                 'Penjualan ' || COALESCE(o.order_number, SUBSTRING(o.id FROM 1 FOR 6)) ||
                 COALESCE(' (' || (
                   SELECT STRING_AGG(oi.quantity || ' ' || oi.product_name, ', ')
                   FROM order_items oi WHERE oi.order_id = o.id
                 ) || ')', '') AS title,
                 o.payment_method AS category,
                 o.total_price::numeric AS amount,
                 o.created_at AS timestamp
          FROM orders o
          WHERE o.created_at::date BETWEEN $1::date AND $2::date
            AND o.status <> 'CANCELLED'
        )
        UNION ALL
        (
          SELECT e.id, 'KELUAR' AS type, e.description AS title,
                 e.category AS category, e.amount::numeric AS amount, e.created_at AS timestamp
          FROM operating_expenses e
          WHERE e.expense_date BETWEEN $1::date AND $2::date
        )
        ORDER BY timestamp DESC
        LIMIT 100
      `, [from, to]);
      res.json({ success: true, data: rows });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat jurnal arus kas.' });
    }
  });

  app.get('/api/v1/reports/financial/profit-breakdown', authenticate, requireAdmin, async (req, res) => {
    const from = req.query.from || new Date().toISOString().slice(0, 10);
    const to = req.query.to || new Date().toISOString().slice(0, 10);
    try {
      const { rows } = await pool.query(`
        SELECT oi.product_name AS name,
               COALESCE(p.category, 'Tanpa kategori') AS category,
               SUM(oi.quantity)::int AS quantity,
               COALESCE(SUM(oi.subtotal), 0)::numeric AS revenue,
               COALESCE(SUM(oi.cost_price * oi.quantity), 0)::numeric AS cost,
               COALESCE(SUM(oi.subtotal - oi.cost_price * oi.quantity), 0)::numeric AS gross_profit
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        LEFT JOIN products p ON p.id = oi.product_id
        WHERE o.created_at::date BETWEEN $1::date AND $2::date
          AND o.status <> 'CANCELLED'
        GROUP BY oi.product_name, p.category
        ORDER BY oi.product_name ASC
      `, [from, to]);
      res.json({ success: true, data: rows });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat rincian HPP produk.' });
    }
  });

  app.get('/api/v1/reports/financial/expenses', authenticate, requireAdmin, async (req, res) => {
    const from = req.query.from || new Date().toISOString().slice(0, 10);
    const to = req.query.to || new Date().toISOString().slice(0, 10);
    try {
      const { rows } = await pool.query(`
        SELECT id, expense_date, category, description, amount
        FROM operating_expenses
        WHERE expense_date BETWEEN $1::date AND $2::date
        ORDER BY expense_date DESC, created_at DESC
      `, [from, to]);
      res.json({ success: true, data: rows });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat biaya operasional.' });
    }
  });

  app.post('/api/v1/reports/financial/expenses', authenticate, requireAdmin, async (req, res) => {
    const { expenseDate, category, description, amount } = req.body ?? {};
    const parsedAmount = Number(amount);
    const parsedDate = /^\d{4}-\d{2}-\d{2}$/.test(expenseDate || '')
      ? new Date(`${expenseDate}T00:00:00.000Z`)
      : null;
    if (!parsedDate || Number.isNaN(parsedDate.getTime()) ||
        parsedDate.toISOString().slice(0, 10) !== expenseDate ||
        typeof category !== 'string' || !category.trim() ||
        typeof description !== 'string' || !description.trim() ||
        !Number.isFinite(parsedAmount) || parsedAmount <= 0) {
      return res.status(400).json({ success: false, message: 'Tanggal, kategori, keterangan, dan jumlah biaya wajib diisi dengan benar.' });
    }
    try {
      const { rows } = await pool.query(`
        INSERT INTO operating_expenses
          (id, expense_date, category, description, amount, created_by)
        VALUES ($1, $2::date, $3, $4, $5, $6)
        RETURNING id, expense_date, category, description, amount
      `, [crypto.randomUUID(), expenseDate, category.trim(), description.trim(), parsedAmount, req.user.id]);
      res.status(201).json({ success: true, data: rows[0] });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal menyimpan biaya operasional.' });
    }
  });

  app.delete('/api/v1/reports/financial/expenses/:id', authenticate, requireAdmin, async (req, res) => {
    try {
      const { rowCount } = await pool.query(
        'DELETE FROM operating_expenses WHERE id = $1',
        [req.params.id],
      );
      if (rowCount === 0) {
        return res.status(404).json({ success: false, message: 'Biaya operasional tidak ditemukan.' });
      }
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal menghapus biaya operasional.' });
    }
  });

  app.get('/api/v1/reports/financial/export.xlsx', authenticate, requireAdmin, async (req, res) => {
    const from = req.query.from || new Date().toISOString().slice(0, 10);
    const to = req.query.to || new Date().toISOString().slice(0, 10);
    try {
      const [summaryResult, productsResult, expensesResult] = await Promise.all([
        pool.query(`
          SELECT COUNT(*)::int AS transaction_count,
               COALESCE(SUM(o.total_price), 0)::numeric AS sales_total,
               COALESCE(SUM((
                 SELECT SUM(oi.cost_price * oi.quantity)
                 FROM order_items oi WHERE oi.order_id = o.id
               )), 0)::numeric AS cost_total,
               (SELECT COALESCE(SUM(e.amount), 0)::numeric
                FROM operating_expenses e
                WHERE e.expense_date BETWEEN $1::date AND $2::date) AS expense_total
          FROM orders o
          WHERE o.created_at::date BETWEEN $1::date AND $2::date
            AND o.status <> 'CANCELLED'
        `, [from, to]),
        pool.query(`
          SELECT oi.product_name AS name,
               COALESCE(p.category, 'Tanpa kategori') AS category,
               SUM(oi.quantity)::int AS quantity,
               COALESCE(SUM(oi.subtotal), 0)::numeric AS revenue,
               COALESCE(SUM(oi.cost_price * oi.quantity), 0)::numeric AS cost,
               COALESCE(SUM(oi.subtotal - oi.cost_price * oi.quantity), 0)::numeric AS gross_profit
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
          LEFT JOIN products p ON p.id = oi.product_id
          WHERE o.created_at::date BETWEEN $1::date AND $2::date
            AND o.status <> 'CANCELLED'
          GROUP BY oi.product_name, p.category
          ORDER BY oi.product_name ASC
        `, [from, to]),
        pool.query(`
          SELECT expense_date, category, description, amount
          FROM operating_expenses
          WHERE expense_date BETWEEN $1::date AND $2::date
          ORDER BY expense_date ASC, created_at ASC
        `, [from, to]),
      ]);
      const summary = summaryResult.rows[0];
      const sales = Number(summary.sales_total);
      const cost = Number(summary.cost_total);
      const expenses = Number(summary.expense_total);
      const workbook = new ExcelJS.Workbook();
      const overview = workbook.addWorksheet('Ringkasan');
      overview.addRows([
        ['Laporan keuangan POS', ''],
        ['Periode', `${from} sampai ${to}`],
        ['Penjualan', sales],
        ['HPP terjual', cost],
        ['Laba kotor', sales - cost],
        ['Biaya operasional', expenses],
        ['Laba bersih', sales - cost - expenses],
        ['Jumlah transaksi', Number(summary.transaction_count)],
      ]);
      const productSheet = workbook.addWorksheet('HPP per produk');
      productSheet.addRow(['Produk', 'Kategori', 'Jumlah terjual', 'Penjualan', 'HPP', 'Laba kotor']);
      productsResult.rows.forEach((row) => productSheet.addRow([
        row.name, row.category, Number(row.quantity), Number(row.revenue),
        Number(row.cost), Number(row.gross_profit),
      ]));
      const expenseSheet = workbook.addWorksheet('Biaya operasional');
      expenseSheet.addRow(['Tanggal', 'Kategori', 'Keterangan', 'Jumlah']);
      expensesResult.rows.forEach((row) => expenseSheet.addRow([
        row.expense_date, row.category, row.description, Number(row.amount),
      ]));
      [overview, productSheet, expenseSheet].forEach((sheet) => {
        sheet.getRow(1).font = { bold: true };
        sheet.columns.forEach((column) => {
          column.width = Math.min(
            42,
            Math.max(14, ...sheet.getColumn(column.number).values.map((value) => String(value ?? '').length + 2)),
          );
        });
      });
      const buffer = await workbook.xlsx.writeBuffer();
      res.set({
        'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'Content-Disposition': `attachment; filename="laporan-keuangan-${from}-${to}.xlsx"`,
      });
      res.send(Buffer.from(buffer));
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal membuat ekspor Excel laporan keuangan.' });
    }
  });

  app.get('/api/v1/settings', authenticate, requireAdmin, async (req, res) => {
    try {
      const { rows } = await pool.query('SELECT setting_key, setting_value FROM store_settings');
      res.json({ success: true, data: Object.fromEntries(rows.map((row) => [row.setting_key, row.setting_value])) });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal memuat pengaturan.' });
    }
  });

  app.put('/api/v1/settings/:key', authenticate, requireAdmin, async (req, res) => {
    if (!allowedSettings.has(req.params.key)) {
      return res.status(404).json({ success: false, message: 'Pengaturan tidak dikenal.' });
    }
    try {
      const { rows } = await pool.query(`
        INSERT INTO store_settings (setting_key, setting_value, updated_at)
        VALUES ($1, $2::jsonb, CURRENT_TIMESTAMP)
        ON CONFLICT (setting_key) DO UPDATE SET
          setting_value = EXCLUDED.setting_value, updated_at = CURRENT_TIMESTAMP
        RETURNING setting_key, setting_value
      `, [req.params.key, JSON.stringify(req.body.value ?? {})]);
      res.json({ success: true, data: rows[0] });
    } catch (error) {
      res.status(500).json({ success: false, message: 'Gagal menyimpan pengaturan.' });
    }
  });
}

async function saveProduct(req, res, pool, isUpdate) {
  const { name, category, sellingPrice, costPrice, sku = null, imageUrl = null, isActive = true, recipe = [] } = req.body;
  if (!name || !category || !Number.isFinite(Number(sellingPrice)) ||
      Number(sellingPrice) < 0 || !Array.isArray(recipe)) {
    return res.status(400).json({ success: false, message: 'Data produk tidak valid.' });
  }
  const client = await pool.connect();
  const id = isUpdate ? req.params.id : crypto.randomUUID();
  const manualCost = Number.isFinite(Number(costPrice)) ? Number(costPrice) : 0;
  const activeBool = isActive !== false;

  try {
    await client.query('BEGIN');
    if (isUpdate) {
      const existing = await client.query('SELECT id FROM products WHERE id = $1 FOR UPDATE', [id]);
      if (!existing.rows[0]) {
        await client.query('ROLLBACK');
        return res.status(404).json({ success: false, message: 'Produk tidak ditemukan.' });
      }
      await client.query(`
        UPDATE products SET
          name = $2,
          category = $3,
          selling_price = $4,
          cost_price = $5,
          sku = $6,
          image_url = $7,
          is_active = $8,
          updated_at = CURRENT_TIMESTAMP
        WHERE id = $1
      `, [id, name.trim(), category, Number(sellingPrice), manualCost, sku, imageUrl, activeBool]);
      await client.query('DELETE FROM product_recipes WHERE product_id = $1', [id]);
    } else {
      await client.query(`
        INSERT INTO products (id, name, category, selling_price, cost_price, sku, image_url, is_active)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      `, [id, name.trim(), category, Number(sellingPrice), manualCost, sku, imageUrl, activeBool]);
    }

    for (const item of recipe) {
      const quantity = Number(item.quantity);
      if (!item.ingredientId || !Number.isFinite(quantity) || quantity <= 0) {
        throw new Error('Resep produk tidak valid.');
      }
      await client.query(`
        INSERT INTO product_recipes (product_id, ingredient_id, quantity_per_product)
        VALUES ($1, $2, $3)
      `, [id, item.ingredientId, quantity]);
    }

    if (recipe.length > 0) {
      await client.query(`
        UPDATE products p SET cost_price = COALESCE((
          SELECT ROUND(SUM(i.cost_per_base_unit * r.quantity_per_product))
          FROM product_recipes r JOIN ingredients i ON i.id = r.ingredient_id
          WHERE r.product_id = p.id
        ), p.cost_price)::int
        WHERE p.id = $1
      `, [id]);
    }

    const { rows } = await client.query(`
      SELECT id, name, category, selling_price, cost_price, sku, image_url, is_active
      FROM products WHERE id = $1
    `, [id]);

    await client.query('COMMIT');
    const product = rows[0];
    product.margin = Number(product.selling_price) - Number(product.cost_price);
    res.status(isUpdate ? 200 : 201).json({ success: true, data: product });
  } catch (error) {
    await client.query('ROLLBACK');
    res.status(400).json({ success: false, message: error.message || 'Gagal menyimpan produk.' });
  } finally {
    client.release();
  }
}

module.exports = { installAdminRoutes };