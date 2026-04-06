# Yerel Linux Bilgi Toplama & Yetki Yükseltme Betiği - v4.0 ENTERPRISE ML Enhanced

## 📋 Açıklama

Bu script, Linux sistemlerde yerel bilgi toplama ve potansiyel yetki yükseltme (privilege escalation) fırsatlarını taramak için tasarlanmış kapsamlı ENTERPRISE-grade bir araçtır. Sistem bilgilerini, kullanıcı hesaplarını, yapılandırma dosyalarını ve güvenlik açıklarını makine öğrenmesi ve CVE analizi ile denetler.

**Tam Türkçe versiyon - 24 Uzmanlaşmış Tarama Modülü** | **ML Tabanlı Risk Tahmini** | **Enterprise Ready**

## ✨ Özellikler

### 🤖 Makine Öğrenmesi & İntellijen Analiz (v4.0 Yenisi!)
- **ML Tabanlı Risk Tahmini**: Sistem davranışından anormal risk faktörleri yapay öğrenme ile tespit
- **CVE Açıklık Taraması**: OpenSSL, Kernel, Bash, PHP vb. kritik bileşenleri CVE veritabanına göre tara
- **Davranış Anomali Tespiti**: LD_PRELOAD, zombi işlemler, yazılabilir sistem dosyaları gibi şüpheli aktiviteleri algıla
- **Gelişmiş Şifreleme Analizi**: TLS/SSL, SSH cipher, disk şifrelemesi güvenliğini derinlemesine doğrula
- **Tedarik Zinciri Risk Değerlendirmesi**: Tainted kernel, GPG imzaları, güvenli repository yapılandırmasını kontrol et
- **Sıfır-Gün Heuristic'leri**: Kernel panic'leri, bellek bozulması, dinamik linker injection risklerini tespit et
- **Akıllı Düzeltme Motor**: SSH hardening, firewall, fail2ban, SELinux gibi otomatik güvenlik önerileri
- **Baseline Sistem Karşılaştırması**: Sistem başlangıç belgesi oluştur ve güvenlik değişimlerini izle

### 📊 Temel Özellikler
- **Sistem Bilgileri**: Çekirdek, dağıtım, CPU, bellek ve disk bilgileri
- **Kullanıcı/Grup Analizi**: Hesaplar, gruplar, sudo yetkileri ve parola politikaları
- **Dosya Sistemi Taraması**: Yazılabilir dosyalar, SUID/SGID dosyaları, gizli dosyalar
- **Ağ Bilgileri**: Ağ arayüzleri, yönlendirme tabloları, açık portlar
- **Servis Analizi**: Çalışan servisler, cron job'ları, systemd zamanlayıcıları
- **Güvenlik Kontrolleri**: Parola politikaları, sudo yapılandırması, yetki açıkları
- **Çıktı Formatları**: Metin, Markdown, JSON, HTML
- **Risk Profilleri**: Strict, Standard, Relaxed
- **Otomatik Raporlama**: Detaylı rapor dosyaları oluşturma
- **Risk Puanlama**: 0-100 arası risk skoru ve yüzde hesaplama
- **Otomatik Düzeltme**: Risk analizine göre otomatik düzeltme script'i oluşturma
- **HTML Rapor**: Profesyonel HTML rapor çıktısı
- **SQLite Veritabanı**: Geçmiş taramaları saklama ve karşılaştırma
- **Trend Analizi**: Güvenlik durumunun zaman içindeki değişimi
- **Çıktı Dosyaları Aynı Dizin**: Rapor ve sonuç dosyaları script dizininde, farklı isimlerle kaydedilir
- **Privilege Escalation Denemeleri**: Tehlikeli yetki yükseltme tekniklerini test etme
- **Akıllı Root Rehberi**: Başarısız denemeler sonrası adım adım root olma rehberi

## � ULTRA DERİN TARAMA ÖZELLİKLERİ (v3.0+)

- **PAM Güvenlik Analizi**: Pluggable Authentication Modules yapılandırması denetimi
- **SUDO Derin Denetimi**: NOPASSWD, ALL=(ALL), shell erişim izinleri analizi
- **SSH Güvenlik Denetimi**: Root girişi, anahtar doğrulaması, ağ geçidi kontrolü
- **Sysctl Parametreleri**: Kernel güvenlik ayarlarının denetimi (ASLR, forwarding vb.)
- **Dosya Sistemi Bağlama**: Mount seçenekleri (noexec, nodev, nosuid) analizi
- **Kütüphane Enjeksiyonu**: LD_PRELOAD, LD_LIBRARY_PATH vektörleri taraması
- **Daemon Yetkileri**: Root daemon'ları ve gereksiz SUID programları tespit
- **Core Dump Koruma**: Memory dump, ASLR ve core dump ayarları denetimi
- **MAC Sistemleri**: SELinux ve AppArmor durumu kontrolleri
- **Firewall Denetimi**: UFW, iptables kuralları ve ağ güvenliği analizi
## 🚀 İLERİ SEVIYE TARAMA ÖZELLİKLERİ (v3.0+ Extended)

- **Kernel Modülü Analizi**: Yüklü modüller ve rootkit tespiti
- **Zamanlanmış Görevler**: AT, systemd timers ve cron derinlemesine analiz
- **Linux Capabilities**: getcap ile privilege sınırlarının analizi
- **Binary Hardening**: PIE, RELRO, Stack Canary, Fortify kontrolleri
- **Audit Sistemi Hazırlığı**: auditd yapılandırması ve kural denetimi
- **Gelişmiş Parola Politikası**: pwquality, faillock, geçmiş, yaş kontrolleri
- **UMASK Güvenliği**: Varsayılan dosya izinleri ve grup yazma kontrolleri

## 🔬 ENTERPRISE ML ANALİZ ÖZELLİKLERİ (v4.0 Yenisi!)

- **ML Risk Tahmini**: Sistem davranış anormallikleri yapay öğrenme ile rating eder
- **CVE Vulnerability Taraması**: Kernel, OpenSSL, Bash, PHP versiyonlarını CVE'ye karşı kontrol et
- **Davranış Anomali Algılama**: Anormal sistem aktivitelerini (LD_PRELOAD, zombi, writable system bins) tespit et
- **Şifreleme Derinlemesine Analiz**: TLS versiyonları, SSH cipher'ları, disk şifreleme durumunu değerlendir
- **Tedarik Zinciri Riski**: Tainted kernel, GPG signing, package authenticity kontrol et
- **Sıfır-Gün Heuristic'leri**: Kernel panic'ler, bellek bozulması, suspicious syscall'ları yakala
- **Akıllı Remediasyon**: SSH hardening, UFW, fail2ban, SELinux gibi otomatik düzeltme adımları öner
- **System Baseline Comparison**: Sistem başlangıç snapshot'ı oluştur ve değişimleri izle
## �🚀 Kurulum

### Gereksinimler

- Bash shell
- Standart Linux araçları (grep, find, awk, vb.)
- Root yetkileri (bazı kontroller için önerilir)

### İndirme

```bash
git clone https://github.com/vedattascier/linux-yetki-yukseltme.git
cd linux-yetki-yukseltme
chmod +x linux-yetki-yukseltme.sh
```

## 📖 Kullanım

### Temel Kullanım

```bash
./linux-yetki-yukseltme.sh
```

### Seçenekler

| Seçenek | Açıklama |
|---------|----------|
| `-h, --help` | Bu yardımı göster |
| `-v, --verbose` | Ayrıntılı çıktı (varsayılan) |
| `-q, --quiet` | Sadece özet ve öneriler göster |
| `-j, --json` | JSON formatında çıktı |
| `-m, --markdown` | Markdown formatında çıktı |
| `-f, --fast` | Hızlı tarama (find timeout 5s) |
| `-t, --thorough` | Ayrıntılı tarama (timeout 60s) |
| `-k, --keyword ANAHTAR` | Anahtar kelimesi ara |
| `-e, --export DİZİN` | Dışa aktar |
| `-p, --password` | Sudo parolası sor |
| `-r, --report DOSYA` | Raporu kaydet |
| `--risk [s\|std\|r]` | Risk profili |
| `--max-results N` | Max bulgu (varsayılan: 200) |
| `--find-timeout N` | Find timeout (varsayılan: 20) |
| `--no-colors` | Renkleri kapat |
| `--fix-script` | Otomatik düzeltme script'i oluştur |
| `--html-report` | HTML rapor oluştur |
| `--database` | SQLite veritabanı kullan |
| `--version` | Versiyon göster |

### Örnekler

```bash
# Normal tarama
./linux-yetki-yukseltme.sh

# Hızlı tarama + sadece özet
./linux-yetki-yukseltme.sh -f -q

# Ayrıntılı tarama + JSON çıktısı
./linux-yetki-yukseltme.sh -t -j | tee rapor.json

# Anahtar kelime arama
./linux-yetki-yukseltme.sh -k "password"

# Dışa aktarma
./linux-yetki-yukseltme.sh -e ./export-dizini

# Özel rapor dosyası
./linux-yetki-yukseltme.sh -r ./benim-raporum.txt

# HTML rapor ile tam tarama
./linux-yetki-yukseltme.sh --html-report

# Tehlikeli privilege escalation denemeleri (DİKKAT!)
./linux-yetki-yukseltme.sh --privilege-escalation

# Otomatik düzeltme script'i oluştur
./linux-yetki-yukseltme.sh --fix-script

# Veritabanı ile geçmiş karşılaştırma
./linux-yetki-yukseltme.sh --database

### Örnek Çıktı (Risk Analizi)

```
📊 RİSK ANALİZİ:
Genel Risk Skoru: 75/100 (%75)
Risk Seviyesi: ⚠️ ÇOK YÜKSEK
Öncelik: HIZLICA DÜZELTİLMELİ

🎯 RİSK SEVİYESİNE GÖRE ÖNERİLER:
⚠️  ÇOK YÜKSEK RİSK ÖNCELİKLERİ (24 Saat İçinde):
   • Açık portları ve servisleri gözden geçirin
   • Sudo yapılandırmasını güçlendirin
   • Parola politikalarını zorunlu hale getirin
   • Güvenlik duvarı kurallarını güncelleyin
   • Cron job'larını ve zamanlanmış görevleri kontrol edin

🔧 TEKNİK DÜZELTME ADIMLARI:
YÜKSEK RİSK DÜZELTMELERİ:
   # Açık portları kontrol edin:
   netstat -tulnp | grep LISTEN
   # Sudo yapılandırmasını kontrol edin:
   visudo -c
   # Güvenlik duvarını etkinleştirin:
   ufw enable
```

## 🔍 Taranan Alanlar

### Sistem Bilgileri
- Çekirdek ve dağıtım sürümü
- CPU, bellek ve disk bilgileri
- Sistem çalışma süresi
- Ana makine adı

### Kullanıcı ve Grup Analizi
- Geçerli kullanıcı bilgileri
- Tüm kullanıcı hesapları (/etc/passwd)
- Grup üyelikleri
- Sudo yapılandırması
- Parola politikaları
- Shadow dosya erişimi

### Dosya Sistemi
- Yazılabilir dosyalar ve dizinler
- SUID/SGID dosyaları
- Dünya tarafından okunabilir/yazılabilir dosyalar
- Gizli dosyalar
- SSH anahtarları
- Yapılandırma dosyaları

### Ağ Bilgileri
- Ağ arayüzleri
- Yönlendirme tabloları
- DNS yapılandırması
- Açık portlar
- Ağ servisleri

### Servisler ve Zamanlayıcılar
- Çalışan prosesler
- Cron job'ları
- Systemd servisleri
- Zamanlanmış görevler

### Güvenlik Kontrolleri
- GTFOBins potansiyeli olan ikililer
- Yazılabilir PATH girişleri
- Güvensiz dosya izinleri
- Yetki yükseltme fırsatları

## 📊 Risk Analizi Sistemi

Script gelişmiş bir risk puanlama sistemi kullanır:

### Risk Seviyeleri
- **KRİTİK (81-100)**: 🚨 Acil müdahale gerekli - Sistem ciddi risk altında
- **ÇOK YÜKSEK (61-80)**: ⚠️ Hızlıca düzeltilmeli - Önemli güvenlik açıkları
- **YÜKSEK (41-60)**: ⚠️ Kısa sürede düzeltilmeli - Güvenlik iyileştirmesi gerekli
- **ORTA (21-40)**: ⚡ Düzeltilmeli - Düzenli bakım gerekli
- **DÜŞÜK (0-20)**: ✅ Gözden geçirilmeli - Genel olarak güvenli

### Risk Puanlama
- **KRİTİK Bulgular**: +25-30 puan (Container kaçış, root yetki açıkları)
- **YÜKSEK Risk**: +15-20 puan (SUID/SGID, açık portlar)
- **ORTA Risk**: +5-10 puan (Konfigürasyon hataları)
- **DÜŞÜK Risk**: +1-5 puan (İyileştirme önerileri)

### Akıllı Öneriler
Risk seviyesine göre kişiselleştirilmiş öneriler:
- **KRİTİK**: Hemen müdahale komutları ve acil adımlar
- **YÜKSEK**: Teknik düzeltme komutları
- **ORTA/DÜŞÜK**: Genel güvenlik önerileri ve kaynaklar

## ⚠️ Uyarılar

- **Güvenlik**: Bu araç güvenlik testleri için tasarlanmıştır. Üretim sistemlerinde dikkatli kullanın.
- **Performans**: Ayrıntılı tarama modu sistem performansını etkileyebilir.
- **Yetkiler**: Bazı kontroller için root yetkileri gerekebilir.
- **Yasal**: Sadece kendi sistemlerinizde veya izin verilen sistemlerde kullanın.

## 📊 Çıktı Formatları

### Metin (Varsayılan)
Standart terminal çıktısı, renk kodları ile.

### Markdown
GitHub uyumlu markdown formatında rapor.

### JSON
Makine tarafından okunabilir JSON formatı.

## 🔧 Yapılandırma

### Risk Profilleri

- **Strict**: Sadece yüksek güvenilirlikli kontroller
- **Standard**: Dengeli yaklaşım (varsayılan)
- **Relaxed**: Daha fazla potansiyel bulgu

### Zaman Aşımları

- **Find Timeout**: Dosya arama işlemleri için zaman aşımı (varsayılan: 20s)
- **Max Results**: Maksimum bulgu sayısı (varsayılan: 200)

## 📝 Raporlama

Script otomatik olarak rapor dosyaları oluşturur:

- `sonuclar.txt`: Ana rapor dosyası
- `yetkiyukseltme_report_TIMESTAMP.txt`: Detaylı rapor (script dizininde oluşturulur)
- JSON/Markdown formatlarında dışa aktarma

## 🤝 Katkıda Bulunma

1. Fork edin
2. Feature branch oluşturun (`git checkout -b feature/YeniOzellik`)
3. Commit edin (`git commit -am 'Yeni özellik eklendi'`)
4. Push edin (`git push origin feature/YeniOzellik`)
5. Pull Request oluşturun

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır.

## 👨‍💻 Yazar

**Vedat Taşçıer**
- Website: [www.vedattascier.com](https://www.vedattascier.com)
- Twitter: [@vedattascier](https://twitter.com/vedattascier)

## 📜 Versiyon Tarihi

| Versiyon | Tarih | Özellikler |
|----------|-------|-----------|
| **4.0 ENTERPRISE ML Enhanced** | Nisan 2026 | ML tabanlı risk tahmini, CVE taraması, davranış anomali tespiti, şifreleme analizi, tedarik zinciri riski, sıfır-gün heuristic'leri, akıllı remediasyon, baseline karşılaştırması |
| **3.0+ EXTENDED** | Mart 2026 | Kernel modülü, zamanlanmış görevler, capabilities, binary hardening, auditd, parola politikası, UMASK analizi |
| **3.0 ULTRA** | Şubat 2026 | PAM, SUDO, SSH, sysctl, mount, library injection, daemon privileges, core dump, MAC, firewall denetimleri |
| **2.7** | Ocak 2026 | Tam Turkish lokalizasyonu, tüm emoji'leriŞkaldırması, risk skoru capping |
| **2.5** | Aralık 2025 | Risk score 0-100 normalizasyonu |
| **2.2** | Kasım 2025 | Risk analizi ve öneriler sistemi |

---

⚠️ **Yasal İvazlı**: Bu araç yalnızca kendi sisteminizde ve yazılı izin verilen test ortamlarında kullanılmalıdır.


## 🙏 Teşekkürler

- GTFOBins projesi
- Linux topluluğu
- Güvenlik araştırmacıları

---

**Versiyon:** 3.0+ EXTENDED
**Son Güncelleme:** 2024

## 🧠 Akıllı Özellikler

### Otomatik Düzeltme Script'i
Risk analizine göre kişiselleştirilmiş bash script'i oluşturur:
- KRİTİK riskler için acil düzeltmeler
- Güvenlik duvarı yapılandırması
- SSH hardening
- Sistem güncellemeleri
- Sysctl güvenlik ayarları

### HTML Rapor
Profesyonel görünümlü HTML rapor:
- İnteraktif risk grafikleri
- Detaylı öneriler tablosu
- Teknik komut referansları
- Tarayıcıda görüntülenebilir

### SQLite Veritabanı
Geçmiş taramaları saklar ve karşılaştırır:
- Trend analizi
- Güvenlik durumu değişimi
- Geçmiş karşılaştırma tabloları
- İyileşme takibi

### Trend Analizi
Zaman içindeki güvenlik değişimini gösterir:
- Güvenlik durumunun iyileşip iyileşmediği
- Risk skorlarının karşılaştırması
- Düzenli tarama önerileri

## ⚠️ Önemli Uyarılar

### Yasal Uyarı
- **Bu araç sadece eğitim amaçlıdır**
- **Sadece kendi sisteminizde veya açık izin verilen sistemlerde kullanın**
- **Yetkisiz sistemlerde kullanmak yasa dışıdır**
- **Yasal sorumluluk tamamen kullanıcıya aittir**

### Privilege Escalation Tehlikesi
- `--privilege-escalation` seçeneği **ÇOK TEHLİKELİ**dir
- Sistemde kalıcı hasar verebilir
- Veri kaybına neden olabilir
- Sistem çökmelerine yol açabilir
- **SADECE TEST ORTAMLARINDA kullanın**
- **Üretim sistemlerinde ASLA kullanmayın**

### Güvenlik Tavsiyeleri
- Her zaman yedek alın
- Kritik sistemlerde kullanmayın
- Sonuçları dikkatlice değerlendirin
- Şüpheli durumlarda uzman danışın
