# Migris 사용 예시

## 스크립트 실행 전 준비사항

### 1. 백업 디렉토리 권한 확인
스크립트는 `/backup/db-backup` 디렉토리를 자동으로 생성합니다.
루트 디렉토리에 생성되므로 sudo 권한이 필요할 수 있습니다.

### 2. MariaDB 접속 정보 준비
- 호스트 주소
- 포트 (기본값: 3306)
- 사용자 이름
- 비밀번호
- 데이터베이스 이름

## 실행 방법

### 기본 사용법

```bash
# 로컬 데이터베이스에 연결
./migris.sh -u root -p your_password -d database_name

# 호스트 지정
./migris.sh -h localhost -u root -p your_password -d database_name

# 원격 데이터베이스에 연결
./migris.sh -h 192.168.1.100 -P 3306 -u dbuser -p dbpass -d database_name
```

### sudo 권한 없이 실행하는 경우

백업 디렉토리를 미리 생성해두세요:

```bash
# 관리자가 미리 디렉토리 생성
sudo mkdir -p /backup/db-backup
sudo chmod 777 /backup/db-backup  # 또는 특정 사용자에게 권한 부여
```

## 실행 과정

스크립트는 다음 순서로 실행됩니다:

1. **디렉토리 확인**
   - `/backup/db-backup` 디렉토리 존재 확인
   - 없으면 자동 생성 (sudo 권한 필요)
   - 쿼리 파일 확인

2. **데이터베이스 연결 테스트**
   - 제공된 접속 정보로 데이터베이스 연결 확인

3. **백업 수행**
   - 전체 데이터베이스를 `/backup/db-backup/before_migration_YYYYMMDD_HHMMSS.sql` 파일로 백업

4. **쿼리 실행**
   - 스크립트와 동일한 경로의 `all_query.txt` 파일의 쿼리를 순차적으로 실행
   - 각 쿼리 실행 전 중복 여부 확인
   - 이미 존재하는 항목은 스킵

5. **결과 출력**
   - 실행 결과 요약 출력
   - 로그 파일 생성: `migration_result_YYYYMMDD_HHMMSS.log`

## 출력 예시

```
========================================
  Migris - Database Migration Tool
========================================

[INFO] 마이그레이션 시작: 2026-01-29 15:00:00
[INFO] 데이터베이스: database@localhost:3306
[INFO] 디렉토리 구조 확인 중...
[INFO] 백업 디렉토리 확인: /backup/db-backup
[INFO] 쿼리 파일 확인: /home/user/all_query.txt
[INFO] 데이터베이스 연결 테스트 중...
[SUCCESS] 데이터베이스 연결 성공
[INFO] 데이터베이스 백업 시작...
[INFO] 백업 파일: /backup/db-backup/before_migration_20260129_150000.sql
[SUCCESS] 데이터베이스 백업 완료 (크기: 125M)
[INFO] 쿼리 파일 파싱 시작: /home/user/all_query.txt
[INFO] 총 예상 쿼리 수: 50

[INFO] [1/50] 쿼리 실행: CREATE TABLE `users` (id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR...
[SUCCESS] 쿼리 실행 성공 [CREATE_TABLE]

[INFO] [2/50] 쿼리 실행: ALTER TABLE users ADD COLUMN status VARCHAR(20) DEFAULT 'ACTIVE'...
[SKIP] 컬럼이 이미 존재함: users.status

...

========================================
마이그레이션 결과 요약
========================================
총 쿼리 수: 50
성공: 35
스킵: 15 (이미 존재)
실패: 0
========================================
백업 파일: /backup/db-backup/before_migration_20260129_150000.sql
로그 파일: /home/user/migration_result_20260129_150000.log
========================================

모든 마이그레이션이 성공적으로 완료되었습니다!
```

## 백업 파일 위치

모든 백업 파일은 `/backup/db-backup/` 디렉토리에 저장됩니다:

```bash
/backup/db-backup/
├── before_migration_20260129_150000.sql
├── before_migration_20260129_160000.sql
└── before_migration_20260129_170000.sql
```

## 복구 방법

마이그레이션 실패 시 백업 파일로 복구할 수 있습니다:

```bash
# 백업 파일 목록 확인
ls -lh /backup/db-backup/

# 특정 백업 파일로 복구
mysql -h localhost -u root -p database_name < /backup/db-backup/before_migration_20260129_150000.sql
```

## 로그 파일

로그 파일은 스크립트가 실행된 경로에 생성됩니다:

```bash
# 로그 파일 확인
cat migration_result_20260129_150000.log

# 실패한 쿼리만 확인
grep "ERROR" migration_result_20260129_150000.log

# 스킵된 항목 확인
grep "SKIP" migration_result_20260129_150000.log
```

## 주의사항

1. **권한**: `/backup` 디렉토리 생성 시 sudo 권한이 필요할 수 있습니다.
2. **디스크 공간**: 백업 파일 크기를 고려하여 충분한 디스크 공간을 확보하세요.
3. **네트워크**: 원격 데이터베이스 연결 시 방화벽 설정을 확인하세요.
4. **테스트**: 프로덕션 환경 적용 전 반드시 테스트 환경에서 먼저 실행하세요.

## 문제 해결

### "백업 디렉토리 생성 실패" 오류

```bash
# 수동으로 디렉토리 생성
sudo mkdir -p /backup/db-backup
sudo chown $USER:$USER /backup/db-backup
```

### "쿼리 파일을 찾을 수 없습니다" 오류

```bash
# 쿼리 파일 경로 확인
ls -l all_query.txt

# 스크립트와 동일한 경로에 all_query.txt 파일이 있어야 함
```

### "데이터베이스 연결 실패" 오류

```bash
# MariaDB 연결 테스트
mysql -h localhost -u root -p -e "SHOW DATABASES;"
```
