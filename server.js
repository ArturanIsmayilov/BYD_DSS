// ============================================================
//  BYD KDS — Operasyon & Fabrika Karar Destek Sistemi
//  ÇALIŞAN KODA SİMÜLASYON EKLENDİ + KARAKTER DÜZELTMELİ
// ============================================================

const express = require("express");
const mysql = require("mysql2/promise");
const path = require("path");
const cors = require("cors");

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(__dirname));

// ======== MYSQL GİRİŞ BİLGİLERİ  ========
const DB = {
  host: "localhost",
  user: "root",
  password: "@05okTRN.", // Şifreni kontrol et
  database: "byd_kds_demo",
  port: 3306,
  charset: "utf8mb4" // BU ÇOK ÖNEMLİ
};
// ======================================

async function getConn() {
  const conn = await mysql.createConnection(DB);
  // BU İKİ SATIR KARAKTER SORUNUNU ÇÖZER
  await conn.query('SET NAMES utf8mb4');
  await conn.query('SET CHARACTER SET utf8mb4');
  return conn;
}

// Hata Yönetimi Yardımcısı
const handleApiError = (res, error, message, endpoint) => {
    console.error(`API Error (${endpoint}): ${message}`, error);
    res.status(500).json({ error: message || "Sunucu hatası oluştu." });
};

// === API Endpointleri (SENİN KODUNLA AYNI) ===
app.get("/", (req, res) => res.sendFile(path.join(__dirname, "index.html")));
app.get("/api/health", (req, res) => res.json({ ok: true, db: DB.database }));

app.get("/api/dealers", async (req, res) => {
  let conn;
  try {
    conn = await getConn();
    const [rows] = await conn.execute(`SELECT d.id, d.name, c.name AS city, d.lat, d.lon, c.region FROM dealer d JOIN city c ON d.city_id = c.id`);
    res.json(rows);
  } catch (error) {
     handleApiError(res, error, "Bayi verileri alınamadı.", "/api/dealers");
  } finally {
      if (conn) await conn.end();
  }
});
app.get("/api/potential_cities", async (req, res) => {
    let conn;
    try {
        conn = await getConn();
        // Bayi tablosunda (dealer) id'si bulunmayan şehirleri (city) getirir
        const [rows] = await conn.execute(`
            SELECT id, name, lat, lon 
            FROM city 
            WHERE id NOT IN (SELECT city_id FROM dealer)
        `);
        res.json(rows);
    } catch (error) {
        res.status(500).json({ error: "Potansiyel şehirler çekilemedi." });
    } finally {
        if (conn) await conn.end();
    }
});
app.get("/api/candidate_sites", async (req, res) => {
    let conn;
    try {
        conn = await getConn();
        const [rows] = await conn.execute("SELECT * FROM candidate_site");
        res.json(rows);
    } catch (error) {
        handleApiError(res, error, "Aday saha verileri alınamadı.", "/api/candidate_sites");
    } finally {
        if(conn) await conn.end();
    }
});


app.get("/api/city_demand", async (req, res) => {
    let conn;
    try {
        conn = await getConn();
        const [rows] = await conn.execute(`SELECT c.id, c.name AS city, c.region, cd.demand_index FROM city_demand cd JOIN city c ON cd.city_id = c.id`);
        res.json(rows);
    } catch (error) {
        handleApiError(res, error, "Şehir talep verileri alınamadı.", "/api/city_demand");
    } finally {
        if (conn) await conn.end();
    }
});

// KPI (SENİN KODUNLA AYNI - ŞEHİR BAZLI DÖNÜYOR)
app.get("/api/kpis", async (req, res) => {
  let conn;
  try {
      const { model } = req.query; // Model filtresini al
      conn = await getConn();
      
      let ordersQuery = `SELECT o.*, c.name AS city, vm.model_name 
                         FROM orders o 
                         JOIN dealer d ON o.dealer_id = d.id 
                         JOIN city c ON d.city_id = c.id
                         JOIN vehicle_model vm ON o.model_id = vm.id`;
      
      let params = [];
      if (model) {
          ordersQuery += ` WHERE vm.model_name = ?`;
          params.push(model);
      }

      const [ordersResult, stockResult] = await Promise.all([
          conn.execute(ordersQuery, params),
          conn.execute(`SELECT SUM(qty) as total_stock FROM inventory`)
      ]);
      
      const orders = ordersResult[0];
      const stock = stockResult[0];

      // Şehir bazlı hesaplama (Aynı kalıyor)
      const byCity = {};
      for (const o of orders) {
          const city = o.city;
          if (!byCity[city]) byCity[city] = { total: 0, ontime: 0, totalDelay: 0 };
          byCity[city].total++;
          if (o.delivered && o.actual_minutes <= o.planned_minutes) byCity[city].ontime++;
          byCity[city].totalDelay += Math.max(0, o.actual_minutes - o.planned_minutes);
      }
      
      const cityKpis = Object.entries(byCity).map(([city, v]) => ({
          city,
          on_time_rate: v.total ? (v.ontime / v.total) * 100 : 0,
          avg_delay_minutes: v.total ? v.totalDelay / v.total : 0,
          total_orders: v.total,
      }));

      // Genel toplamlar (Artık modele göre filtrelenmiş olabilir)
      let totalOrdersAgg = orders.length;
      let totalDelayAgg = 0;
      let totalOnTimeAgg = 0;
      orders.forEach(o => {
          totalDelayAgg += Math.max(0, o.actual_minutes - o.planned_minutes);
          if (o.delivered && o.actual_minutes <= o.planned_minutes) totalOnTimeAgg++;
      });

      const overallKpis = {
          total_orders: totalOrdersAgg,
          avg_delay: totalOrdersAgg ? Math.round((totalDelayAgg / totalOrdersAgg) * 100) / 100 : 0,
          on_time_rate: totalOrdersAgg ? Math.round((totalOnTimeAgg / totalOrdersAgg) * 1000) / 10 : 0,
          total_stock: stock[0]?.total_stock || 0
      };

      res.json({ overall: overallKpis, byCity: cityKpis });
  } catch (error) {
      handleApiError(res, error, "KPI verileri alınamadı.", "/api/kpis");
  } finally {
      if (conn) await conn.end();
  }
});


// === YENİ: Skorlama Fonksiyonu (Simülasyon için) ===
async function calculateScores(weights, siteOverrides = {}) {
    let conn;
    try {
        conn = await getConn();
        let [sites] = await conn.execute(`SELECT cs.*, c.region FROM candidate_site cs JOIN city c ON cs.city_id = c.id WHERE cs.land_cost_per_m2 IS NOT NULL AND cs.labor_index IS NOT NULL AND cs.altyapi_endeksi IS NOT NULL AND cs.supplier_proximity_km IS NOT NULL`);
        const [demands] = await conn.execute(`SELECT c.name AS city, cd.demand_index, c.lat, c.lon FROM city_demand cd JOIN city c ON cd.city_id = c.id WHERE cd.demand_index IS NOT NULL`);

        // Override'ları uygula
        if (siteOverrides.regionCostChange && siteOverrides.regionCostChange.region && siteOverrides.regionCostChange.percentage !== undefined) {
             sites = sites.map(s => {
                if (s.region === siteOverrides.regionCostChange.region) {
                    const changeFactor = 1 + (siteOverrides.regionCostChange.percentage / 100);
                    const newCost = Math.max(0, s.land_cost_per_m2 * changeFactor);
                    return { ...s, land_cost_per_m2: newCost };
                }
                return s;
            });
        }

        const toRad = (v) => (v * Math.PI) / 180;
        const haversine = (lat1, lon1, lat2, lon2) => {
            const R = 6371; const dLat = toRad(lat2 - lat1); const dLon = toRad(lon2 - lon1);
            const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
            return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        };

        const demandRaw = [], landRaw = [], laborRaw = [], infraRaw = [], supplierRaw = [];

        for (const s of sites) {
             try {
                let demandSum = 0;
                if (demands && demands.length > 0) {
                     for (const c of demands) { const dist = Math.max(1, haversine(s.lat, s.lon, c.lat, c.lon)); demandSum += (c.demand_index || 0) / dist; }
                }
                demandRaw.push(demandSum);
                landRaw.push(1 / Math.max(1, s.land_cost_per_m2 || 1));
                laborRaw.push(s.labor_index || 0);
                infraRaw.push(s.altyapi_endeksi || 0);
                supplierRaw.push(1 / Math.max(1, s.supplier_proximity_km || 1));
             } catch (siteError) { demandRaw.push(0); landRaw.push(0); laborRaw.push(0); infraRaw.push(0); supplierRaw.push(0); }
        }

        const norm = (arr) => {
            if (!arr || arr.length === 0) return [];
            const validValues = arr.filter(v => typeof v === 'number' && isFinite(v) && v >= 0);
            if (validValues.length === 0) return arr.map(() => 0.5);
            const min = Math.min(...validValues); const max = Math.max(...validValues);
            if (max === min || max === 0) { return arr.map(v => (typeof v === 'number' && isFinite(v) && v >= 0) ? 0.5 : 0); }
            return arr.map(v => (typeof v === 'number' && isFinite(v) && v >= 0) ? (v - min) / (max - min) : 0);
        };

        const nDemand = norm(demandRaw); const nLand = norm(landRaw); const nLabor = norm(laborRaw); const nInfra = norm(infraRaw); const nSupplier = norm(supplierRaw);

        // Skorları 100 üzerinden hesapla ve sırala
        const results = sites.map((s, i) => {
            const w = {
                demand: Number(weights?.demand) || 0,
                land: Number(weights?.land) || 0,
                labor: Number(weights?.labor) || 0,
                infra: Number(weights?.infra) || 0,
                supplier: Number(weights?.supplier) || 0
            };

            const score = (nDemand[i] * w.demand) + (nLand[i] * w.land) + (nLabor[i] * w.labor) + (nInfra[i] * w.infra) + (nSupplier[i] * w.supplier);
            
            return { 
                ...s, 
                score: isNaN(score) ? 0 : Math.round(score * 10000) / 100 
            };
        });

        // Backend tarafında sıralamayı yapıp gönderiyoruz
        return results.sort((a, b) => (b.score || 0) - (a.score || 0));
        

    } catch (error) { console.error("calculateScores error:", error); throw error; }
    finally { if (conn) await conn.end(); }
}

// === FABRİKA YERİ ANALİZİ (SENİN KODUNLA AYNI, SADECE calculateScores kullanıyor) ===
app.get("/api/score_sites", async (req, res) => {
  const defaultWeights = { demand: 0.30, land: 0.15, labor: 0.10, infra: 0.15, supplier: 0.10 }; // Default'ları başa aldım
  const weights = {
      demand: parseFloat(req.query.w_demand) || defaultWeights.demand,
      land: parseFloat(req.query.w_land) || defaultWeights.land,
      labor: parseFloat(req.query.w_labor) || defaultWeights.labor,
      infra: parseFloat(req.query.w_infra) || defaultWeights.infra, // Bu altyapi_endeksi ile eşleşir
      supplier: parseFloat(req.query.w_supplier) || defaultWeights.supplier,
  };
  try {
      const results = await calculateScores(weights); // Dışarı alınan fonksiyonu çağır
      res.json({ weights, results });
  } catch (error) {
      handleApiError(res, error, "Skorlama sırasında bir hata oluştu.", "/api/score_sites");
  }
});
// csv dosyasini okuyalim
app.post("/api/export_report", (req, res) => {
    const { data } = req.body;
    const format = req.query.format;

    if (format === 'csv') {
        let csvContent = "Saha Adi,Simulasyon Skoru,Arsa Maliyeti\n";
        data.forEach(row => {
            // Excel'in TL sembolünü ve noktalamayı doğru tanıması için temizleme yapıyoruz
            csvContent += `${row.name},${row.score},"${row.cost}"\n`;
        });
        
        res.setHeader('Content-Type', 'text/csv; charset=utf-8');
        res.attachment('BYD_KDS_Analiz_Raporu.csv');
        return res.send("\uFEFF" + csvContent); // Excel Türkçe karakterler için BOM ekledik
    }
    res.status(400).send("Format desteklenmiyor.");
});
// === YENİ: SİMÜLASYON API'I ===
app.post("/api/simulate_scoring", async (req, res) => {
    const { weights, siteOverrides } = req.body;
    const simWeights = {
      demand: parseFloat(weights?.demand) || 0.30,
      land: parseFloat(weights?.land) || 0.15,
      labor: parseFloat(weights?.labor) || 0.10,
      infra: parseFloat(weights?.infra) || 0.15,
      supplier: parseFloat(weights?.supplier) || 0.10,
    };
    try {
        const results = await calculateScores(simWeights, siteOverrides);
        res.json({ weights: simWeights, overrides: siteOverrides, results });
    } catch (error) {
        handleApiError(res, error, "Simülasyon sırasında bir hata oluştu.", "/api/simulate_scoring");
    }
});


// === Diğer API'lar (SENİN KODUNLA AYNI + Hata Yönetimi) ===
// server.js içindeki /api/all_site_details endpoint'ini bulun
app.get("/api/all_site_details", async (req, res) => {
    let conn;
    try {
        conn = await getConn();
        const [rows] = await conn.execute(`
            SELECT 
                cs.id, cs.name AS site_name, c.name AS city_name, 
                cs.land_cost_per_m2, cs.labor_index, cs.altyapi_endeksi, 
                cs.logistics_index, cs.supplier_proximity_km, 
                cd.demand_index, rp.earthquake_risk_pct, iz.zone_name,
                -- BU SATIRI EKLİYORUZ:
                (SELECT IFNULL(SUM(qty), 0) FROM inventory i JOIN dealer d ON i.dealer_id = d.id WHERE d.city_id = c.id) as city_stock
            FROM candidate_site cs 
            JOIN city c ON cs.city_id = c.id 
            JOIN risk_profile rp ON cs.risk_profile_id = rp.id 
            JOIN incentive_zone iz ON cs.incentive_zone_id = iz.id 
            LEFT JOIN city_demand cd ON cs.city_id = cd.city_id 
            ORDER BY c.name, cs.name`);
        res.json(rows);
    } catch(error) { handleApiError(res, error, "Hata", "/api/all_site_details"); }
    finally { if (conn) await conn.end(); }
});
app.get("/api/site_detail/:id", async (req, res) => {
    let conn;
     try{
        const { id } = req.params;
        conn = await getConn();
        const [rows] = await conn.execute(`SELECT cs.id, cs.name AS site_name, c.name AS city_name, cs.lat, cs.lon, cs.land_cost_per_m2, cs.labor_index, cs.altyapi_endeksi, cs.supplier_proximity_km, cs.logistics_index, cs.energy_capacity_mw, cs.notes, cd.demand_index, cd.population, cd.growth_pct, rp.earthquake_risk_pct, rp.flood_risk_pct, rp.supply_disruption_risk_pct, iz.zone_name, iz.tax_rebate_pct, iz.sgk_support_months, iz.investment_grant_pct FROM candidate_site cs JOIN city c ON cs.city_id = c.id JOIN risk_profile rp ON cs.risk_profile_id = rp.id JOIN incentive_zone iz ON cs.incentive_zone_id = iz.id LEFT JOIN city_demand cd ON cs.city_id = cd.city_id WHERE cs.id = ?`, [id]);
        res.json(rows[0] || null);
     } catch(error){ handleApiError(res, error, "Site detayı alınamadı.", `/api/site_detail/${req.params.id}`); }
     finally { if (conn) await conn.end(); }
});
app.get("/api/vehicle_model", async (req, res) => {
    let conn;
    try{
        conn = await getConn();
        const [rows] = await conn.execute("SELECT id, model_name FROM vehicle_model");
        res.json(rows);
    } catch(error){ handleApiError(res, error, "Araç modelleri alınamadı.", "/api/vehicle_model"); }
    finally { if (conn) await conn.end(); }
});
app.get("/api/inventory", async (req, res) => {
    let conn;
    try {
        conn = await getConn();
        const [rows] = await conn.execute(`SELECT c.name AS city, v.model_name, SUM(i.qty) AS total_qty FROM inventory i JOIN dealer d ON i.dealer_id = d.id JOIN vehicle_model v ON i.model_id = v.id JOIN city c ON d.city_id = c.id GROUP BY c.name, v.model_name ORDER BY c.name, v.model_name`);
        res.json(rows);
    } catch (error) {
        handleApiError(res, error, "Envanter özeti alınamadı.", "/api/inventory");
    } finally {
        if (conn) await conn.end();
    }
});
app.get("/api/sales_by_model", async (req, res) => {
    let conn;
    try{
        conn = await getConn();
        const [rows] = await conn.execute(`SELECT vm.model_name AS model, COUNT(*) AS orders FROM orders o JOIN vehicle_model vm ON o.model_id = vm.id WHERE o.delivered = 1 GROUP BY vm.model_name ORDER BY orders DESC`);
        res.json(rows);
    } catch(error){ handleApiError(res, error, "Model bazlı satış verileri alınamadı.", "/api/sales_by_model"); }
    finally { if (conn) await conn.end(); }
});
app.get("/api/potential_cities", async (req, res) => {
    let conn;
    try {
        conn = await getConn();
        const [rows] = await conn.execute(`
            SELECT id, name, lat, lon FROM city 
            WHERE id NOT IN (SELECT city_id FROM dealer)
        `);
        res.json(rows);
    } catch (error) {
        res.status(500).json({ error: "Hata" });
    } finally {
        if (conn) await conn.end();
    }
});

// ======== SERVER ========
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`✅ Server çalışıyor: http://localhost:${PORT}`);
  console.log(`✅ MySQL bağlantısı: ${DB.user}@${DB.host}:${DB.port}/${DB.database}`);
});