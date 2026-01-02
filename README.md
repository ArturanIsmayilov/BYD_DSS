# BYD KDS — Taktiksel & Stratejik Fabrika Karar Destek Sistemi

Bu proje, Türkiye genelinde yeni yatırım planlayan BYD için geliştirilmiş, veri odaklı bir **Karar Destek Sistemi (KDS)** simülasyonudur. Sistem, hem operasyonel verimliliği takip eder hem de yeni fabrika lokasyonları için analitik hesaplamalar yapar.

## 🚀 Öne Çıkan Özellikler

* **Akıllı Skorlama Motoru:** Aday sahaları; arsa maliyeti, işgücü endeksi, altyapı yeterliliği ve tedarikçi yakınlığı gibi kriterlere göre ağırlıklı puanlar.
* **"What-If" Simülasyonu:** Kullanıcılar, karar kriterlerinin ağırlıklarını anlık olarak değiştirerek farklı senaryoları test edebilir.
* **İnteraktif Harita Entegrasyonu:** Leaflet.js kullanılarak bayiler, aday sahalar ve potansiyel şehirler harita üzerinde görselleştirilmiştir.
* **KPI Takibi:** Teslimat performansları, gecikme süreleri ve stok durumları şehir/model bazlı olarak anlık izlenebilir.
* **Dinamik Raporlama:** Analiz sonuçları PDF veya CSV formatında dışa aktarılabilir.

![Status](https://img.shields.io/badge/Status-Completed-success?style=flat-square) ![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

## 🛠️ Teknik Altyapı

* **Backend:** Node.js & Express.js.
* **Veritabanı:** MySQL (İlişkisel şema ve performans odaklı görünümler).
* **Frontend:** HTML5, CSS3, JavaScript & Chart.js.
* **Harita:** Leaflet API.

## 📦 Kurulum ve Çalıştırma

1. **Veritabanı Yapılandırması:** `schema.sql` dosyasını MySQL sunucunuzda çalıştırarak gerekli tabloları ve örnek verileri oluşturun.

2. **Bağımlılıkların Yüklenmesi:** Proje ana dizininde aşağıdaki komutu çalıştırın:
   ```bash
   npm install

```

3. **Çevresel Değişkenlerin Ayarlanması:** Ana dizinde bir `.env` dosyası oluşturun ve veritabanı bağlantı bilgilerinizi aşağıdaki formatta girin:
```text
DB_HOST=localhost
DB_USER=root
DB_PASS=Sifreniz
DB_NAME=byd_kds_demo
DB_PORT=port

```


4. **Sistemi Başlatma:** Sunucuyu ayağa kaldırmak için şu komutu kullanın:
```bash
node server.js

```


5. **Erişim:** Tarayıcınızdan `http://localhost:3000` adresine giderek sistemi kullanmaya başlayın.
