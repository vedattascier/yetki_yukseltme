#!/usr/bin/env bash

# Yerel Linux Bilgi Toplama & Yetki Yükseltme Betiği
# Tam Türkçe versiyon - Tüm fonksiyonlar eksiksiz
# @vedattascier

version="sürüm 2.0"
output_format="text"   # text | md | json
risk_profile="standard" # strict | standard | relaxed
quiet=""                 # 1 = sadece özetleri/önerileri göster
auto=""                  # 1 = otomatik çalıştır
interrupted=0            # kesinti durumunda
use_colors="1"          # 1 = renk kodları kullan
fast_mode=""            # 1 = hızlı tarama
MAX_FIND_RESULTS=${MAX_FIND_RESULTS:-200}
FIND_TIMEOUT=${FIND_TIMEOUT:-20}
REPORT_FILE="${REPORT_FILE:-/tmp/yetkiyukseltme_report_$(date +%Y%m%d_%H%M%S).txt}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
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
  echo "[$sev] $msg" >> "$REPORT_FILE"
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
  echo -e "${CYAN}⏱️  Geçen süre: ${elapsed}s${NC}"
}

# Güvenli dosya okuması
safe_read_file() {
  [ -r "$1" ] && cat "$1" 2>/dev/null || echo ""
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
echo "  --version               Versiyon"
echo
echo -e "${CYAN}ÖRNEKLER:${NC}"
echo "  $0                    # Normal tarama"
echo "  $0 -f -q              # Hızlı + özet"
echo "  $0 -t -j | tee o.json # Ayrıntılı + JSON"
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
writable_suid=`find / -perm -4000 -writable 2>/dev/null`
if [ "$writable_suid" ]; then
  echo -e "\e[00;31m[!] KRİTİK - Yazılabilir SUID dosyaları:\e[00m\n$writable_suid"
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
writable_cron=`find /etc/cron* -writable 2>/dev/null`
if [ "$writable_cron" ]; then
  echo -e "\e[00;31m[!] KRİTİK - Yazılabilir cron dosyaları:\e[00m\n$writable_cron"
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
echo -e "searchsploit linux privilege escalation"

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

echo -e "\n\e[00;31m[-] World-writable dosyalar:\e[00m"
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

# Privilege Escalation Tools
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

  echo -e "\n${CYAN}[-] World-writable dosya/dizin taraması (hızlı):${NC}"
  find / -xdev \( -type f -perm -002 -o -type d -perm -002 \) ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | head -50 | while read -r f; do
      echo -e "${YELLOW}[!] World-writable: $f${NC}"
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
    ["2.6.22-2.6.24"]="CVE-2008-0600 - vmsplice Local Privilege Escalation|https://www.exploit-db.com/exploits/5092"
    ["2.6.17-2.6.24"]="CVE-2008-0001 - dmesg Restriction Bypass|https://www.exploit-db.com/exploits/5093"
    ["2.6.19-2.6.31"]="CVE-2009-1185 - pipe.c Local Privilege Escalation|https://www.exploit-db.com/exploits/3334"
    ["2.6.36-3.0"]="CVE-2010-4259 - Econet Privilege Escalation|https://www.exploit-db.com/exploits/15704"
    ["3.13-3.19"]="CVE-2015-1328 - overlayfs Privilege Escalation|https://www.exploit-db.com/exploits/37292"
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
    
    if [[ -n "${service_ports[$port]}" ]]; then
        service_info="${service_ports[$port]}"
        echo -e "\e[00;33m[!] AÇIK PORT $port: $service_info\e[00m"
        echo -e "\e[00;32m      -> Servis: $service\e[00m"
        log_finding "HIGH" "Açık Port $port | $service_info | $service"
        high_count=$((high_count + 1))
        risk_score=$((risk_score + 12))
    else
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

# World-writable dizinler
echo -e "\n\e[00;31m[-] World-Writable Dizinler:\e[00m"
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

# Gelişmiş Raporlama ve Öneri Sistemi
advanced_reporting() {
echo -e "\e[00;33m### GELİŞMİŞ RAPORLAMA VE ÖNERİ SİSTEMİ ########\e[00m"

# Risk seviyesi hesaplama
if [ "$risk_score" -gt 80 ]; then
    risk_level="KRİTİK"
    risk_color="\e[00;31m"
    urgency="ACİL MÜDAHALE GEREKLİ"
elif [ "$risk_score" -gt 60 ]; then
    risk_level="ÇOK YÜKSEK"
    risk_color="\e[00;31m"
    urgency="HIZLICA DÜZELTİLMELİ"
elif [ "$risk_score" -gt 40 ]; then
    risk_level="YÜKSEK"
    risk_color="\e[00;33m"
    urgency="KISA SÜREDE DÜZELTİLMELİ"
elif [ "$risk_score" -gt 20 ]; then
    risk_level="ORTA"
    risk_color="\e[00;35m"
    urgency="DÜZELTİLMELİ"
else
    risk_level="DÜŞÜK"
    risk_color="\e[00;32m"
    urgency="GÖZDEN GEÇİRİLMELİ"
fi

echo -e "\n$risk_color================================================${NC}"
echo -e "$risk_color              GELİŞMİŞ GÜVENLİK RAPORU              ${NC}"
echo -e "$risk_color================================================${NC}"
echo ""

echo -e "\e[00;31m📊 RİSK ANALİZİ:${NC}"
echo -e "${risk_color}Genel Risk Skoru: $risk_score/100${NC}"
echo -e "${risk_color}Risk Seviyesi: $risk_level${NC}"
echo -e "${risk_color}Öncelik: $urgency${NC}"
log_finding "ÖZET" "Genel Risk Skoru: $risk_score/100"
log_finding "ÖZET" "Risk Seviyesi: $risk_level"
log_finding "ÖZET" "Öncelik: $urgency"
echo ""

echo -e "\e[00;31m📈 BULGU İSTATİSTİKLERİ:${NC}"
echo -e "\e[00;31mKRİTİK Bulgular: $critical_count${NC}"
echo -e "\e[00;33mYÜKSEK Riskli: $high_count${NC}"
echo -e "\e[00;35mORTA Riskli: $medium_count${NC}"
echo -e "\e[00;32mDÜŞÜK Riskli: $low_count${NC}"
log_finding "ÖZET" "KRİTİK: $critical_count | YÜKSEK: $high_count | ORTA: $medium_count | DÜŞÜK: $low_count"
echo ""

echo -e "\e[00;31m🎯 ÖNCELİKLİ EYLEMLER:${NC}"

if [ "$critical_count" -gt 0 ]; then
    echo -e "\e[00;31m🚨 KRİTİK ÖNCELİK:${NC}"
    echo -e "   • Derhal yetki yükseltme zafiyetlerini düzeltin"
    echo -e "   • Container kaçış yollarını kapatın"
    echo -e "   • Hassas dosya erişimlerini kısıtlayın"
fi

if [ "$high_count" -gt 0 ]; then
    echo -e "\e[00;33m⚠️  YÜKSEK ÖNCELİK:${NC}"
    echo -e "   • Güvenlik duvarı kurallarını gözden geçirin"
    echo -e "   • Servis konfigürasyonlarını güçlendirin"
    echo -e "   • Parola politikalarını güncelleyin"
fi

echo -e "\e[00;31m🔧 GÜVENLİK ÖNERİLERİ:${NC}"
echo -e "   1. Sistemi güncel tutun (kernel, paketler)"
echo -e "   2. Minimum prensibiyle çalıştırın (gerekli servisler)"
echo -e "   3. Güçlü parola politikaları uygulayın"
echo -e "   4. Çok faktörlü kimlik doğrulama kullanın"
echo -e "   5. Loglama ve monitoring sistemi kurun"
echo -e "   6. Düzenli güvenlik taramaları yapın"
echo -e "   7. Yedekleme ve disaster recovery planı"
echo -e "   8. Ağ segmentasyonu uygulayın"
echo -e "   9. Güvenlik duvarı ve IDS/IPS kurun"
echo -e "   10. Personel güvenlik eğitimi"

echo -e "\e[00;31m📚 EK KAYNAKLAR:${NC}"
echo -e "   • OWASP Top 10: https://owasp.org/www-project-top-ten/"
echo -e "   • CIS Benchmarks: https://www.cisecurity.org/"
echo -e "   • NIST Cybersecurity Framework"
echo -e "   • Linux Security Hardening Guides"
echo -e "   • Container Security Best Practices"

echo -e "\e[00;33m📌 BU SONUÇLARA GÖRE NE YAPMALISINIZ?${NC}"
if [ "$critical_count" -gt 0 ]; then
    echo -e "   • KRİTİK bulguları öncelikli olarak kapatın. Root yetkisi gerektiren SUID/SGID açıklarını tespit edip düzeltin."
    echo -e "   • /etc/shadow, /root/.ssh ve world-writable dosya izinlerini hemen inceleyin."
fi
if [ "$high_count" -gt 0 ]; then
    echo -e "   • Yüksek riskli bulgular için servis ve yapılandırma izinlerine bakın."
    echo -e "   • sudo, cron ve service dosyalarını kontrol ederek hatalı izinleri düzeltin."
fi
if [ "$medium_count" -gt 0 ]; then
    echo -e "   • Orta riskli noktaları ele alın: yapılandırma dosyası izinleri, export edilmiş kimlik bilgileri, backup dosyaları."
fi
if [ "$low_count" -gt 0 ]; then
    echo -e "   • Düşük riskli bulguları kayıt altına alıp düzenli taramaları tekrarlayın."
fi

echo -e "\e[00;33m📝 Rapor dosyası: $REPORT_FILE${NC}"
echo -e "\e[00;33m📝 Kaydedilen sonuç: $RESULT_FILE${NC}"
}

# Footer fonksiyonu
footer() {
    local scan_end_time=$(date +%s)
    local total_time=$((scan_end_time - SCAN_START_TIME))
    
    echo ""
    echo -e "${YELLOW}================================================${NC}"
    echo -e "${YELLOW}TARAMA TAMAMLANDI${NC}"
    echo -e "${YELLOW}================================================${NC}"
    echo -e "${CYAN}Başlangıç: $SCAN_START_DATE${NC}"
    echo -e "${CYAN}Bitiş: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}Toplam Süre: ${total_time}s${NC}"
    echo ""
    echo -e "${CYAN}📊 RİSK ÖZETI:${NC}"
    echo -e "  ${RED}Kritik: $critical_count${NC}"
    echo -e "  ${RED}Yüksek: $high_count${NC}"
    echo -e "  ${YELLOW}Orta: $medium_count${NC}"
    echo -e "  ${GREEN}Düşük: $low_count${NC}"
    echo -e "  ${MAGENTA}Risk Puanı: $risk_score${NC}"
    echo ""
    echo -e "${GREEN}✅ Rapor dosyası: $RESULT_FILE${NC}"
    echo ""
    echo -e "${GREEN}Güvenli günler dilerim!${NC}"
    echo ""
}

# Gelişmiş ana tarama fonksiyonu
advanced_call_each() {
    echo -e "${YELLOW}🚀 GELİŞMİŞ YETKİ YÜKSELTME TARAMASI BAŞLATILIYOR...${NC}"
    echo -e "${CYAN}⏰ Başlangıç: $SCAN_START_DATE${NC}"
    echo ""

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
          no-colors)
            disable_colors
            use_colors=""
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