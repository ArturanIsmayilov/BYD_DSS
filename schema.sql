/* BAŞLANGIÇ: Bu 3 satır, Türkçe karakterleri (İ,ş,ğ) garanti eder */
SET NAMES 'utf8mb4';
SET CHARACTER SET 'utf8mb4';
SET collation_connection = 'utf8mb4_unicode_ci';

-- =========================================================
-- BYD KDS - Türkiye Fabrika Yeri Analizi için Zengin Şema
-- =========================================================
DROP DATABASE IF EXISTS byd_kds_demo;
CREATE DATABASE byd_kds_demo CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE byd_kds_demo;

-- -------------------------
-- 1) Referans Tabloları
-- -------------------------
CREATE TABLE city (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(64) NOT NULL,
  lat DOUBLE NOT NULL,
  lon DOUBLE NOT NULL,
  region VARCHAR(64) NOT NULL
);

CREATE TABLE incentive_zone (
  id INT AUTO_INCREMENT PRIMARY KEY,
  zone_name VARCHAR(64) NOT NULL,     -- Örn: "Bölge 1 Teşvik", "OSB Ekstra"
  tax_rebate_pct INT NOT NULL,        -- Kurumlar vergisi indirimi % (0-100)
  sgk_support_months INT NOT NULL,    -- SGK işveren payı desteği (ay)
  investment_grant_pct INT NOT NULL   -- Yatırım katkı oranı % (0-100)
);

CREATE TABLE supplier_cluster (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(128) NOT NULL,         -- Örn: "Marmara Otomotiv Yan Sanayi"
  city_id INT NOT NULL,
  avg_distance_km INT NOT NULL,       -- Şehir merkezine ortalama uzaklık
  specialization VARCHAR(128),        -- Örn: "Batarya", "Şasi", "Plastik"
  FOREIGN KEY (city_id) REFERENCES city(id)
);

CREATE TABLE risk_profile (
  id INT AUTO_INCREMENT PRIMARY KEY,
  city_id INT NOT NULL,
  earthquake_risk_pct INT NOT NULL,   -- 0-100
  flood_risk_pct INT NOT NULL,        -- 0-100
  supply_disruption_risk_pct INT NOT NULL, -- 0-100
  FOREIGN KEY (city_id) REFERENCES city(id)
);

-- -------------------------
-- 2) Aday Sahalar (Ana Tablo)
-- -------------------------
CREATE TABLE candidate_site (
  id INT AUTO_INCREMENT PRIMARY KEY,
  city_id INT NOT NULL,
  name VARCHAR(128) NOT NULL,
  lat DOUBLE NOT NULL,
  lon DOUBLE NOT NULL,

  -- Maliyet / İşgücü / Altyapı
  land_cost_per_m2 DECIMAL(12,2) NOT NULL,  -- TL/m² (net değer, 5x YOK)
  labor_index INT NOT NULL,                 -- 0-100 (yüksek = daha iyi, maliyet/donanım dengeli)
  altyapi_endeksi INT NOT NULL,             -- 0-100 (enerji, su, yol, fiber vs.)

  -- Tedarik ve taşıma
  supplier_proximity_km INT NOT NULL,       -- En yakın yoğun tedarik kümesine km
  logistics_index INT NOT NULL,             -- 0-100 (liman/karayolu/demiryolu erişimi)
  energy_capacity_mw INT NOT NULL,          -- Sanayi tahsis edilebilir güç (MW)

  -- Risk & Teşvik
  risk_profile_id INT NOT NULL,             -- risk_profile.id
  incentive_zone_id INT NOT NULL,           -- incentive_zone.id

  -- Notlar
  zoning_ready BOOLEAN NOT NULL DEFAULT 1,  -- İmar/OSB hazır mı
  notes VARCHAR(255),

  FOREIGN KEY (city_id) REFERENCES city(id),
  FOREIGN KEY (risk_profile_id) REFERENCES risk_profile(id),
  FOREIGN KEY (incentive_zone_id) REFERENCES incentive_zone(id)
);

-- -------------------------
-- 3) Talep & Satış Ekosistemi
-- -------------------------
CREATE TABLE vehicle_model (
  id INT AUTO_INCREMENT PRIMARY KEY,
  model_code VARCHAR(50),
  model_name VARCHAR(100),
  type VARCHAR(50)  -- EV / Hybrid / SUV / Commercial
);

CREATE TABLE dealer (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100),
  city_id INT NOT NULL,
  lat DOUBLE NOT NULL,
  lon DOUBLE NOT NULL,
  region VARCHAR(50),
  FOREIGN KEY (city_id) REFERENCES city(id)
);

CREATE TABLE inventory (
  id INT AUTO_INCREMENT PRIMARY KEY,
  dealer_id INT NOT NULL,
  model_id INT NOT NULL,
  qty INT NOT NULL,
  last_updated DATE NOT NULL,
  FOREIGN KEY (dealer_id) REFERENCES dealer(id),
  FOREIGN KEY (model_id) REFERENCES vehicle_model(id)
);

CREATE TABLE orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  order_no VARCHAR(50),
  dealer_id INT NOT NULL,
  model_id INT NOT NULL,
  planned_minutes INT NOT NULL,
  actual_minutes INT NOT NULL,
  cost DECIMAL(12,2) NOT NULL,
  revenue DECIMAL(12,2) NOT NULL,
  order_date DATE NOT NULL,
  delivered BOOLEAN NOT NULL,
  FOREIGN KEY (dealer_id) REFERENCES dealer(id),
  FOREIGN KEY (model_id) REFERENCES vehicle_model(id)
);

CREATE TABLE city_demand (
  id INT AUTO_INCREMENT PRIMARY KEY,
  city_id INT NOT NULL,
  demand_index DOUBLE NOT NULL,    -- 0-10 ölçeği
  population INT NOT NULL,         -- şehir nüfusu
  growth_pct INT NOT NULL,         -- ekonomik büyüme/otomotiv talep artış % (0-20)
  FOREIGN KEY (city_id) REFERENCES city(id)
);

-- -------------------------
-- 4) Ağırlıklar & Görünüm
-- -------------------------
CREATE TABLE weights (
  id INT PRIMARY KEY,
  w_demand DECIMAL(5,2),      -- 0-1
  w_land DECIMAL(5,2),
  w_labor DECIMAL(5,2),
  w_altyapi DECIMAL(5,2),
  w_supplier DECIMAL(5,2),
  w_logistics DECIMAL(5,2),
  w_energy DECIMAL(5,2),
  w_risk DECIMAL(5,2),        -- risk negatif etki
  w_incentive DECIMAL(5,2)    -- teşvik pozitif etki
);

INSERT INTO weights VALUES (1, 0.30, 0.15, 0.10, 0.15, 0.10, 0.08, 0.07, 0.03, 0.02);

-- Skor görünümü: 0-100 normalize (basit min-max yerine lineer ölçek)
-- Not: Land maliyeti ve tedarik mesafesi düşük oldukça daha iyi; bu nedenle 1/x etkisi
CREATE OR REPLACE VIEW view_site_score AS
SELECT
  cs.id,
  c.name AS city,
  cs.name AS site_name,
  cs.lat, cs.lon,
  cs.land_cost_per_m2,
  cs.labor_index,
  cs.altyapi_endeksi,
  cs.supplier_proximity_km,
  cs.logistics_index,
  cs.energy_capacity_mw,
  rp.earthquake_risk_pct,
  rp.flood_risk_pct,
  rp.supply_disruption_risk_pct,
  iz.zone_name,
  w.w_demand, w.w_land, w.w_labor, w.w_altyapi, w.w_supplier, w.w_logistics, w.w_energy, w.w_risk, w.w_incentive,

  -- Normalize edilmiş basitleştirilmiş bileşenler
  -- (örn. maliyet ters orantılı)
  (
    + (w.w_demand   * (SELECT IFNULL(MAX(cd.demand_index),1) FROM city_demand cd WHERE cd.city_id = cs.city_id) / 10.0) * 100
    + (w.w_land     * (1.0 / NULLIF(cs.land_cost_per_m2,0)) * 10000)
    + (w.w_labor    * (cs.labor_index/100.0) * 100)
    + (w.w_altyapi  * (cs.altyapi_endeksi/100.0) * 100)
    + (w.w_supplier * (1.0 / NULLIF(cs.supplier_proximity_km,1)) * 6000)
    + (w.w_logistics* (cs.logistics_index/100.0) * 100)
    + (w.w_energy   * LEAST(cs.energy_capacity_mw,300) / 3.0)
    -- risk negatif: deprem/sel/tedarik kesinti ortalaması
    - (w.w_risk     * ((rp.earthquake_risk_pct + rp.flood_risk_pct + rp.supply_disruption_risk_pct)/3.0))
    -- teşvik pozitif: vergi indirimi + yatırım katkısı
    + (w.w_incentive* (iz.tax_rebate_pct + iz.investment_grant_pct) / 2.0)
  ) AS score_raw
FROM candidate_site cs
JOIN city c               ON c.id = cs.city_id
JOIN risk_profile rp      ON rp.id = cs.risk_profile_id
JOIN incentive_zone iz    ON iz.id = cs.incentive_zone_id
JOIN weights w            ON w.id = 1;

-- ===========================
-- VERİLER
-- ===========================

-- 1) Şehirler
INSERT INTO city (name, lat, lon, region) VALUES
('İstanbul', 41.0082, 28.9784, 'Marmara'),
('Kocaeli', 40.8533, 29.8815, 'Marmara'),
('Bursa', 40.1950, 29.0600, 'Marmara'),
('Sakarya', 40.7731, 30.3948, 'Marmara'),
('Tekirdağ', 40.9780, 27.5110, 'Marmara'),
('Çanakkale', 40.1467, 26.4086, 'Marmara'),
('Ankara', 39.9208, 32.8541, 'İç Anadolu'),
('Konya', 37.8715, 32.4846, 'İç Anadolu'),
('Eskişehir', 39.7767, 30.5206, 'İç Anadolu'),
('Kayseri', 38.7225, 35.4875, 'İç Anadolu'),
('Sivas', 39.7477, 37.0179, 'İç Anadolu'),
('İzmir', 38.4237, 27.1428, 'Ege'),
('Manisa', 38.6140, 27.4296, 'Ege'),
('Denizli', 37.7765, 29.0864, 'Ege'),
('Aydın', 37.8444, 27.8458, 'Ege'),
('Mersin', 36.8121, 34.6415, 'Akdeniz'),
('Adana', 37.0000, 35.3213, 'Akdeniz'),
('Antalya', 36.8969, 30.7133, 'Akdeniz'),
('Gaziantep', 37.0662, 37.3833, 'Güneydoğu'),
('Diyarbakır', 37.9144, 40.2306, 'Güneydoğu'),
('Samsun', 41.2867, 36.33, 'Karadeniz'),
('Trabzon', 41.0053, 39.7275, 'Karadeniz'),
('Zonguldak', 41.4564, 31.7987, 'Karadeniz');

-- 2) Teşvik Bölgeleri
INSERT INTO incentive_zone (zone_name, tax_rebate_pct, sgk_support_months, investment_grant_pct) VALUES
('OSB Standard', 30, 36, 20),
('OSB + Liman Yakın', 40, 48, 25),
('Yüksek Teşvik Bölgesi', 50, 60, 35),
('Stratejik Yatırım Bölgesi', 60, 72, 40);

-- 3) Risk Profilleri
INSERT INTO risk_profile (city_id, earthquake_risk_pct, flood_risk_pct, supply_disruption_risk_pct) VALUES
((SELECT id FROM city WHERE name='İstanbul'), 60, 30, 20),
((SELECT id FROM city WHERE name='Kocaeli'), 55, 25, 18),
((SELECT id FROM city WHERE name='Bursa'), 50, 25, 16),
((SELECT id FROM city WHERE name='Sakarya'), 50, 20, 18),
((SELECT id FROM city WHERE name='Tekirdağ'), 45, 20, 22),
((SELECT id FROM city WHERE name='Çanakkale'), 35, 15, 20),
((SELECT id FROM city WHERE name='Ankara'), 20, 10, 12),
((SELECT id FROM city WHERE name='Konya'), 25, 8, 10),
((SELECT id FROM city WHERE name='Eskişehir'), 25, 12, 12),
((SELECT id FROM city WHERE name='Kayseri'), 30, 12, 14),
((SELECT id FROM city WHERE name='Sivas'), 25, 10, 16),
((SELECT id FROM city WHERE name='İzmir'), 45, 20, 18),
((SELECT id FROM city WHERE name='Manisa'), 40, 18, 18),
((SELECT id FROM city WHERE name='Denizli'), 35, 15, 16),
((SELECT id FROM city WHERE name='Aydın'), 40, 18, 16),
((SELECT id FROM city WHERE name='Mersin'), 35, 22, 18),
((SELECT id FROM city WHERE name='Adana'), 40, 22, 20),
((SELECT id FROM city WHERE name='Antalya'), 30, 25, 18),
((SELECT id FROM city WHERE name='Gaziantep'), 35, 15, 22),
((SELECT id FROM city WHERE name='Diyarbakır'), 35, 12, 25),
((SELECT id FROM city WHERE name='Samsun'), 28, 24, 16),
((SELECT id FROM city WHERE name='Trabzon'), 26, 30, 18),
((SELECT id FROM city WHERE name='Zonguldak'), 24, 26, 20);

-- 4) Tedarik Kümeleri
INSERT INTO supplier_cluster (name, city_id, avg_distance_km, specialization) VALUES
('Marmara Otomotiv Yan Sanayi', (SELECT id FROM city WHERE name='Kocaeli'), 20, 'Genel Yan Sanayi'),
('Bursa Metal & Şasi Kümesi', (SELECT id FROM city WHERE name='Bursa'), 25, 'Şasi & Metal'),
('İzmir Batarya & Elektrik', (SELECT id FROM city WHERE name='İzmir'), 30, 'Batarya'),
('Ankara Mekanik Parça', (SELECT id FROM city WHERE name='Ankara'), 35, 'Mekanik'),
('Konya Döküm & İşleme', (SELECT id FROM city WHERE name='Konya'), 40, 'Döküm'),
('Gaziantep Plastik & Kalıp', (SELECT id FROM city WHERE name='Gaziantep'), 45, 'Plastik'),
('Mersin Lojistik Hub', (SELECT id FROM city WHERE name='Mersin'), 30, 'Lojistik Dağıtım'),
('Samsun Karadeniz Tedarik', (SELECT id FROM city WHERE name='Samsun'), 35, 'Karma');

-- 5) Aday Sahalar (20+ yer)
INSERT INTO candidate_site
(city_id, name, lat, lon, land_cost_per_m2, labor_index, altyapi_endeksi, supplier_proximity_km, logistics_index, energy_capacity_mw, risk_profile_id, incentive_zone_id, zoning_ready, notes)
VALUES
((SELECT id FROM city WHERE name='Kocaeli'),'Gebze OSB - Doğu Kapı',40.814,29.44,  2500, 82, 95, 10,  92, 220, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Kocaeli')), 2, TRUE,'Liman ve otoyola çok yakın'),
((SELECT id FROM city WHERE name='Bursa'),'Bursa Hasanağa OSB',40.209,28.94,   1920, 84, 92, 25,  85, 180, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Bursa')),   1, TRUE,'Yan sanayi güçlü'),
((SELECT id FROM city WHERE name='İzmir'),'Aliağa Endüstri Bölgesi',38.74,26.97,  1850, 85, 88, 30,  88, 200, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='İzmir')),   2, TRUE,'Enerji ve petrokimya yakın'),
((SELECT id FROM city WHERE name='Manisa'),'Manisa OSB 4. Kısım',38.66,27.37,   1900, 80, 86, 35,  84, 160, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Manisa')),  1, TRUE,'İzmir limanına 45dk'),
((SELECT id FROM city WHERE name='Ankara'),'Ankara Başkent OSB',40.08,32.59,   4300, 83, 90, 40,  80, 170, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Ankara')),  1, TRUE,'Memur kenti, işgücü istikrarlı'),
((SELECT id FROM city WHERE name='Konya'),'Konya 3. OSB (Lojistik)',37.96,32.53, 2300, 78, 84, 60,  76, 140, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Konya')),   3, TRUE,'Geniş arsa ve lojistik köprüsü'),
((SELECT id FROM city WHERE name='Eskişehir'),'Eskişehir OSB Batı',39.80,30.44,  3100, 80, 87, 55,  78, 150, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Eskişehir')),1, TRUE,'Raylı sistem tedarikleri güçlü'),
((SELECT id FROM city WHERE name='Kayseri'),'Kayseri OSB Kuzey',38.78,35.36,    2900, 79, 82, 70,  74, 140, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Kayseri')),  3, TRUE,'İç Anadolu dağıtım merkezi'),
((SELECT id FROM city WHERE name='Sivas'),'Sivas Demirağ OSB',39.83,37.00,      2600, 72, 78, 85,  68, 120, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Sivas')),    3, TRUE,'Yeni OSB, arsa geniş'),
((SELECT id FROM city WHERE name='Mersin'),'Mersin Tarsus OSB',36.94,34.90,     3530, 77, 83, 35,  86, 170, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Mersin')),  2, TRUE,'Liman ve Akdeniz koridoru'),
((SELECT id FROM city WHERE name='Adana'),'Adana Hacı Sabancı OSB',37.06,35.25, 3060, 76, 80, 45,  80, 160, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Adana')),  2, TRUE,'Geleneksel sanayi güçlü'),
((SELECT id FROM city WHERE name='Gaziantep'),'Başpınar OSB',37.09,37.37,       2800, 78, 79, 55,  75, 150, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Gaziantep')),2, TRUE,'Plastik/kalıp kümesi yakın'),
((SELECT id FROM city WHERE name='Diyarbakır'),'Diyarbakır OSB',37.95,40.13,    2100, 70, 76, 95,  65, 110, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Diyarbakır')),3, TRUE,'Teşvik yüksek'),
((SELECT id FROM city WHERE name='Samsun'),'Samsun Merkez OSB',41.24,36.35,     2500, 74, 80, 65,  70, 120, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Samsun')),   3, TRUE,'Karadeniz limanı erişimi'),
((SELECT id FROM city WHERE name='Trabzon'),'Trabzon Arsin OSB',40.98,39.78,    4200, 72, 78, 75,  68, 110, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Trabzon')), 3, TRUE,'Karadeniz doğu kapısı'),
((SELECT id FROM city WHERE name='Zonguldak'),'Filyos Endüstri Bölgesi',41.62,32.07,3600, 76, 85, 40,  82, 160, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Zonguldak')),2, TRUE,'Derin deniz limanı'),
((SELECT id FROM city WHERE name='Tekirdağ'),'Çorlu Velimeşe',41.19,27.80,      5200, 82, 89, 35,  90, 200, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Tekirdağ')),2, TRUE,'İstanbul hinterlandı'),
((SELECT id FROM city WHERE name='Sakarya'),'Sakarya Hendek',40.80,30.60,       4700, 81, 88, 28,  88, 190, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Sakarya')),  2, TRUE,'Otoyol ve tedarik yakın'),
((SELECT id FROM city WHERE name='Çanakkale'),'Biga OSB',40.23,27.24,           3200, 77, 81, 60,  74, 140, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Çanakkale')),1, TRUE,'Rüzgar enerjisi bölgeleri'),
((SELECT id FROM city WHERE name='Antalya'),'AOSB Doğu',36.95,30.83,            5050, 75, 80, 50,  70, 130, (SELECT id FROM risk_profile WHERE city_id=(SELECT id FROM city WHERE name='Antalya')),  1, TRUE,'Nitelikli göç alanı');

-- 6) Şehir Talebi (0-10)
INSERT INTO city_demand (city_id, demand_index, population, growth_pct) VALUES
((SELECT id FROM city WHERE name='İstanbul'), 9.5, 15800000, 4),
((SELECT id FROM city WHERE name='Kocaeli'), 7.8, 2050000, 5),
((SELECT id FROM city WHERE name='Bursa'), 7.0, 3100000, 4),
((SELECT id FROM city WHERE name='Sakarya'), 6.2, 1080000, 4),
((SELECT id FROM city WHERE name='Tekirdağ'), 6.8, 1100000, 4),
((SELECT id FROM city WHERE name='Çanakkale'), 5.2, 560000, 3),
((SELECT id FROM city WHERE name='Ankara'), 7.5, 5600000, 3),
((SELECT id FROM city WHERE name='Konya'), 6.4, 2300000, 3),
((SELECT id FROM city WHERE name='Eskişehir'), 6.0, 900000, 3),
((SELECT id FROM city WHERE name='Kayseri'), 6.1, 1450000, 3),
((SELECT id FROM city WHERE name='Sivas'), 4.8, 650000, 2),
((SELECT id FROM city WHERE name='İzmir'), 7.6, 4400000, 4),
((SELECT id FROM city WHERE name='Manisa'), 5.9, 1450000, 3),
((SELECT id FROM city WHERE name='Denizli'), 5.6, 1050000, 3),
((SELECT id FROM city WHERE name='Aydın'), 5.4, 1100000, 3),
((SELECT id FROM city WHERE name='Mersin'), 6.7, 1900000, 4),
((SELECT id FROM city WHERE name='Adana'), 6.5, 2260000, 3),
((SELECT id FROM city WHERE name='Antalya'), 6.9, 2600000, 4),
((SELECT id FROM city WHERE name='Gaziantep'), 5.8, 2100000, 3),
((SELECT id FROM city WHERE name='Diyarbakır'), 5.0, 1800000, 3),
((SELECT id FROM city WHERE name='Samsun'), 5.2, 1350000, 2),
((SELECT id FROM city WHERE name='Trabzon'), 4.9, 820000, 2),
((SELECT id FROM city WHERE name='Zonguldak'), 4.7, 600000, 2);

-- 7) Araç Modelleri
INSERT INTO vehicle_model (model_code, model_name, type) VALUES
('BYD-E6','E6 Electric','EV'),
('BYD-T3','T3 Van','Commercial'),
('BYD-Atto3','Atto 3','EV'),
('BYD-Tang','Tang','SUV'),
('BYD-Yuan','Yuan PLUS','SUV'),
('BYD-Dolphin','Dolphin','EV'),
('BYD-Seal','Seal','EV'),
('BYD-Han','Han','EV'),
('BYD-Song','Song','SUV'),
('BYD-Frigate07','Frigate 07','Hybrid'),
('BYD-DenzaN7','Denza N7','EV'),
('BYD-PlusDMi','Song Plus DM-i','Hybrid'),
('BYD-QinPlus','Qin Plus','Hybrid'),
('BYD-Seagull','Seagull','EV'),
('BYD-U8','YangWang U8','SUV');

-- 8) Bayiler (şehir başına 2-3)
INSERT INTO dealer (name, city_id, lat, lon, region) VALUES
('BYD Dealer - İstanbul Avrupa', (SELECT id FROM city WHERE name='İstanbul'), 41.05, 28.85, 'Marmara'),
('BYD Dealer - İstanbul Anadolu', (SELECT id FROM city WHERE name='İstanbul'), 40.98, 29.10, 'Marmara'),
('BYD Dealer - Kocaeli İzmit', (SELECT id FROM city WHERE name='Kocaeli'), 40.77, 29.94, 'Marmara'),
('BYD Dealer - Bursa Nilüfer', (SELECT id FROM city WHERE name='Bursa'), 40.23, 28.95, 'Marmara'),
('BYD Dealer - Bursa Osmangazi', (SELECT id FROM city WHERE name='Bursa'), 40.20, 29.07, 'Marmara'),
('BYD Dealer - Ankara Çankaya', (SELECT id FROM city WHERE name='Ankara'), 39.90, 32.85, 'İç Anadolu'),
('BYD Dealer - Ankara Etimesgut', (SELECT id FROM city WHERE name='Ankara'), 39.95, 32.65, 'İç Anadolu'),
('BYD Dealer - İzmir Karşıyaka', (SELECT id FROM city WHERE name='İzmir'), 38.47, 27.12, 'Ege'),
('BYD Dealer - İzmir Gaziemir', (SELECT id FROM city WHERE name='İzmir'), 38.31, 27.15, 'Ege'),
('BYD Dealer - Konya Selçuklu', (SELECT id FROM city WHERE name='Konya'), 37.97, 32.49, 'İç Anadolu'),
('BYD Dealer - Eskişehir Tepebaşı', (SELECT id FROM city WHERE name='Eskişehir'), 39.78, 30.50, 'İç Anadolu'),
('BYD Dealer - Kayseri Melikgazi', (SELECT id FROM city WHERE name='Kayseri'), 38.73, 35.47, 'İç Anadolu'),
('BYD Dealer - Mersin Mezitli', (SELECT id FROM city WHERE name='Mersin'), 36.78, 34.55, 'Akdeniz'),
('BYD Dealer - Adana Seyhan', (SELECT id FROM city WHERE name='Adana'), 36.99, 35.32, 'Akdeniz'),
('BYD Dealer - Antalya Kepez', (SELECT id FROM city WHERE name='Antalya'), 36.92, 30.72, 'Akdeniz'),
('BYD Dealer - Gaziantep Şehitkamil', (SELECT id FROM city WHERE name='Gaziantep'), 37.08, 37.35, 'Güneydoğu'),
('BYD Dealer - Samsun İlkadım', (SELECT id FROM city WHERE name='Samsun'), 41.29, 36.33, 'Karadeniz'),
('BYD Dealer - Trabzon Ortahisar', (SELECT id FROM city WHERE name='Trabzon'), 41.00, 39.73, 'Karadeniz');

-- 9) Stok (örnek)
INSERT INTO inventory (dealer_id, model_id, qty, last_updated)
SELECT d.id, m.id, FLOOR(1 + RAND()*8), DATE('2025-10-10')
FROM dealer d CROSS JOIN vehicle_model m;

-- 10) Siparişler (yaklaşık 400 satır)
INSERT INTO orders (order_no, dealer_id, model_id, planned_minutes, actual_minutes, cost, revenue, order_date, delivered)
SELECT
  CONCAT('ORD-', LPAD(1000 + (a.n - 1) * 10 + b.n, 5, '0')),

  (SELECT id FROM dealer ORDER BY RAND() LIMIT 1),
  (SELECT id FROM vehicle_model ORDER BY RAND() LIMIT 1),
  FLOOR(60 + RAND()*420),
  FLOOR(60 + RAND()*480),
  FLOOR(12000 + RAND()*50000),
  FLOOR(15000 + RAND()*70000),
  DATE_ADD('2025-06-01', INTERVAL FLOOR(RAND()*140) DAY),
  IF(RAND()>0.12,1,0)
FROM (
  SELECT 1 AS n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10
  UNION SELECT 11 UNION SELECT 12 UNION SELECT 13 UNION SELECT 14 UNION SELECT 15 UNION SELECT 16 UNION SELECT 17 UNION SELECT 18 UNION SELECT 19 UNION SELECT 20
  UNION SELECT 21 UNION SELECT 22 UNION SELECT 23 UNION SELECT 24 UNION SELECT 25 UNION SELECT 26 UNION SELECT 27 UNION SELECT 28 UNION SELECT 29 UNION SELECT 30
  UNION SELECT 31 UNION SELECT 32 UNION SELECT 33 UNION SELECT 34 UNION SELECT 35 UNION SELECT 36 UNION SELECT 37 UNION SELECT 38 UNION SELECT 39 UNION SELECT 40
) a,
(
  SELECT 1 AS n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
  UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10
) b;

-- 11) KPI Cache (boş başlangıç)
CREATE TABLE kpi_cache (
  id INT AUTO_INCREMENT PRIMARY KEY,
  city_id INT NOT NULL,
  on_time_rate DOUBLE,
  avg_delay_minutes DOUBLE,
  total_orders INT,
  last_run DATETIME,
  FOREIGN KEY (city_id) REFERENCES city(id)
);

INSERT INTO kpi_cache (city_id, on_time_rate, avg_delay_minutes, total_orders, last_run)
SELECT id, 0, 0, 0, NULL FROM city;