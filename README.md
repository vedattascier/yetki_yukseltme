# Yerel Linux Bilgi Toplama & Yetki Yükseltme Betiği

## 📋 Açıklama

Bu script, Linux sistemlerde yerel bilgi toplama ve potansiyel yetki yükseltme (privilege escalation) fırsatlarını taramak için tasarlanmış kapsamlı bir araçtır. Sistem bilgilerini, kullanıcı hesaplarını, yapılandırma dosyalarını ve güvenlik açıklarını analiz eder.

**Tam Türkçe versiyon - Tüm fonksiyonlar eksiksiz**

## ✨ Özellikler

- **Sistem Bilgileri**: Çekirdek, dağıtım, CPU, bellek ve disk bilgileri
- **Kullanıcı/Grup Analizi**: Hesaplar, gruplar, sudo yetkileri ve parola politikaları
- **Dosya Sistemi Taraması**: Yazılabilir dosyalar, SUID/SGID dosyaları, gizli dosyalar
- **Ağ Bilgileri**: Ağ arayüzleri, yönlendirme tabloları, açık portlar
- **Servis Analizi**: Çalışan servisler, cron job'ları, systemd zamanlayıcıları
- **Güvenlik Kontrolleri**: Parola politikaları, sudo yapılandırması, yetki açıkları
- **Çıktı Formatları**: Metin, Markdown, JSON
- **Risk Profilleri**: Strict, Standard, Relaxed
- **Otomatik Raporlama**: Detaylı rapor dosyaları oluşturma

## 🚀 Kurulum

### Gereksinimler

- Bash shell
- Standart Linux araçları (grep, find, awk, vb.)
- Root yetkileri (bazı kontroller için önerilir)

### İndirme

```bash
git clone https://github.com/vedattascier/yetki_yukseltme.git
cd yetki-yukseltme-script
chmod +x yetki_yukseltme.sh
```

## 📖 Kullanım

### Temel Kullanım

```bash
./yetki_yukseltme.sh
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
| `--version` | Versiyon göster |

### Örnekler

```bash
# Normal tarama
./yetki_yukseltme.sh

# Hızlı tarama + sadece özet
./yetki_yukseltme.sh -f -q

# Ayrıntılı tarama + JSON çıktısı
./yetki_yukseltme.sh -t -j | tee rapor.json

# Anahtar kelime arama
./yetki_yukseltme.sh -k "password"

# Dışa aktarma
./yetki_yukseltme.sh -e ./export-dizini

# Özel rapor dosyası
./yetki_yukseltme.sh -r ./benim-raporum.txt
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
- `/tmp/yetkiyukseltme_report_TIMESTAMP.txt`: Detaylı rapor
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

## 🙏 Teşekkürler

- GTFOBins projesi
- Linux topluluğu
- Güvenlik araştırmacıları

---

**Versiyon:** 2.0
**Son Güncelleme:** 2024</content>
<parameter name="filePath">c:\Users\vedat\OneDrive\Masaüstü\README.md
