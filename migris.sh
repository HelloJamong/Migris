#!/bin/bash

#==============================================================================
# Migris - Database Migration Script
# 운영 중인 시스템의 데이터베이스를 안전하게 마이그레이션
#==============================================================================

set -e  # 에러 발생 시 스크립트 중단

#==============================================================================
# 색상 정의
#==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#==============================================================================
# 전역 변수
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/backup/db-backup"
QUERY_FILE="${SCRIPT_DIR}/all_query.txt"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${SCRIPT_DIR}/migration_result_${TIMESTAMP}.log"
BACKUP_FILE="${BACKUP_DIR}/before_migration_${TIMESTAMP}.sql"

# 데이터베이스 연결 정보
DB_HOST=""
DB_PORT="3306"
DB_USER=""
DB_PASSWORD=""
DB_NAME=""

# 통계 변수
TOTAL_QUERIES=0
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

#==============================================================================
# 로그 함수
#==============================================================================
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            echo "[$timestamp] [SUCCESS] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        SKIP)
            echo -e "${YELLOW}[SKIP]${NC} $message"
            echo "[$timestamp] [SKIP] $message" >> "$LOG_FILE"
            ;;
    esac
}

#==============================================================================
# 사용법 출력
#==============================================================================
usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
    -h, --host HOST        데이터베이스 호스트 (기본값: localhost)
    -P, --port PORT        데이터베이스 포트 (기본값: 3306)
    -u, --user USER        데이터베이스 사용자 (필수)
    -p, --password PASS    데이터베이스 비밀번호 (필수)
    -d, --database DB      데이터베이스 이름 (필수)
    --help                 도움말 출력

예시:
    $0 -u root -p --d database_name

EOF
    exit 1
}

#==============================================================================
# 인자 파싱
#==============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                DB_HOST="$2"
                shift 2
                ;;
            -P|--port)
                DB_PORT="$2"
                shift 2
                ;;
            -u|--user)
                DB_USER="$2"
                shift 2
                ;;
            -p|--password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            -d|--database)
                DB_NAME="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                echo "알 수 없는 옵션: $1"
                usage
                ;;
        esac
    done

    # 필수 인자 확인
    if [[ -z "$DB_USER" ]] || [[ -z "$DB_PASSWORD" ]] || [[ -z "$DB_NAME" ]]; then
        echo -e "${RED}Error: 필수 인자가 누락되었습니다.${NC}"
        usage
    fi

    # 기본값 설정
    if [[ -z "$DB_HOST" ]]; then
        DB_HOST="localhost"
    fi
}

#==============================================================================
# 디렉토리 확인 및 생성
#==============================================================================
setup_directories() {
    log INFO "디렉토리 구조 확인 중..."

    # 백업 디렉토리 확인 및 생성 (루트 권한 필요할 수 있음)
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log INFO "백업 디렉토리가 존재하지 않습니다. 생성 시도: $BACKUP_DIR"

        if sudo mkdir -p "$BACKUP_DIR" 2>/dev/null; then
            sudo chmod 755 "$BACKUP_DIR"
            log SUCCESS "백업 디렉토리 생성 완료: $BACKUP_DIR"
        else
            log ERROR "백업 디렉토리 생성 실패: $BACKUP_DIR (sudo 권한 필요)"
            exit 1
        fi
    else
        log INFO "백업 디렉토리 확인: $BACKUP_DIR"
    fi

    # 쿼리 파일 확인
    if [[ ! -f "$QUERY_FILE" ]]; then
        log ERROR "쿼리 파일을 찾을 수 없습니다: $QUERY_FILE"
        exit 1
    fi

    log INFO "쿼리 파일 확인: $QUERY_FILE"
}

#==============================================================================
# 데이터베이스 연결 테스트
#==============================================================================
test_db_connection() {
    log INFO "데이터베이스 연결 테스트 중..."

    if mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" -e "USE $DB_NAME;" 2>/dev/null; then
        log SUCCESS "데이터베이스 연결 성공"
        return 0
    else
        log ERROR "데이터베이스 연결 실패"
        exit 1
    fi
}

#==============================================================================
# 데이터베이스 백업
#==============================================================================
backup_database() {
    log INFO "데이터베이스 백업 시작..."
    log INFO "백업 파일: $BACKUP_FILE"

    # 임시 파일에 백업 후 이동 (권한 문제 해결)
    local temp_backup="/tmp/migration_backup_${TIMESTAMP}.sql"

    if mysqldump -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        "$DB_NAME" > "$temp_backup" 2>/dev/null; then

        # 백업 파일을 목적지로 이동
        if sudo mv "$temp_backup" "$BACKUP_FILE" 2>/dev/null; then
            sudo chmod 644 "$BACKUP_FILE"
            local backup_size=$(sudo du -h "$BACKUP_FILE" | cut -f1)
            log SUCCESS "데이터베이스 백업 완료 (크기: $backup_size)"
            return 0
        else
            log ERROR "백업 파일 이동 실패: $BACKUP_FILE"
            rm -f "$temp_backup"
            exit 1
        fi
    else
        log ERROR "데이터베이스 백업 실패"
        rm -f "$temp_backup"
        exit 1
    fi
}

#==============================================================================
# MySQL 쿼리 실행
#==============================================================================
execute_mysql() {
    local query="$1"
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$query" 2>&1
}

#==============================================================================
# 쿼리 타입 감지
#==============================================================================
get_query_type() {
    local query="$1"
    local query_upper=$(echo "$query" | tr '[:lower:]' '[:upper:]' | xargs)

    if [[ $query_upper == INSERT* ]]; then
        echo "INSERT"
    elif [[ $query_upper == CREATE\ TABLE* ]]; then
        echo "CREATE_TABLE"
    elif [[ $query_upper == CREATE\ *VIEW* ]]; then
        echo "CREATE_VIEW"
    elif [[ $query_upper == CREATE\ *INDEX* ]] || [[ $query_upper == CREATE\ UNIQUE\ INDEX* ]]; then
        echo "CREATE_INDEX"
    elif [[ $query_upper == ALTER\ TABLE* ]]; then
        echo "ALTER_TABLE"
    elif [[ $query_upper == UPDATE* ]]; then
        echo "UPDATE"
    elif [[ $query_upper == DROP* ]]; then
        echo "DROP"
    else
        echo "OTHER"
    fi
}

#==============================================================================
# 테이블 존재 확인
#==============================================================================
table_exists() {
    local table_name="$1"
    local result=$(execute_mysql "SHOW TABLES LIKE '$table_name';")
    [[ -n "$result" ]]
}

#==============================================================================
# 컬럼 존재 확인
#==============================================================================
column_exists() {
    local table_name="$1"
    local column_name="$2"
    local result=$(execute_mysql "SHOW COLUMNS FROM \`$table_name\` LIKE '$column_name';")
    [[ -n "$result" ]]
}

#==============================================================================
# 인덱스 존재 확인
#==============================================================================
index_exists() {
    local table_name="$1"
    local index_name="$2"
    local result=$(execute_mysql "SHOW INDEX FROM \`$table_name\` WHERE Key_name = '$index_name';")
    [[ -n "$result" ]]
}

#==============================================================================
# VIEW 존재 확인
#==============================================================================
view_exists() {
    local view_name="$1"
    local result=$(execute_mysql "SHOW FULL TABLES WHERE Table_type = 'VIEW' AND Tables_in_$DB_NAME = '$view_name';")
    [[ -n "$result" ]]
}

#==============================================================================
# 중복 레코드 확인 (INSERT 쿼리용)
#==============================================================================
record_exists() {
    local query="$1"

    # INSERT 쿼리에서 테이블명과 값 추출 (간단한 패턴)
    if [[ $query =~ insert[[:space:]]+into[[:space:]]+([a-zA-Z_]+)[[:space:]]+values[[:space:]]*\(([^)]+)\) ]]; then
        local table="${BASH_REMATCH[1]}"
        local values="${BASH_REMATCH[2]}"

        # 첫 번째 값을 기준으로 확인 (일반적으로 PK)
        local first_value=$(echo "$values" | cut -d',' -f1 | xargs)

        # ref_code 테이블의 경우 특별 처리
        if [[ $table == "ref_code" ]]; then
            # ref_code_group과 ref_code 값 추출
            local ref_code_group=$(echo "$values" | cut -d',' -f1 | xargs | sed "s/'//g")
            local ref_code=$(echo "$values" | cut -d',' -f2 | xargs | sed "s/'//g")
            local result=$(execute_mysql "SELECT COUNT(*) as cnt FROM $table WHERE ref_code_group='$ref_code_group' AND ref_code='$ref_code';" | tail -n1)
            [[ "$result" -gt 0 ]]
        else
            return 1  # 다른 테이블은 INSERT 시도
        fi
    else
        return 1
    fi
}

#==============================================================================
# 쿼리 실행 전 존재 여부 확인
#==============================================================================
should_skip_query() {
    local query="$1"
    local query_type="$2"

    case $query_type in
        CREATE_TABLE)
            # 테이블명 추출
            if [[ $query =~ CREATE[[:space:]]+TABLE[[:space:]]+\`?([a-zA-Z_]+)\`? ]]; then
                local table_name="${BASH_REMATCH[1]}"
                if table_exists "$table_name"; then
                    log SKIP "테이블이 이미 존재함: $table_name"
                    return 0
                fi
            fi
            ;;
        CREATE_VIEW)
            # VIEW명 추출
            if [[ $query =~ CREATE[[:space:]]+(OR[[:space:]]+REPLACE[[:space:]]+)?VIEW[[:space:]]+([a-zA-Z_]+) ]]; then
                local view_name="${BASH_REMATCH[2]}"
                if view_exists "$view_name"; then
                    log SKIP "VIEW가 이미 존재함: $view_name (OR REPLACE로 재생성)"
                    return 1  # OR REPLACE는 실행
                fi
            fi
            ;;
        CREATE_INDEX)
            # 인덱스명과 테이블명 추출
            if [[ $query =~ create[[:space:]]+(unique[[:space:]]+)?index[[:space:]]+([a-zA-Z_]+)[[:space:]]+on[[:space:]]+([a-zA-Z_]+) ]]; then
                local index_name="${BASH_REMATCH[2]}"
                local table_name="${BASH_REMATCH[3]}"
                if index_exists "$table_name" "$index_name"; then
                    log SKIP "인덱스가 이미 존재함: $table_name.$index_name"
                    return 0
                fi
            fi
            ;;
        ALTER_TABLE)
            # ADD COLUMN 확인
            if [[ $query =~ ALTER[[:space:]]+TABLE[[:space:]]+[a-zA-Z_.]+[[:space:]]+ADD[[:space:]]+(COLUMN[[:space:]]+)?([a-zA-Z_]+) ]]; then
                local column_name="${BASH_REMATCH[2]}"
                # 테이블명 추출
                if [[ $query =~ ALTER[[:space:]]+TABLE[[:space:]]+([a-zA-Z_.]+)[[:space:]]+ ]]; then
                    local full_table="${BASH_REMATCH[1]}"
                    local table_name=$(echo "$full_table" | awk -F. '{print $NF}')

                    if column_exists "$table_name" "$column_name"; then
                        log SKIP "컬럼이 이미 존재함: $table_name.$column_name"
                        return 0
                    fi
                fi
            fi
            # DROP 작업은 존재 여부 확인 후 처리
            if [[ $query =~ DROP ]]; then
                if [[ $query =~ drop[[:space:]]+column[[:space:]]+([a-zA-Z_]+) ]]; then
                    local column_name="${BASH_REMATCH[1]}"
                    if [[ $query =~ alter[[:space:]]+table[[:space:]]+([a-zA-Z_]+) ]]; then
                        local table_name="${BASH_REMATCH[1]}"
                        if ! column_exists "$table_name" "$column_name"; then
                            log SKIP "컬럼이 존재하지 않음 (이미 삭제됨): $table_name.$column_name"
                            return 0
                        fi
                    fi
                elif [[ $query =~ drop[[:space:]]+key[[:space:]]+([a-zA-Z_]+) ]]; then
                    local key_name="${BASH_REMATCH[1]}"
                    if [[ $query =~ alter[[:space:]]+table[[:space:]]+([a-zA-Z_]+) ]]; then
                        local table_name="${BASH_REMATCH[1]}"
                        if ! index_exists "$table_name" "$key_name"; then
                            log SKIP "인덱스가 존재하지 않음 (이미 삭제됨): $table_name.$key_name"
                            return 0
                        fi
                    fi
                fi
            fi
            ;;
        INSERT)
            if record_exists "$query"; then
                log SKIP "레코드가 이미 존재함"
                return 0
            fi
            ;;
    esac

    return 1  # 실행 필요
}

#==============================================================================
# 쿼리 실행
#==============================================================================
execute_query() {
    local query="$1"
    local query_num="$2"

    # 쿼리 타입 확인
    local query_type=$(get_query_type "$query")

    # 쿼리 로그 (길이 제한)
    local query_preview=$(echo "$query" | head -c 100)
    log INFO "[$query_num/$TOTAL_QUERIES] 쿼리 실행: $query_preview..."

    # 존재 여부 확인
    if should_skip_query "$query" "$query_type"; then
        ((SKIP_COUNT++))
        return 0
    fi

    # 쿼리 실행
    local result=$(execute_mysql "$query" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log SUCCESS "쿼리 실행 성공 [$query_type]"
        ((SUCCESS_COUNT++))
        return 0
    else
        # 에러 메시지 분석
        if [[ $result == *"Duplicate"* ]] || [[ $result == *"already exists"* ]]; then
            log SKIP "이미 존재하는 항목: $result"
            ((SKIP_COUNT++))
            return 0
        else
            log ERROR "쿼리 실행 실패: $result"
            echo "[$query_num] 실패한 쿼리: $query" >> "$LOG_FILE"
            ((FAIL_COUNT++))
            return 1
        fi
    fi
}

#==============================================================================
# 쿼리 파일 파싱 및 실행
#==============================================================================
process_queries() {
    log INFO "쿼리 파일 파싱 시작: $QUERY_FILE"

    local current_query=""
    local query_num=0
    local in_create_table=false
    local in_create_view=false

    # 전체 쿼리 수 계산 (예측)
    TOTAL_QUERIES=$(grep -ci "insert\|create\|alter\|update\|drop" "$QUERY_FILE" || echo "0")
    log INFO "총 예상 쿼리 수: $TOTAL_QUERIES"

    echo "" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    echo "쿼리 실행 시작" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 빈 줄이나 구분선 무시
        if [[ -z "$line" ]] || [[ "$line" =~ ^[=]+$ ]]; then
            continue
        fi

        # 주석 제거
        line=$(echo "$line" | sed 's/--.*$//')

        # 빈 줄 다시 확인
        if [[ -z "$(echo "$line" | xargs)" ]]; then
            continue
        fi

        # CREATE TABLE이나 CREATE VIEW 시작 감지
        if [[ $line =~ ^CREATE[[:space:]]+TABLE ]] || [[ $line =~ ^CREATE[[:space:]]+.*TABLE ]]; then
            in_create_table=true
            current_query="$line"
        elif [[ $line =~ ^create[[:space:]]+OR[[:space:]]+REPLACE[[:space:]]+VIEW ]] || [[ $line =~ ^create[[:space:]]+VIEW ]]; then
            in_create_view=true
            current_query="$line"
        elif [[ $in_create_table == true ]] || [[ $in_create_view == true ]]; then
            # 멀티라인 쿼리 계속
            current_query="$current_query $line"

            # 종료 조건 확인
            if [[ $line =~ \;$ ]]; then
                ((query_num++))
                execute_query "$current_query" "$query_num"
                current_query=""
                in_create_table=false
                in_create_view=false
            fi
        else
            # 세미콜론으로 끝나는 단일 쿼리
            if [[ $line =~ \;$ ]]; then
                ((query_num++))
                execute_query "$line" "$query_num"
            else
                # 멀티라인 쿼리 시작
                current_query="$line"
            fi
        fi

        # 이전에 시작된 쿼리 계속
        if [[ -n "$current_query" ]] && [[ $in_create_table == false ]] && [[ $in_create_view == false ]] && [[ ! $line =~ \;$ ]]; then
            while IFS= read -r next_line; do
                current_query="$current_query $next_line"
                if [[ $next_line =~ \;$ ]]; then
                    ((query_num++))
                    execute_query "$current_query" "$query_num"
                    current_query=""
                    break
                fi
            done
        fi

    done < "$QUERY_FILE"

    # 마지막 쿼리 처리
    if [[ -n "$current_query" ]]; then
        ((query_num++))
        execute_query "$current_query" "$query_num"
    fi

    # 실제 실행된 쿼리 수로 업데이트
    TOTAL_QUERIES=$query_num
}

#==============================================================================
# 결과 요약
#==============================================================================
print_summary() {
    echo ""
    echo "========================================" >> "$LOG_FILE"
    echo "마이그레이션 결과 요약" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    echo "총 쿼리 수: $TOTAL_QUERIES" >> "$LOG_FILE"
    echo "성공: $SUCCESS_COUNT" >> "$LOG_FILE"
    echo "스킵: $SKIP_COUNT (이미 존재)" >> "$LOG_FILE"
    echo "실패: $FAIL_COUNT" >> "$LOG_FILE"
    echo "백업 파일: $BACKUP_FILE" >> "$LOG_FILE"
    echo "로그 파일: $LOG_FILE" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"

    echo ""
    echo "========================================"
    echo -e "${BLUE}마이그레이션 결과 요약${NC}"
    echo "========================================"
    echo -e "총 쿼리 수: ${BLUE}$TOTAL_QUERIES${NC}"
    echo -e "성공: ${GREEN}$SUCCESS_COUNT${NC}"
    echo -e "스킵: ${YELLOW}$SKIP_COUNT${NC} (이미 존재)"
    echo -e "실패: ${RED}$FAIL_COUNT${NC}"
    echo "========================================"
    echo -e "백업 파일: ${GREEN}$BACKUP_FILE${NC}"
    echo -e "로그 파일: ${GREEN}$LOG_FILE${NC}"
    echo "========================================"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo ""
        echo -e "${RED}경고: 일부 쿼리가 실패했습니다.${NC}"
        echo -e "${YELLOW}로그 파일을 확인하고 필요시 백업으로 복구하세요.${NC}"
        echo ""
        echo "복구 명령어:"
        echo "mysql -h$DB_HOST -P$DB_PORT -u$DB_USER -p$DB_PASSWORD $DB_NAME < $BACKUP_FILE"
    else
        echo ""
        echo -e "${GREEN}모든 마이그레이션이 성공적으로 완료되었습니다!${NC}"
    fi
}

#==============================================================================
# 메인 함수
#==============================================================================
main() {
    echo ""
    echo "========================================"
    echo "  Migris - Database Migration Tool"
    echo "========================================"
    echo ""

    # 인자 파싱
    parse_args "$@"

    # 시작 시간 기록
    local start_time=$(date +%s)
    log INFO "마이그레이션 시작: $(date '+%Y-%m-%d %H:%M:%S')"
    log INFO "데이터베이스: $DB_NAME@$DB_HOST:$DB_PORT"

    # 디렉토리 설정
    setup_directories

    # DB 연결 테스트
    test_db_connection

    # 백업 수행
    backup_database

    # 쿼리 실행
    process_queries

    # 종료 시간 기록
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log INFO "마이그레이션 종료: $(date '+%Y-%m-%d %H:%M:%S')"
    log INFO "소요 시간: ${duration}초"

    # 결과 요약
    print_summary

    # 종료 코드 결정
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

#==============================================================================
# 스크립트 실행
#==============================================================================
main "$@"
