#!/bin/bash
# VPS Monitor - Real-time VPS monitoring tool
# by @killu_zl

# Проверка на команду обновления
if [ "$1" = "--update" ] || [ "$1" = "-u" ]; then
    echo "🔄 Обновление VPS Monitor..."
    curl -sSL https://raw.githubusercontent.com/Killu-zl/vps-monitor/main/install.sh | sudo bash
    exit 0
fi

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция для выбора цвета в зависимости от загрузки
get_load_color() {
    local load=$1
    local load_int=${load%.*}
    
    if [ $load_int -lt 50 ]; then
        echo "$GREEN"
    elif [ $load_int -lt 80 ]; then
        echo "$YELLOW"
    else
        echo "$RED"
    fi
}

# Функция для получения информации о CPU
get_cpu_model() {
    cpu_raw=""
    
    # Метод 1: /proc/cpuinfo (самый надежный)
    cpu_raw=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d ':' -f2 | xargs)
    
    # Метод 2: lscpu если /proc/cpuinfo не сработал
    if [ -z "$cpu_raw" ] || [ "$cpu_raw" = "+" ] || [ ${#cpu_raw} -lt 3 ]; then
        cpu_raw=$(lscpu 2>/dev/null | grep "Model name" | cut -d ':' -f2 | xargs)
    fi
    
    # Метод 3: Пробуем получить через dmidecode (требует root)
    if [ -z "$cpu_raw" ] || [ "$cpu_raw" = "+" ] || [ ${#cpu_raw} -lt 3 ]; then
        if command -v dmidecode &> /dev/null; then
            cpu_raw=$(dmidecode -t processor 2>/dev/null | grep "Version:" | head -1 | cut -d ':' -f2 | xargs)
        fi
    fi
    
    # Если ничего не нашли
    if [ -z "$cpu_raw" ] || [ "$cpu_raw" = "+" ] || [ ${#cpu_raw} -lt 3 ]; then
        echo "Virtual CPU"
        return
    fi
    
    # Убираем мусор от виртуализации и лишнюю информацию
    cpu_clean=$(echo "$cpu_raw" | \
        sed 's/RHEL [0-9.]*//g' | \
        sed 's/PC (i440FX + PIIX, [0-9]*)//' | \
        sed 's/QEMU Virtual CPU version [0-9.]*//g' | \
        sed 's/Common KVM processor//g' | \
        sed 's/@ [0-9.]*GHz//g' | \
        sed 's/ CPU @//g' | \
        sed 's/CPU @//g' | \
        sed 's/(R)//g' | \
        sed 's/(TM)//g' | \
        sed 's/(tm)//g' | \
        sed 's/  */ /g' | \
        xargs)
    
    # Финальная проверка
    if [ -z "$cpu_clean" ] || [ "$cpu_clean" = "+" ] || [ ${#cpu_clean} -lt 3 ]; then
        echo "Virtual CPU"
    else
        echo "$cpu_clean"
    fi
}

# Функция для получения количества ядер
get_cpu_cores() {
    nproc
}

# Функция для получения общей RAM
get_total_ram() {
    free -h | awk 'NR==2{print $2}'
}

# Функция для получения размера диска
get_disk_size() {
    df -h / | awk 'NR==2{print $2}'
}

# Функция для получения IP адресов
get_ip_addresses() {
    local ipv4=""
    local ipv6=""
    
    # Получаем IPv4
    ipv4=$(curl -4 -s --max-time 2 ifconfig.me 2>/dev/null || curl -4 -s --max-time 2 icanhazip.com 2>/dev/null)
    
    # Получаем IPv6
    ipv6=$(curl -6 -s --max-time 2 ifconfig.me 2>/dev/null || curl -6 -s --max-time 2 icanhazip.com 2>/dev/null)
    
    # Если IPv4 не получен, пробуем через ip route
    if [ -z "$ipv4" ]; then
        ipv4=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    fi
    
    # Формируем вывод
    if [ -n "$ipv4" ] && [ -n "$ipv6" ]; then
        echo "$ipv4 / $ipv6"
    elif [ -n "$ipv4" ]; then
        echo "$ipv4"
    elif [ -n "$ipv6" ]; then
        echo "$ipv6"
    else
        echo "N/A"
    fi
}

# Функция для получения информации о сети/хостинге
get_network_info() {
    local ip=$1
    # Пробуем получить информацию через ip-api.com
    network_data=$(curl -s --max-time 3 "http://ip-api.com/json/$ip?fields=org,city,regionName,country" 2>/dev/null)
    
    if [ -n "$network_data" ]; then
        org=$(echo "$network_data" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
        city=$(echo "$network_data" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
        region=$(echo "$network_data" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
        country=$(echo "$network_data" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
        
        echo "$org|$city|$region|$country"
    else
        echo "N/A|N/A|N/A|N/A"
    fi
}

# Функция для получения аптайма
get_uptime_formatted() {
    uptime -p | sed 's/up //'
}

# Функция для получения количества сетевых соединений
get_network_connections() {
    # Быстрый подсчет без полного парсинга
    local tcp_count=$(ss -tan 2>/dev/null | grep -c ESTAB || echo 0)
    local udp_count=$(ss -uant 2>/dev/null | tail -n +2 | wc -l || echo 0)
    echo "$tcp_count $udp_count"
}

# Скрыть курсор
tput civis

# Функция очистки при выходе
cleanup() {
    tput cnorm  # Показать курсор
    tput sgr0   # Сброс форматирования
    clear       # Очистить экран
    echo ""
    echo "✅ Мониторинг остановлен."
    echo ""
    echo "💡 Совет: Для фонового запуска используйте tmux:"
    echo "   sudo apt install tmux -y          # Установка"
    echo "   tmux new -s monitor               # Создать сессию"
    echo "   monitor                           # Запустить"
    echo "   Ctrl+B, затем D                   # Отсоединиться"
    echo "   tmux attach -t monitor            # Вернуться"
    echo ""
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Функция для получения имени основного сетевого интерфейса
get_network_interface() {
    local interface=""
    
    # Метод 1: Через default route
    interface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    # Метод 2: Если не нашли, ищем активные интерфейсы
    if [ -z "$interface" ]; then
        for iface in eth0 ens3 enp0s3 enp0s8 ens18 ens19 venet0; do
            if [ -d "/sys/class/net/$iface" ]; then
                state=$(cat /sys/class/net/$iface/operstate 2>/dev/null)
                if [ "$state" = "up" ]; then
                    interface=$iface
                    break
                fi
            fi
        done
    fi
    
    # Метод 3: Берем первый активный интерфейс (не lo)
    if [ -z "$interface" ]; then
        interface=$(ls /sys/class/net/ | grep -v "^lo$" | head -1)
    fi
    
    echo "$interface"
}

# Функция для получения сетевого трафика
get_network_stats() {
    # Определяем основной сетевой интерфейс
    local interface=$(get_network_interface)
    
    # Читаем статистику для найденного интерфейса
    if [ -n "$interface" ] && [ -d "/sys/class/net/$interface" ]; then
        rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
    else
        rx_bytes=0
        tx_bytes=0
    fi
    
    echo "$rx_bytes $tx_bytes"
}

# Функция для форматирования байтов в Mbit/s
format_bytes() {
    local bytes=$1
    # Конвертируем байты в мегабиты (1 байт = 8 бит, 1 мегабит = 1000000 бит)
    local mbits=$(awk "BEGIN {printf \"%.2f\", ($bytes * 8) / 1000000}")
    
    # Если меньше 1 Mbit/s, показываем в Kbit/s
    if (( $(awk "BEGIN {print ($mbits < 1)}") )); then
        local kbits=$(awk "BEGIN {printf \"%.2f\", ($bytes * 8) / 1000}")
        echo "${kbits} Kbit/s"
    else
        echo "${mbits} Mbit/s"
    fi
}

# Получаем начальные значения трафика
read rx_prev tx_prev <<< $(get_network_stats)

# Массивы для сглаживания значений (храним последние 10 измерений для лучшего усреднения)
cpu_history=(0 0 0 0 0 0 0 0 0 0)
rx_history=(0 0 0 0 0 0 0 0 0 0)
tx_history=(0 0 0 0 0 0 0 0 0 0)
history_index=0
history_size=10

# Анимация спиннера
spinner_frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
spinner_index=0

# Счетчик для кэширования тяжелых операций
cache_counter=0
cache_interval=5  # Обновлять тяжелые данные раз в 5 секунд

# Кэшированные данные
cached_tcp_conn=""
cached_udp_conn=""
cached_top_processes=""

# Получаем конфигурацию сервера (один раз)
echo -e "${CYAN}Загрузка информации о сервере...${NC}"
CPU_MODEL=$(get_cpu_model)
CPU_CORES=$(get_cpu_cores)
TOTAL_RAM=$(get_total_ram)
DISK_SIZE=$(get_disk_size)
IP_ADDR=$(get_ip_addresses)
UPTIME=$(get_uptime_formatted)

# Получаем информацию о сети/хостинге (используем первый IPv4 для определения)
IP_FOR_LOOKUP=$(echo "$IP_ADDR" | awk '{print $1}')
IFS='|' read -r ORGANIZATION LOCATION REGION COUNTRY <<< $(get_network_info "$IP_FOR_LOOKUP")

sleep 1

# Очищаем экран один раз
clear

# Основной цикл
while true; do
    # Перемещаем курсор в начало (вместо clear)
    tput cup 0 0
    
    # Конфигурация сервера (статичная информация)
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                   КОНФИГУРАЦИЯ СЕРВЕРА                     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}CPU:${NC}          $CPU_MODEL"
    echo -e "${CYAN}Ядра:${NC}         $CPU_CORES cores"
    echo -e "${CYAN}RAM:${NC}          $TOTAL_RAM"
    echo -e "${CYAN}Диск:${NC}         $DISK_SIZE"
    echo -e "${CYAN}IP:${NC}           $IP_ADDR"
    echo -e "${CYAN}Uptime:${NC}       $UPTIME"
    
    # Показываем информацию о хостинге, если она доступна
    if [ "$ORGANIZATION" != "N/A" ] && [ -n "$ORGANIZATION" ]; then
        echo -e "${CYAN}Organization:${NC} $ORGANIZATION"
        echo -e "${CYAN}Location:${NC}     $LOCATION / $COUNTRY"
        if [ "$REGION" != "N/A" ] && [ -n "$REGION" ]; then
            echo -e "${CYAN}Region:${NC}       $REGION"
        fi
    fi
    echo ""
    
    # Заголовок с временем (фиксированная ширина без printf)
    current_time=$(date '+%H:%M:%S')
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      Мониторинг в реальном времени - ${current_time}           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # CPU - используем mpstat если доступен, иначе top с одной итерацией
    if command -v mpstat &> /dev/null; then
        cpu_current=$(mpstat 1 1 | awk '/Average/ {print 100 - $NF}')
    else
        # Используем top с одной итерацией для скорости
        cpu_line=$(top -bn1 | grep "Cpu(s)" | head -1)
        # Берем %us (user) + %sy (system) + %ni (nice) и убираем % полностью
        cpu_us=$(echo "$cpu_line" | awk '{print $2}' | tr -d '%' | sed 's/us,//' | sed 's/,//')
        cpu_sy=$(echo "$cpu_line" | awk '{print $4}' | tr -d '%' | sed 's/sy,//' | sed 's/,//')
        cpu_ni=$(echo "$cpu_line" | awk '{print $6}' | tr -d '%' | sed 's/ni,//' | sed 's/,//')
        
        # Убедимся что это числа, иначе 0
        [ -z "$cpu_us" ] && cpu_us=0
        [ -z "$cpu_sy" ] && cpu_sy=0
        [ -z "$cpu_ni" ] && cpu_ni=0
        
        cpu_current=$(awk "BEGIN {printf \"%.1f\", $cpu_us + $cpu_sy + $cpu_ni}")
    fi
    
    # Добавляем в историю и вычисляем среднее
    cpu_history[$history_index]=$cpu_current
    
    # Считаем среднее за последние измерения
    cpu_sum=0
    for val in "${cpu_history[@]}"; do
        cpu_sum=$(awk "BEGIN {printf \"%.1f\", $cpu_sum + $val}")
    done
    cpu_usage=$(awk "BEGIN {printf \"%.1f\", $cpu_sum / $history_size}")
    
    # Определяем цвет в зависимости от загрузки
    cpu_color=$(get_load_color $cpu_usage)
    
    echo -e "${GREEN}▶ CPU загрузка:${NC}"
    printf "  ${cpu_color}%.1f%%${NC}\n" "$cpu_usage"
    
    # Прогресс-бар для CPU с цветом
    cpu_int=${cpu_usage%.*}
    bar_length=$((cpu_int / 5))
    printf "  ["
    for ((i=0; i<20; i++)); do
        if [ $i -lt $bar_length ]; then
            printf "${cpu_color}█${NC}"
        else
            printf "░"
        fi
    done
    printf "]\n"
    echo ""
    
    # RAM
    mem_info=$(free -m | awk 'NR==2{printf "%.1f %.1f %.1f", $3,$2,($3/$2)*100}')
    read mem_used mem_total mem_percent <<< $mem_info
    
    # Определяем цвет в зависимости от загрузки
    mem_color=$(get_load_color $mem_percent)
    
    echo -e "${GREEN}▶ RAM использование:${NC}"
    printf "  ${mem_color}%.0fMB / %.0fMB (%.1f%%)${NC}\n" "$mem_used" "$mem_total" "$mem_percent"
    
    # Прогресс-бар для RAM с цветом
    mem_int=${mem_percent%.*}
    bar_length=$((mem_int / 5))
    printf "  ["
    for ((i=0; i<20; i++)); do
        if [ $i -lt $bar_length ]; then
            printf "${mem_color}█${NC}"
        else
            printf "░"
        fi
    done
    printf "]\n"
    echo ""
    
    # Сетевой трафик
    read rx_curr tx_curr <<< $(get_network_stats)
    
    rx_diff=$((rx_curr - rx_prev))
    tx_diff=$((tx_curr - tx_prev))
    
    # Защита от отрицательных значений (при переполнении счетчика)
    if [ $rx_diff -lt 0 ]; then rx_diff=0; fi
    if [ $tx_diff -lt 0 ]; then tx_diff=0; fi
    
    # Добавляем в историю для сглаживания
    rx_history[$history_index]=$rx_diff
    tx_history[$history_index]=$tx_diff
    
    # Вычисляем среднее за последние измерения
    rx_sum=0
    tx_sum=0
    for i in "${!rx_history[@]}"; do
        rx_sum=$((rx_sum + ${rx_history[$i]}))
        tx_sum=$((tx_sum + ${tx_history[$i]}))
    done
    rx_avg=$((rx_sum / history_size))
    tx_avg=$((tx_sum / history_size))
    
    rx_speed=$(format_bytes $rx_avg)
    tx_speed=$(format_bytes $tx_avg)
    
    # Получаем имя интерфейса для отображения
    net_interface=$(get_network_interface)
    
    # Получаем анимированный спиннер
    spinner="${spinner_frames[$spinner_index]}"
    
    echo -e "${GREEN}▶ Сетевой трафик ($net_interface): ${CYAN}${spinner}${NC}"
    printf "  ${YELLOW}↓${NC} Входящий:  %-15s\n" "$rx_speed"
    printf "  ${RED}↑${NC} Исходящий: %-15s\n" "$tx_speed"
    echo ""
    
    # Дисковое пространство
    disk_info=$(df -h / | awk 'NR==2{printf "%s %s %s", $3,$2,$5}')
    read disk_used disk_total disk_percent <<< $disk_info
    echo -e "${GREEN}▶ Диск (/):${NC}"
    printf "  %s / %s (%s)\n" "$disk_used" "$disk_total" "$disk_percent"
    echo ""
    
    # Сетевые соединения (обновляем раз в 5 секунд)
    if [ $cache_counter -eq 0 ]; then
        read cached_tcp_conn cached_udp_conn <<< $(get_network_connections)
    fi
    echo -e "${GREEN}▶ Сетевые соединения:${NC}"
    printf "  TCP: ${CYAN}%s${NC}  |  UDP: ${CYAN}%s${NC}\n" "$cached_tcp_conn" "$cached_udp_conn"
    echo ""
    
    # Топ процессов (обновляем раз в 5 секунд)
    if [ $cache_counter -eq 0 ]; then
        cached_top_cpu=$(ps aux --sort=-%cpu | awk 'NR>1{printf "  %-25s %5s%%\n", substr($11,1,25), $3}' | head -3)
        cached_top_mem=$(ps aux --sort=-%mem | awk 'NR>1{printf "  %-25s %5s%%\n", substr($11,1,25), $4}' | head -3)
    fi
    
    # Топ процессов по CPU
    echo -e "${GREEN}▶ Топ-3 процесса по CPU:${NC}"
    echo "$cached_top_cpu"
    echo ""
    
    # Топ процессов по RAM
    echo -e "${GREEN}▶ Топ-3 процесса по RAM:${NC}"
    echo "$cached_top_mem"
    echo ""
    echo -e "${CYAN}Ctrl+C для выхода | Для фона: tmux new -s monitor${NC}"
    
    # Очищаем остаток экрана (если что-то осталось от предыдущего вывода)
    tput ed
    
    # Обновляем предыдущие значения
    rx_prev=$rx_curr
    tx_prev=$tx_curr
    
    # Циклически обновляем индекс истории
    history_index=$(( (history_index + 1) % history_size ))
    
    # Обновляем индекс спиннера
    spinner_index=$(( (spinner_index + 1) % 10 ))
    
    # Обновляем счетчик кэша (0-4, потом снова 0)
    cache_counter=$(( (cache_counter + 1) % cache_interval ))
    
    # Пауза 1 секунда
    sleep 1
done
