# Migris

운영 중인 시스템의 데이터베이스 스키마 및 데이터를 안전하게 자동 마이그레이션하는 도구

## 프로젝트 목표

운영 중인 시스템을 유지한 채로 변경된 데이터베이스 테이블과 레코드를 반영하여 자동 최신화 도구를 제공합니다.

## 시스템 요구사항

### 운영 환경
- **OS**: RockyLinux 8 또는 9
- **Database**: MariaDB 10.11.7 이상

### 필수 패키지
- bash (4.0 이상)
- MariaDB Client
- mysqldump

## 주요 기능

### 1. 단일 스크립트 실행
- 하나의 쉘 스크립트로 모든 마이그레이션 작업을 일괄 처리
- 간단한 명령어로 복잡한 데이터베이스 변경 작업 수행

### 2. 데이터 안전성 보장
- 마이그레이션 전 자동 백업 수행
- 기존 운영 데이터 완전 보존
- 데이터 무결성 검증 기능
- 트랜잭션 기반 안전한 변경 적용

### 3. 자동 복구 시스템
- 문제 발생 시 즉각 롤백 가능
- 백업 데이터를 통한 신속한 복구
- 마이그레이션 로그 자동 기록

## 설치 방법

```bash
# 저장소 클론
git clone <repository-url>
cd Migris

# 쿼리 파일 생성 (샘플 파일 복사)
cp all_query.txt.sample all_query.txt

# all_query.txt 파일을 열어 실제 마이그레이션 쿼리 작성
vim all_query.txt

# migris.sh 상단의 데이터베이스 연결 정보 변수 설정
vim migris.sh

# 실행 권한 부여
chmod +x migris.sh
```

## 사용 방법

### 1. 연결 정보 설정

`migris.sh` 상단의 변수에 데이터베이스 연결 정보를 입력합니다. `DB_PASSWORD`는 반드시 공란으로 유지해야 합니다.

```bash
DB_HOST="localhost"
DB_PORT="3306"
DB_USER="root"
DB_PASSWORD=""          # 공란 유지 — 실행 시 프롬프트로 입력받음
DB_NAME="database_name"
```

### 2. 스크립트 실행

```bash
./migris.sh
```

실행 후 비밀번호 프롬프트가 표시되며, 입력 시 문자는 화면에 표시되지 않습니다.

```
========================================
  Migris - Database Migration Tool
========================================

데이터베이스 비밀번호: ██████
```

## 마이그레이션 쿼리 작성

`all_query.txt` 파일에 마이그레이션 쿼리를 작성합니다.

```sql
-- 테이블 생성 예시
CREATE TABLE `users` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `username` VARCHAR(100) NOT NULL,
    `email` VARCHAR(255) NOT NULL,
    `created_date` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 컬럼 추가 예시
ALTER TABLE users ADD COLUMN status VARCHAR(20) DEFAULT 'ACTIVE' NOT NULL;

-- 인덱스 생성 예시
CREATE INDEX idx_email ON users (email);

-- 데이터 삽입 예시
INSERT INTO config_table (key_name, key_value) VALUES ('app_version', '1.0.0');
```

## 안전장치

### 자동 백업
- 마이그레이션 실행 전 전체 데이터베이스 자동 백업
- 백업 파일은 타임스탬프와 함께 저장

### 검증 절차
- 마이그레이션 파일 문법 검증
- 데이터베이스 연결 상태 확인
- 충분한 디스크 공간 확인

### 트랜잭션 관리
- 가능한 모든 작업을 트랜잭션으로 처리
- 오류 발생 시 자동 롤백

## 디렉토리 구조

```
Migris/
├── migris.sh                      # 메인 스크립트
├── all_query.txt.sample           # 마이그레이션 쿼리 샘플 파일
├── all_query.txt                  # 마이그레이션 쿼리 파일 (git 추적 제외)
├── .gitignore                     # Git 제외 파일 목록
├── README.md                      # 프로젝트 문서
├── USAGE_EXAMPLE.md               # 사용 예시 문서
└── migration_result_*.log         # 실행 로그 파일 (자동 생성, git 추적 제외)

/backup/db-backup/                 # 백업 파일 저장 디렉토리 (시스템 경로)
└── before_migration_*.sql         # 백업 파일 (자동 생성)
```

## 로그 및 모니터링

모든 마이그레이션 작업은 자동으로 로그에 기록됩니다.

```bash
# 로그 확인
tail -f migration_result_YYYYMMDD_HHMMSS.log
```

## 문제 해결

### 변수 미설정 오류 시

`migris.sh` 상단의 `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_NAME` 중 하나라도 공란이면 실행 시에 해당 변수명과 함께 오류가 출력됩니다. 해당 변수에 값을 채워두세요.

### 마이그레이션 실패 시

1. 로그 파일 확인
2. 백업 디렉토리에서 수동 복구 가능

### 백업 복구

```bash
# 백업 파일 목록 확인
ls -la /backup/db-backup/

# 수동 복구
mysql -h localhost -u root -p database_name < /backup/db-backup/before_migration_YYYYMMDD_HHMMSS.sql
```

## 주의사항

- 프로덕션 환경 적용 전 반드시 테스트 환경에서 검증
- 충분한 디스크 공간 확보 (데이터베이스 크기의 2배 이상 권장)
- 마이그레이션 수행 전 수동 백업 권장
- 대용량 데이터베이스의 경우 작업 시간 고려
- `migris.sh` 상단의 연결 정보 변수(`DB_HOST` 등)에는 실제 서비스 정보가 포함될 수 있으므로 주의하여 관리하세요
- `all_query.txt` 파일에는 실제 서비스 DB 정보가 포함되므로 Git에 커밋하지 않도록 주의

## 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

누구나 자유롭게 사용, 수정, 배포할 수 있습니다.

---

<div align="center">

**본 프로젝트는 [Claude Code](https://claude.ai/code)를 활용하여 개발되었습니다.**

</div>


