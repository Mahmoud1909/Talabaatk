// index.js
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(express.json());
app.use(cors({ origin: true })); // ضبط الأصل حسب حاجتك في الإنتاج

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  // إذا تحتاج SSL في بيئة الإنتاج:
  // ssl: { rejectUnauthorized: false }
});

app.get('/health', (_req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

// GET /api/branches/:id/delivery?lat=...&lng=...&price=50
app.get('/api/branches/:id/delivery', async (req, res) => {
  try {
    const branchId = req.params.id;
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const price = req.query.price ? parseFloat(req.query.price) : 50;

    if (!branchId) return res.status(400).json({ error: 'Missing branch id' });
    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      return res.status(400).json({ error: 'Missing or invalid lat/lng' });
    }
    if (Number.isNaN(price) || price <= 0) {
      return res.status(400).json({ error: 'Invalid price' });
    }

    const client = await pool.connect();
    try {
      // نادى الدالة SQL الموجودة في Postgres
      const q = `SELECT * FROM public.compute_delivery_for_branch($1::uuid, $2::double precision, $3::double precision, $4::numeric)`;
      const r = await client.query(q, [branchId, lat, lng, price]);

      if (!r.rows || r.rows.length === 0) {
        return res.status(404).json({ error: 'Branch not found or no result' });
      }

      const row = r.rows[0];
      return res.json({
        distance_m: Number(row.distance_m),
        distance_km: Number(row.distance_km),
        charged_km: Number(row.charged_km),
        cost: Number(row.cost),
      });
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('delivery endpoint error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`delivery API listening on ${port}`));
