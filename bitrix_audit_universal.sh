#!/bin/bash

# =============================================================================
# УНИВЕРСАЛЬНЫЙ АУДИТ ПОРТАЛА БИТРИКС
# Единый скрипт для комплексного тестирования производительности и безопасности
# =============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация (можно переопределить через параметры)
DOMAIN="${BITRIX_DOMAIN:-}"
LOGIN_URL=""
PORTAL_URL=""
REPORT_FILE=""
TEMP_DIR="/tmp/bitrix_audit_$$"
SERVER_LOCATION="${SERVER_LOCATION:-Не указано}"

# Функция логирования
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$REPORT_FILE"
}

log_error() {
    echo -e "${RED}[ОШИБКА]${NC} $1" | tee -a "$REPORT_FILE"
}

log_warning() {
    echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1" | tee -a "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1" | tee -a "$REPORT_FILE"
}

# Функция инициализации
init_config() {
    if [ -z "$DOMAIN" ]; then
        echo -e "${YELLOW}Введите домен для тестирования:${NC}"
        read -p "Домен (например, example.com): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            log_error "Домен не указан. Завершение работы."
            exit 1
        fi
    fi
    
    # Удаляем протокол если указан
    DOMAIN=$(echo "$DOMAIN" | sed 's|^https\?://||' | sed 's|/$||')
    
    LOGIN_URL="https://${DOMAIN}/bitrix/admin/"
    PORTAL_URL="https://${DOMAIN}/"
    REPORT_FILE="bitrix_audit_${DOMAIN}_$(date +%Y%m%d_%H%M%S).txt"
    
    # Создаем временную директорию
    mkdir -p "$TEMP_DIR"
    
    log "Инициализация конфигурации для домена: $DOMAIN"
}

# Функция проверки зависимостей
check_dependencies() {
    log "Проверка зависимостей..."
    
    local deps=("curl" "openssl" "dig" "ping" "bc")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Отсутствуют зависимости: ${missing[*]}"
        log "Установите их с помощью:"
        log "  Ubuntu/Debian: sudo apt-get install ${missing[*]}"
        log "  CentOS/RHEL: sudo yum install ${missing[*]}"
        log "  macOS: brew install ${missing[*]}"
        exit 1
    fi
    
    log_success "Все зависимости установлены"
}

# Функция тестирования DNS
test_dns() {
    log "=== ТЕСТИРОВАНИЕ DNS ==="
    
    # Проверка разрешения DNS
    local dns_time=$(dig +short +time=5 +tries=1 "$DOMAIN" | head -1)
    if [ -n "$dns_time" ]; then
        log_success "DNS разрешается корректно"
        echo "IP адрес: $dns_time" >> "$REPORT_FILE"
    else
        log_error "Проблемы с DNS разрешением"
    fi
    
    # Проверка времени ответа DNS
    local dns_response_time=$(dig +stats "$DOMAIN" | grep "Query time" | awk '{print $4}')
    if [ -n "$dns_response_time" ]; then
        echo "Время ответа DNS: ${dns_response_time}ms" >> "$REPORT_FILE"
        if [ "$dns_response_time" -gt 1000 ]; then
            log_warning "Медленный ответ DNS: ${dns_response_time}ms"
        else
            log_success "DNS ответ быстрый: ${dns_response_time}ms"
        fi
    fi
}

# Функция тестирования SSL
test_ssl() {
    log "=== ТЕСТИРОВАНИЕ SSL СЕРТИФИКАТА ==="
    
    # Получение информации о сертификате
    local cert_info=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    
    if [ -n "$cert_info" ]; then
        log_success "SSL сертификат найден"
        
        # Извлечение даты истечения
        local not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
        local expiry_date=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null)
        local current_date=$(date +%s)
        local days_until_expiry=$(( (expiry_date - current_date) / 86400 ))
        
        echo "Сертификат действителен до: $not_after" >> "$REPORT_FILE"
        echo "Дней до истечения: $days_until_expiry" >> "$REPORT_FILE"
        
        if [ "$days_until_expiry" -lt 30 ]; then
            log_error "SSL сертификат истекает через $days_until_expiry дней!"
        elif [ "$days_until_expiry" -lt 90 ]; then
            log_warning "SSL сертификат истекает через $days_until_expiry дней"
        else
            log_success "SSL сертификат действителен еще $days_until_expiry дней"
        fi
    else
        log_error "Не удалось получить информацию о SSL сертификате"
    fi
}

# Функция тестирования ping
test_ping() {
    log "=== ТЕСТ PING ДО СЕРВЕРА ==="
    
    local host_ip=$(dig +short "$DOMAIN" | head -1)
    if [ -n "$host_ip" ]; then
        log "IP адрес сервера: $host_ip"
        echo "IP адрес сервера: $host_ip" >> "$REPORT_FILE"
        
        # Выполняем ping тест
        log "Выполнение ping теста (5 пакетов)..."
        local ping_result=$(ping -c 5 "$host_ip" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            # Извлекаем статистику
            local avg_time=$(echo "$ping_result" | grep "avg" | awk -F'/' '{print $5}')
            local min_time=$(echo "$ping_result" | grep "min" | awk -F'/' '{print $4}')
            local max_time=$(echo "$ping_result" | grep "max" | awk -F'/' '{print $6}')
            local packet_loss=$(echo "$ping_result" | grep "packet loss" | awk '{print $6}')
            
            echo "Результаты ping:" >> "$REPORT_FILE"
            echo "  Среднее время: ${avg_time}ms" >> "$REPORT_FILE"
            echo "  Минимальное время: ${min_time}ms" >> "$REPORT_FILE"
            echo "  Максимальное время: ${max_time}ms" >> "$REPORT_FILE"
            echo "  Потеря пакетов: $packet_loss" >> "$REPORT_FILE"
            
            # Анализ результатов
            if (( $(echo "$avg_time > 100" | bc -l 2>/dev/null || echo "0") )); then
                log_error "Высокая задержка ping: ${avg_time}ms"
            elif (( $(echo "$avg_time > 50" | bc -l 2>/dev/null || echo "0") )); then
                log_warning "Умеренная задержка ping: ${avg_time}ms"
            else
                log_success "Низкая задержка ping: ${avg_time}ms"
            fi
            
            if [ "$packet_loss" != "0%" ]; then
                log_warning "Обнаружена потеря пакетов: $packet_loss"
            else
                log_success "Потеря пакетов отсутствует"
            fi
        else
            log_error "Ping тест не удался"
        fi
    else
        log_error "Не удалось определить IP адрес сервера"
    fi
}

# Функция тестирования производительности
test_performance() {
    log "=== ТЕСТИРОВАНИЕ ПРОИЗВОДИТЕЛЬНОСТИ ==="
    
    # Тест времени отклика главной страницы
    log "Тестирование времени загрузки главной страницы..."
    local start_time=$(date +%s.%N)
    local response=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}|%{time_connect}|%{time_starttransfer}" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        --connect-timeout 30 \
        --max-time 60 \
        "$PORTAL_URL")
    local end_time=$(date +%s.%N)
    
    local http_code=$(echo "$response" | cut -d'|' -f1)
    local total_time=$(echo "$response" | cut -d'|' -f2)
    local connect_time=$(echo "$response" | cut -d'|' -f3)
    local start_transfer=$(echo "$response" | cut -d'|' -f4)
    
    echo "HTTP код: $http_code" >> "$REPORT_FILE"
    echo "Общее время: ${total_time}s" >> "$REPORT_FILE"
    echo "Время подключения: ${connect_time}s" >> "$REPORT_FILE"
    echo "Время до первого байта: ${start_transfer}s" >> "$REPORT_FILE"
    
    if [ "$http_code" = "200" ]; then
        log_success "Главная страница доступна (HTTP $http_code)"
    else
        log_error "Проблема с главной страницей (HTTP $http_code)"
    fi
    
    # Анализ времени загрузки
    local total_time_ms=$(echo "$total_time * 1000" | bc -l 2>/dev/null || echo "0")
    if (( $(echo "$total_time > 10.0" | bc -l 2>/dev/null || echo "0") )); then
        log_error "КРИТИЧЕСКИ МЕДЛЕННАЯ ЗАГРУЗКА: ${total_time}s"
    elif (( $(echo "$total_time > 5.0" | bc -l 2>/dev/null || echo "0") )); then
        log_warning "Медленная загрузка: ${total_time}s"
    else
        log_success "Быстрая загрузка: ${total_time}s"
    fi
    
    # Тест административной панели
    log "Тестирование административной панели..."
    local admin_response=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        --connect-timeout 30 \
        --max-time 60 \
        "$LOGIN_URL")
    
    local admin_code=$(echo "$admin_response" | cut -d'|' -f1)
    local admin_time=$(echo "$admin_response" | cut -d'|' -f2)
    
    echo "Админ панель HTTP код: $admin_code" >> "$REPORT_FILE"
    echo "Админ панель время: ${admin_time}s" >> "$REPORT_FILE"
    
    if [ "$admin_code" = "200" ] || [ "$admin_code" = "302" ]; then
        log_success "Административная панель доступна"
    else
        log_error "Проблема с административной панелью (HTTP $admin_code)"
    fi
}

# Функция проверки заголовков HTTP
test_http_headers() {
    log "=== АНАЛИЗ HTTP ЗАГОЛОВКОВ ==="
    
    local headers=$(curl -s -I -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        --connect-timeout 30 \
        "$PORTAL_URL" 2>/dev/null)
    
    echo "HTTP заголовки:" >> "$REPORT_FILE"
    echo "$headers" >> "$REPORT_FILE"
    
    # Проверка важных заголовков
    if echo "$headers" | grep -qi "server:"; then
        local server=$(echo "$headers" | grep -i "server:" | head -1)
        echo "Веб-сервер: $server" >> "$REPORT_FILE"
        log "Веб-сервер: $server"
    fi
    
    if echo "$headers" | grep -qi "x-powered-by:"; then
        local php_version=$(echo "$headers" | grep -i "x-powered-by:" | head -1)
        echo "PHP версия: $php_version" >> "$REPORT_FILE"
        log "PHP версия: $php_version"
    fi
    
    # Проверка кеширования
    if echo "$headers" | grep -qi "cache-control:"; then
        log_success "Настроено кеширование"
    else
        log_warning "Кеширование не настроено"
    fi
    
    # Проверка сжатия
    if echo "$headers" | grep -qi "content-encoding:"; then
        log_success "Включено сжатие"
    else
        log_warning "Сжатие не включено"
    fi
}

# Функция тестирования с авторизацией (если предоставлены данные)
test_authenticated() {
    if [ -n "$BITRIX_LOGIN" ] && [ -n "$BITRIX_PASSWORD" ]; then
        log "=== ТЕСТИРОВАНИЕ С АВТОРИЗАЦИЕЙ ==="
        
        # Создание временного файла для cookies
        local cookie_file="$TEMP_DIR/cookies.txt"
        
        # Получение формы входа
        log "Получение формы входа..."
        local login_page=$(curl -s -c "$cookie_file" --connect-timeout 30 "$LOGIN_URL")
        
        if [ -n "$login_page" ]; then
            log_success "Форма входа получена"
            
            # Попытка авторизации
            log "Попытка авторизации..."
            local auth_start=$(date +%s.%N)
            local auth_response=$(curl -s -b "$cookie_file" -c "$cookie_file" \
                -d "AUTH_FORM=Y" \
                -d "TYPE=AUTH" \
                -d "USER_LOGIN=$BITRIX_LOGIN" \
                -d "USER_PASSWORD=$BITRIX_PASSWORD" \
                -d "USER_REMEMBER=Y" \
                -w "%{http_code}|%{time_total}" \
                -o /dev/null \
                --connect-timeout 30 \
                --max-time 120 \
                "$LOGIN_URL")
            local auth_end=$(date +%s.%N)
            
            local auth_code=$(echo "$auth_response" | cut -d'|' -f1)
            local auth_time=$(echo "$auth_response" | cut -d'|' -f2)
            
            echo "Время авторизации: ${auth_time}s" >> "$REPORT_FILE"
            
            if [ "$auth_code" = "302" ] || [ "$auth_code" = "200" ]; then
                log_success "Авторизация прошла успешно за ${auth_time}s"
                
                # Тест загрузки CRM после авторизации
                log "Тестирование CRM модуля..."
                local crm_response=$(curl -s -b "$cookie_file" \
                    -w "%{http_code}|%{time_total}" \
                    -o /dev/null \
                    --connect-timeout 30 \
                    --max-time 120 \
                    "$PORTAL_URL/crm/lead/list/")
                
                local crm_code=$(echo "$crm_response" | cut -d'|' -f1)
                local crm_time=$(echo "$crm_response" | cut -d'|' -f2)
                
                echo "CRM время загрузки: ${crm_time}s" >> "$REPORT_FILE"
                
                if (( $(echo "$crm_time > 60.0" | bc -l 2>/dev/null || echo "0") )); then
                    log_error "КРИТИЧЕСКАЯ ПРОБЛЕМА: CRM загружается ${crm_time}s"
                elif (( $(echo "$crm_time > 10.0" | bc -l 2>/dev/null || echo "0") )); then
                    log_warning "Медленная загрузка CRM: ${crm_time}s"
                else
                    log_success "CRM загружается быстро: ${crm_time}s"
                fi
            else
                log_error "Ошибка авторизации (HTTP $auth_code)"
            fi
        else
            log_error "Не удалось получить форму входа"
        fi
        
        # Очистка временных файлов
        rm -f "$cookie_file"
    else
        log_warning "Данные для авторизации не предоставлены. Для полного тестирования установите BITRIX_LOGIN и BITRIX_PASSWORD"
    fi
}

# Функция проверки безопасности
test_security() {
    log "=== ПРОВЕРКА БЕЗОПАСНОСТИ ==="
    
    # Проверка на наличие robots.txt
    local robots_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$PORTAL_URL/robots.txt")
    if [ "$robots_response" = "200" ]; then
        log_success "Файл robots.txt найден"
    else
        log_warning "Файл robots.txt отсутствует"
    fi
    
    # Проверка на наличие .htaccess
    local htaccess_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$PORTAL_URL/.htaccess")
    if [ "$htaccess_response" = "200" ]; then
        log_warning "Файл .htaccess доступен публично (потенциальная уязвимость)"
    else
        log_success "Файл .htaccess скрыт"
    fi
    
    # Проверка на наличие backup файлов
    local backup_files=("backup" "backup.sql" "backup.zip" "backup.tar.gz")
    for backup in "${backup_files[@]}"; do
        local backup_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$PORTAL_URL/$backup")
        if [ "$backup_response" = "200" ]; then
            log_error "КРИТИЧЕСКАЯ УЯЗВИМОСТЬ: Файл $backup доступен публично!"
        fi
    done
}

# Функция генерации отчета
generate_report() {
    log "=== ГЕНЕРАЦИЯ ОТЧЕТА ==="
    
    echo "" >> "$REPORT_FILE"
    echo "===========================================" >> "$REPORT_FILE"
    echo "РЕКОМЕНДАЦИИ ПО УЛУЧШЕНИЮ ПРОИЗВОДИТЕЛЬНОСТИ" >> "$REPORT_FILE"
    echo "===========================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "1. КРИТИЧЕСКИЕ ПРОБЛЕМЫ:" >> "$REPORT_FILE"
    echo "   - Время загрузки CRM модуля превышает 60 секунд" >> "$REPORT_FILE"
    echo "   - Географическая задержка между пользователями и сервером" >> "$REPORT_FILE"
    echo "   - Необходимо оптимизировать запросы к базе данных" >> "$REPORT_FILE"
    echo "   - Рекомендуется настроить Memcached для кеширования" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "2. ОПТИМИЗАЦИЯ СЕРВЕРА:" >> "$REPORT_FILE"
    echo "   - Увеличить объем RAM до 16-32GB" >> "$REPORT_FILE"
    echo "   - Настроить SSD диски для базы данных" >> "$REPORT_FILE"
    echo "   - Оптимизировать настройки MySQL" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "3. ОБНОВЛЕНИЯ ПО:" >> "$REPORT_FILE"
    echo "   - Обновить Bitrix Framework до актуальной версии" >> "$REPORT_FILE"
    echo "   - Обновить PHP до версии 8.3" >> "$REPORT_FILE"
    echo "   - Обновить MySQL до последней стабильной версии" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "4. НАСТРОЙКА КЕШИРОВАНИЯ:" >> "$REPORT_FILE"
    echo "   - Включить Memcached для кеширования" >> "$REPORT_FILE"
    echo "   - Настроить кеширование на уровне веб-сервера" >> "$REPORT_FILE"
    echo "   - Использовать CDN для статических ресурсов" >> "$REPORT_FILE"
    echo "   - Настроить агрессивное кеширование для компенсации географической задержки" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    echo "5. МОНИТОРИНГ:" >> "$REPORT_FILE"
    echo "   - Настроить регулярное резервное копирование" >> "$REPORT_FILE"
    echo "   - Включить мониторинг производительности" >> "$REPORT_FILE"
    echo "   - Настроить алерты при превышении времени загрузки" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    log_success "Отчет сохранен в файл: $REPORT_FILE"
}

# Функция очистки
cleanup() {
    log "Очистка временных файлов..."
    rm -rf "$TEMP_DIR"
}

# Основная функция
main() {
    echo "==========================================="
    echo "УНИВЕРСАЛЬНЫЙ АУДИТ ПОРТАЛА БИТРИКС"
    echo "==========================================="
    echo ""
    
    # Инициализация
    init_config
    
    echo "Домен: $DOMAIN"
    echo "Дата: $(date)"
    echo "==========================================="
    echo ""
    
    # Инициализация отчета
    echo "АУДИТ ПОРТАЛА БИТРИКС: $DOMAIN" > "$REPORT_FILE"
    echo "Дата проведения: $(date)" >> "$REPORT_FILE"
    echo "Расположение сервера: $SERVER_LOCATION" >> "$REPORT_FILE"
    echo "Тестирование из: $(curl -s ipinfo.io/country 2>/dev/null || echo "Не определено")" >> "$REPORT_FILE"
    echo "===========================================" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Проверка зависимостей
    check_dependencies
    
    # Запуск тестов
    test_dns
    test_ssl
    test_ping
    test_http_headers
    test_performance
    test_authenticated
    test_security
    
    # Генерация отчета
    generate_report
    
    # Очистка
    cleanup
    
    echo ""
    echo "==========================================="
    log_success "АУДИТ ЗАВЕРШЕН"
    echo "Отчет сохранен в: $REPORT_FILE"
    echo "==========================================="
}

# Обработка сигналов для корректной очистки
trap cleanup EXIT INT TERM

# Проверка аргументов командной строки
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Использование: $0 [OPTIONS]"
    echo ""
    echo "Опции:"
    echo "  --domain DOMAIN   Домен для тестирования"
    echo "  --login LOGIN     Логин для авторизации в Битрикс"
    echo "  --password PASS   Пароль для авторизации в Битрикс"
    echo "  --location LOC    Расположение сервера"
    echo "  --help, -h        Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0"
    echo "  $0 --domain example.com"
    echo "  $0 --domain example.com --login admin --password mypassword"
    echo "  $0 --domain example.com --location \"Москва, TimeWeb\""
    echo ""
    echo "Переменные окружения:"
    echo "  BITRIX_DOMAIN     Домен для тестирования"
    echo "  BITRIX_LOGIN      Логин для авторизации"
    echo "  BITRIX_PASSWORD   Пароль для авторизации"
    echo "  SERVER_LOCATION   Расположение сервера"
    echo ""
    echo "Быстрый запуск:"
    echo "  wget -O bitrix_audit.sh https://raw.githubusercontent.com/your-repo/bitrix_audit.sh"
    echo "  chmod +x bitrix_audit.sh"
    echo "  ./bitrix_audit.sh --domain your-domain.com"
    exit 0
fi

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --login)
            BITRIX_LOGIN="$2"
            shift 2
            ;;
        --password)
            BITRIX_PASSWORD="$2"
            shift 2
            ;;
        --location)
            SERVER_LOCATION="$2"
            shift 2
            ;;
        *)
            echo "Неизвестный параметр: $1"
            echo "Используйте --help для справки"
            exit 1
            ;;
    esac
done

# Запуск основной функции
main
