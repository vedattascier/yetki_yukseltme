# 🛡️ Linux Yetki Yükseltme Denetim Aracı

Linux sistemlerde kapsamlı **yerel güvenlik denetimi** ve **yetki yükseltme (privilege escalation)** analizleri yapmak için geliştirilmiş gelişmiş bir otomasyon scriptidir.

Bu araç; sistem yapılandırmaları, dosya izinleri, servis güvenliği ve bilinen zafiyetleri analiz ederek riskleri tespit eder ve çözüm önerileri sunar.

---

## 📌 Genel Özellikler

- Tam Türkçe arayüz
- Risk puanlama sistemi (**0–100**)
- CVE (bilinen zafiyet) taraması
- Makine öğrenmesi tabanlı anomali analizi
- Otomatik güvenlik önerileri
- Çoklu çıktı formatı desteği:
  - TXT
  - JSON
  - Markdown
  - HTML
  - SQLite veritabanı

---

## 🚀 Yeni Eklenen Özellikler

- 🤖 ML tabanlı risk tahmini
- 🔍 CVE açıklık taraması
- ⚠️ Anomali tespiti:
  - LD_PRELOAD manipülasyonu
  - Zombi işlemler
  - Yazılabilir sistem binary’leri
- 🛠️ Otomatik düzeltme scripti oluşturma
- 📊 Tarama sonrası raporun otomatik gösterimi

---

## 📂 Oluşturulan Dosyalar

Script çalıştırıldığında aynı dizinde aşağıdaki dosyalar oluşturulur:

| Dosya | Açıklama |
|------|--------|
| `sonuclar.txt` / `sonuclar_N.txt` | Terminal çıktısı |
| `yetkiyukseltme_report_TIMESTAMP.txt` | Detaylı analiz raporu |
| `security_scans.db` | SQLite veritabanı (opsiyonel) |

---

## ⚙️ Kurulum & Kullanım

Script’e çalıştırma izni verin:

```bash
chmod +x linux-yetki-yukseltme.sh
```

Çalıştırın:

```bash
./linux-yetki-yukseltme.sh
```

---

## 🧩 Komut Satırı Seçenekleri

| Parametre | Açıklama |
|----------|--------|
| `-h, --help` | Yardım menüsü |
| `-v` | Ayrıntılı çıktı |
| `-q` | Sessiz mod (sadece özet) |
| `-f` | Hızlı tarama |
| `-t` | Kapsamlı tarama |
| `-j` | JSON çıktısı |
| `-m` | Markdown çıktısı |
| `-p` | Sudo parolası ister |
| `-k <anahtar>` | Anahtar kelime arama |
| `-e <dizin>` | Dışa aktarım dizini |
| `-r <dosya>` | Özel rapor adı |
| `--html-report` | HTML rapor oluşturur |
| `--database` | SQLite kaydı |
| `--fix-script` | Otomatik düzeltme scripti üretir |
| `--no-colors` | Renkleri kapatır |
| `--version` | Versiyon bilgisi |

---

## 💡 Örnek Kullanımlar

### Standart tarama
```bash
./linux-yetki-yukseltme.sh
```

### Hızlı tarama (özet çıktı)
```bash
./linux-yetki-yukseltme.sh -f -q
```

### Detaylı + JSON çıktısı
```bash
./linux-yetki-yukseltme.sh -t -j
```

### HTML rapor
```bash
./linux-yetki-yukseltme.sh --html-report
```

### Veritabanına kayıt
```bash
./linux-yetki-yukseltme.sh --database
```

---

## 🔍 Tarama Kapsamı

### 🖥️ Sistem Bilgileri
- Kernel versiyonu
- Dağıtım bilgisi
- CPU / RAM / Disk kullanımı
- Ağ yapılandırması

### 👤 Kullanıcı & Yetki Denetimi
- Kullanıcı hesapları
- Sudo yetkileri
- Parola politikaları
- `/etc/shadow` güvenliği

### 📁 Dosya Sistemi Güvenliği
- SUID / SGID dosyalar
- Dünya yazılabilir dosyalar
- Sistem binary güvenliği
- Kütüphane enjeksiyon riskleri

### 🌐 Ağ & Servis Analizi
- SSH yapılandırması
- Firewall (iptables / UFW)
- Açık portlar
- Cron & systemd timer
- Servis güvenliği

### 🔐 Gelişmiş Güvenlik Analizleri
- CVE kontrolü
- ML tabanlı anomali tespiti
- Tedarik zinciri riskleri
- Zero-day heuristikleri
- Auditd durumu
- TLS / şifreleme kontrolleri

---

## 📊 Risk Değerlendirme Seviyeleri

| Seviye | Açıklama |
|------|--------|
| 🔴 KRİTİK | Acil müdahale gerekli |
| 🟠 ÇOK YÜKSEK | Hızlı aksiyon alınmalı |
| 🟡 YÜKSEK | Kısa sürede düzeltilmeli |
| 🔵 ORTA | Düzenli bakım gerekli |
| ⚪ DÜŞÜK | İzlenebilir |

---

## 📢 Raporlama

Tarama tamamlandıktan sonra:

- En güncel rapor **otomatik olarak terminale yazdırılır**
- Aynı zamanda dosya olarak kaydedilir
- Farklı formatlarda dışa aktarım mümkündür

---

## ⚠️ Yasal Uyarı

Bu araç yalnızca:

- Kendi sistemlerinizde  
- Açık izin verilen test ortamlarında  

kullanılmalıdır.

Yetkisiz sistemlerde yapılan testler **yasal sorumluluk doğurur**.

---

## 🧠 Not

Bu araç bir **otomasyon destekli analiz** sağlar.  
Tespit edilen bulgular mutlaka **manuel doğrulama** ile teyit edilmelidir.
