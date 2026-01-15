#!/bin/bash
# VPS Monitor - Real-time VPS monitoring tool
# by @killu_zl

# Проверка на команду обновления
if [ "$1" = "--update" ] || [ "$1" = "-u" ]; then
    echo "🔄 Обновление VPS Monitor..."
    curl -sSL https://raw.githubusercontent.com/Killu-zl/vps-monitor/main/install.sh | sudo bash
    exit 0
fi

# Цвета
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функция выбора цвета по загрузке
get_color() {
    local val=${1%.*}
    [ $val -lt 50 ] && echo "$GREEN" || [ $val -lt 80 ] && echo "$YELLOW" || echo "$RED"
}

# CPU модель
get_cpu_model() {
    local cpu=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)
    [ -z "$cpu" ] && cpu=$(lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | xargs)
    cpu=$(echo "$cpu" | sed 's/RHEL [0-9.]*//g; s/QEMU.*//g; s/@ [0-9.]*GHz//g; s/(R)//g; s/(TM)//g; s/  */ /g' | xargs)
    [ ${#cpu} -lt 3 ] && cpu="Virtual CPU"
    echo "$cpu"
}

# Сетевой интерфейс
get_interface() {
    local iface=$(ip route | grep default | awk '{print $5}' | head -1)
    [ -z "$iface" ] && iface=$(ls /sys/class/net/ 2>/dev/null | grep -v "^lo$" | head -1)
    echo "$iface"
}

# Сетевая статистика
get_net_bytes() {
    local iface=$(get_interface)
    [ -z "$iface" ] && echo "0 0" && return
    local rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    echo "$rx $tx"
}

# Форматирование в Mbit/s
format_speed() {
    local bytes=$1
    local mbits=$(awk "BEGIN {printf \"%.2f\", ($bytes * 8) / 1000000}")
    if (( $(awk "BEGIN {print ($mbits < 1)}") )); then
        local kbits=$(awk "BEGIN {printf \"%.2f\", ($bytes * 8) / 1000}")
        echo "${kbits} Kbit/s"
    else
        echo "${mbits} Mbit/s"
    fi
}

# IP адреса
get_ip() {
    local ip4=$(curl -4 -s --max-time 2 ifconfig.me 2>/dev/null)
    local ip6=$(curl -6 -s --max-time 2 ifconfig.me 2>/dev/null)
    [ -n "$ip4" ] && [ -n "$ip6" ] && echo "$ip4 / $ip6" && return
    [ -n "$ip4" ] && echo "$ip4" && return
    [ -n "$ip6" ] && echo "$ip6" && return
    echo "N/A"
}

# Информация о хостинге
get_hosting_info() {
    local ip=$1
    local data=$(curl -s --max-time 3 "http://ip-api.com/json/$ip?fields=org,city,regionName,country" 2>/dev/null)
    [ -z "$data" ] && echo "N/A|N/A|N/A|N/A" && return
    local org=$(echo "$data" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
    local city=$(echo "$data" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
    local region=$(echo "$data" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
    local country=$(echo "$data" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
    echo "$org|$city|$region|$country"
}

# Скрыть курсор и настроить выход
tput civis
trap 'tput cnorm; clear; echo ""; echo "✅ Мониторинг остановлен."; echo ""; echo "💡 Для фона: tmux new -s monitor"; echo ""; exit 0' EXIT INT TERM

# Загрузка конфигурации
echo -e "${CYAN}Загрузка информации о сервере...${NC}"
CPU_MODEL=$(get_cpu_model)
CPU_CORES=$(nproc)
TOTAL_RAM=$(free -h | awk 'NR==2{print $2}')
DISK_SIZE=$(df -h / | awk 'NR==2{print $2}')
IP_ADDR=$(get_ip)
UPTIME=$(uptime -p | sed 's/up //')
IP_FOR_LOOKUP=$(echo "$IP_ADDR" | awk '{print $1}')
IFS='|' read -r ORG LOC REG COUNTRY <<< $(get_hosting_info "$IP_FOR_LOOKUP")

# Инициализация
read rx_prev tx_prev <<< $(get_net_bytes)
cpu_hist=(0 0 0 0 0 0 0 0 0 0)
rx_hist=(0 0 0 0 0 0 0 0 0 0)
tx_hist=(0 0 0 0 0 0 0 0 0 0)
idx=0
spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
sidx=0
cache_counter=0

# Кэш для тяжелых операций (обновляется раз в 5 сек)
tcp_cached=""
udp_cached=""
top_cpu_cached=""
top_mem_cached=""

echo -e "${CYAN}Инициализация...${NC}"
tcp_cached=$(ss -tan 2>/dev/null | grep -c ESTAB || echo 0)
udp_cached=$(ss -uant 2>/dev/null | tail -n +2 | wc -l || echo 0)
top_cpu_cached=$(ps aux --sort=-%cpu | awk 'NR>1 && NR<5{printf "  %-25s %5.1f%%\n", substr($11,1,25), $3}')
top_mem_cached=$(ps aux --sort=-%mem | awk 'NR>1 && NR<5{printf "  %-25s %5.1f%%\n", substr($11,1,25), $4}')

sleep 1
clear

# Главный цикл
while true; do
    tput cup 0 0
    
    # Конфигурация сервера
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                 КОНФИГУРАЦИЯ СЕРВЕРА                       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}CPU:${NC}          $CPU_MODEL"
    echo -e "${CYAN}Ядра:${NC}         $CPU_CORES cores"
    echo -e "${CYAN}RAM:${NC}          $TOTAL_RAM"
    echo -e "${CYAN}Диск:${NC}         $DISK_SIZE"
    echo -e "${CYAN}IP:${NC}           $IP_ADDR"
    echo -e "${CYAN}Uptime:${NC}       $UPTIME"
    [ "$ORG" != "N/A" ] && [ -n "$ORG" ] && echo -e "${CYAN}Organization:${NC} $ORG"
    [ "$ORG" != "N/A" ] && [ -n "$ORG" ] && echo -e "${CYAN}Location:${NC}     $LOC / $COUNTRY"
    [ "$REG" != "N/A" ] && [ -n "$REG" ] && echo -e "${CYAN}Region:${NC}       $REG"
    echo ""
    
    # Заголовок с временем
    TIME=$(date '+%H:%M:%S')
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          Мониторинг в реальном времени - ${TIME}          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # CPU
    if command -v mpstat &>/dev/null; then
        cpu_curr=$(mpstat 1 1 | awk '/Average/{print 100-$NF}')
    else
        cpu_line=$(top -bn1 | grep "Cpu(s)" | head -1)
        cpu_us=$(echo "$cpu_line" | awk '{print $2}' | tr -d '%us,')
        cpu_sy=$(echo "$cpu_line" | awk '{print $4}' | tr -d '%sy,')
        cpu_ni=$(echo "$cpu_line" | awk '{print $6}' | tr -d '%ni,')
        [ -z "$cpu_us" ] && cpu_us=0
        [ -z "$cpu_sy" ] && cpu_sy=0
        [ -z "$cpu_ni" ] && cpu_ni=0
        cpu_curr=$(awk "BEGIN{printf \"%.1f\",$cpu_us+$cpu_sy+$cpu_ni}")
    fi
    cpu_hist[$idx]=$cpu_curr
    cpu_sum=0; for v in "${cpu_hist[@]}"; do cpu_sum=$(awk "BEGIN{printf \"%.1f\",$cpu_sum+$v}"); done
    cpu_avg=$(awk "BEGIN{printf \"%.1f\",$cpu_sum/10}")
    cpu_color=$(get_color $cpu_avg)
    cpu_bar=$((${cpu_avg%.*}/5))
    echo -e "${GREEN}▶ CPU загрузка:${NC}"
    echo -e "  ${cpu_color}${cpu_avg}%${NC}"
    printf "  ["; for((i=0;i<20;i++)); do [ $i -lt $cpu_bar ] && printf "${cpu_color}█${NC}" || printf "░"; done; printf "]\n"
    echo ""
    
    # RAM
    mem_info=$(free -m | awk 'NR==2{printf "%d %d %.1f",$3,$2,($3/$2)*100}')
    read mem_used mem_total mem_pct <<< "$mem_info"
    mem_color=$(get_color $mem_pct)
    mem_bar=$((${mem_pct%.*}/5))
    echo -e "${GREEN}▶ RAM использование:${NC}"
    echo -e "  ${mem_color}${mem_used}MB / ${mem_total}MB (${mem_pct}%)${NC}"
    printf "  ["; for((i=0;i<20;i++)); do [ $i -lt $mem_bar ] && printf "${mem_color}█${NC}" || printf "░"; done; printf "]\n"
    echo ""
    
    # Сеть
    read rx_curr tx_curr <<< $(get_net_bytes)
    rx_diff=$((rx_curr-rx_prev)); [ $rx_diff -lt 0 ] && rx_diff=0
    tx_diff=$((tx_curr-tx_prev)); [ $tx_diff -lt 0 ] && tx_diff=0
    rx_hist[$idx]=$rx_diff
    tx_hist[$idx]=$tx_diff
    rx_sum=0; tx_sum=0
    for i in {0..9}; do rx_sum=$((rx_sum+${rx_hist[$i]})); tx_sum=$((tx_sum+${tx_hist[$i]})); done
    rx_avg=$((rx_sum/10))
    tx_avg=$((tx_sum/10))
    iface=$(get_interface)
    spin="${spinner[$sidx]}"
    echo -e "${GREEN}▶ Сетевой трафик ($iface): ${CYAN}${spin}${NC}"
    echo -e "  ${YELLOW}↓${NC} Входящий:  $(format_speed $rx_avg)"
    echo -e "  ${RED}↑${NC} Исходящий: $(format_speed $tx_avg)"
    echo ""
    
    # Диск
    disk_info=$(df -h / | awk 'NR==2{print $3,$2,$5}')
    read disk_used disk_total disk_pct <<< "$disk_info"
    echo -e "${GREEN}▶ Диск (/):${NC}"
    echo "  $disk_used / $disk_total ($disk_pct)"
    echo ""
    
    # Соединения (кэш раз в 5 сек)
    if [ $cache_counter -eq 0 ]; then
        tcp_cached=$(ss -tan 2>/dev/null | grep -c ESTAB || echo 0)
        udp_cached=$(ss -uant 2>/dev/null | tail -n +2 | wc -l || echo 0)
        top_cpu_cached=$(ps aux --sort=-%cpu | awk 'NR>1 && NR<5{printf "  %-25s %5.1f%%\n", substr($11,1,25), $3}')
        top_mem_cached=$(ps aux --sort=-%mem | awk 'NR>1 && NR<5{printf "  %-25s %5.1f%%\n", substr($11,1,25), $4}')
    fi
    echo -e "${GREEN}▶ Сетевые соединения:${NC}"
    echo "  TCP: ${CYAN}${tcp_cached}${NC}  |  UDP: ${CYAN}${udp_cached}${NC}"
    echo ""
    echo -e "${GREEN}▶ Топ-3 процесса по CPU:${NC}"
    echo "$top_cpu_cached"
    echo ""
    echo -e "${GREEN}▶ Топ-3 процесса по RAM:${NC}"
    echo "$top_mem_cached"
    echo ""
    echo -e "${CYAN}Ctrl+C для выхода | Для фона: tmux new -s monitor${NC}"
    
    tput ed
    rx_prev=$rx_curr
    tx_prev=$tx_curr
    idx=$(((idx+1)%10))
    sidx=$(((sidx+1)%10))
    cache_counter=$(((cache_counter+1)%5))
    sleep 1
done
