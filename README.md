# Linux Yetki Yükseltme Denetim Aracı

Bu betik, Linux sistemlerde kapsamlı yerel güvenlik değerlendirmesi ve yetki yükseltme analizleri yapmak için tasarlanmıştır. Script; sistem bilgileri, dosya izinleri, ağ güvenliği, servis yapılandırmaları, CVE kontrolü ve ML tabanlı anomali analizini aynı anda yürütür.

## Önemli Not
- Rapor dosyaları **script dosyasının bulunduğu dizinde** oluşturulur.
- İki ayrı dosya üretilir:
  - sonuclar.txt veya sonuclar_N.txt - ana terminal çıktısı ve tarama sonuçları
  - yetkiyukseltme_report_TIMESTAMP.txt - detaylı rapor
- Raporlar aynı dizinde, farklı isimlerle kaydedilir.

## Temel Özellikler
- Tam Türkçe arayüz ve açıklamalar
- Risk puanlaması: 0-100 arası
- ML ve CVE tabanlı ek analizler
- Detaylı sistem ve kullanıcı denetimleri
- Dosya sistemi, ağ, servis ve zamanlayıcı incelemeleri
- SUID/SGID, yazılabilir dosya ve PATH güvenliği kontrolleri
- SSH, sudo, PAM, sysctl, firewall, auditd gibi temel alanların analizi
- Otomatik düzeltme önerileri ve akıllı güvenlik tavsiyeleri
- HTML, JSON, Markdown ve SQLite destekli raporlama

## En Yeni Eklenen Özellikler
- Makine öğrenmesi tabanlı risk tahmini
- CVE açıklık taraması
- Anomali tespiti (LD_PRELOAD, zombi işlemler, yazılabilir sistem binary'leri)
- Akıllı onarım ve sistem postürü değerlendirmesi
- Rapor dosyası içeriğini tarama sonrası otomatik ekrana yazdırma
- Rapor dosyalarının script dizininde saklanması

## Kullanım

`ash
./linux-yetki-yukseltme.sh
`

### Seçenekler

- -h, --help : Yardım mesajını gösterir
- -v : Ayrıntılı çıktı modu
- -q : Sessiz mod / yalnızca özet
- -j : JSON formatında çıktı
- -m : Markdown formatında çıktı
- -f : Hızlı tarama (kısaltılmış dosya arama)
- -t : Kapsamlı tarama
- -k <anahtar> : Anahtar kelime araması
- -e <dizin> : Dışa aktarım dizini
- -p : Sudo parolası sor
- -r <dosya> : Özel rapor adı
- --no-colors : Renkli çıktıyı kapat
- --fix-script : Otomatik düzeltme script'i oluşturur
- --html-report : HTML raporu oluşturur
- --database : SQLite veritabanı kaydı sağlar
- --version : Versiyon bilgisini gösterir

## Örnek Komutlar

`bash
# Normal tarama
./linux-yetki-yukseltme.sh

# Hızlı tarama ve sadece özet
./linux-yetki-yukseltme.sh -f -q

# JSON çıktısı ile ayrıntılı tarama
./linux-yetki-yukseltme.sh -t -j

# HTML rapor oluşturma
./linux-yetki-yukseltme.sh --html-report

# SQLite geçmiş kaydı
./linux-yetki-yukseltme.sh --database

# Özel rapor dosyası ile çalıştırma
./linux-yetki-yukseltme.sh -r ./ozel_rapor.txt
`

## Raporlar

Script çalıştırıldığında en son rapor dosyası otomatik olarak ekrana yazdırılır. Bu sayede kullanıcı hem terminal çıktısını hem de rapor içeriğini aynı anda görebilir.

### Oluşturulan Dosyalar
- sonuclar.txt veya sonuclar_N.txt
- yetkiyukseltme_report_TIMESTAMP.txt
- security_scans.db (SQLite destekliyse)

## Tarama Kapsamı

### Sistem Bilgileri
- Çekirdek versiyonu
- Dağıtım bilgileri
- Bellek ve disk kullanımı
- İşlemci ve ağ bilgileri

### Kullanıcı / Grup Denetimi
- Kullanıcı hesapları
- Sudoer yapılandırması
- Parola politikaları
- Shadow dosya izinleri

### Dosya Sistemi Güvenliği
- SUID/SGID dosyaları
- Dünya tarafından yazılabilir dosyalar
- Yazılabilir sistem binary'leri
- Kütüphane enjeksiyonu riskleri

### Ağ ve Servis Analizi
- SSH, iptables, UFW
- Açık portlar
- Cron / systemd timer
- Daemon ve servis güvenliği

### Ek Güvenlik Analizleri
- CVE tabanlı sürüm kontrolü
- ML tabanlı anomali analizi
- Tedarik zinciri riski
- Sıfır-gün heuristikleri
- Auditd hazır hâli
- Şifreleme ve TLS kontrolleri

## Risk Değerlendirme

### Seviyeler
- **KRİTİK** : Acil müdahale gerek
- **ÇOK YÜKSEK** : Hızlı düzeltme gerek
- **YÜKSEK** : Kısa sürede iyileştirilmeli
- **ORTA** : Düzenli bakım gerekli
- **DÜŞÜK** : İzlenebilir

## Yasal Uyarı

Bu araç yalnızca kendi sisteminizde veya yazılı izin verilen test ortamlarında kullanılmalıdır. Yetkisiz erişim ve testler yasal sorumluluk doğurur.

---

**Not:** README bu sürüme özel olarak güncellendi. Dosya çıktıları artık script dizininde tutuluyor ve rapor dosyası tarama sonunda ekrana yazdırılıyor.
