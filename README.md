# 로컬 LLM 비교 실험

사내 규정 챗봇 온프레미스 배포를 위한 로컬 LLM 비교 실험 환경입니다.  
Ollama 기반으로 로컬 및 AWS EC2에서 동일한 실험을 실행하고 결과를 비교합니다.

---

## 프로젝트 구조

```
local-llm-comparison/
├── .env                          # AWS 자격증명 및 EC2 정보 (git 제외)
├── .env.example                  # .env 템플릿
├── experiments/
│   ├── experiment_config.sh      # ★ 실험 설정 (모델, EC2 스펙, 타임아웃 등)
│   ├── experiment.sh             # 실험 본체 (직접 실행 X — run 스크립트가 호출)
│   └── sample_regulation.txt     # 실험용 사내 규정 문서 (3개 조항)
├── scripts/
│   ├── run_local_experiment.sh   # 로컬 실험 실행
│   ├── run_experiment.sh         # EC2 실험 실행 (업로드 → 실행 → 결과 수집)
│   ├── ec2_create.sh             # EC2 인스턴스 최초 생성
│   ├── ec2_start.sh              # EC2 인스턴스 시작
│   ├── ec2_stop.sh               # EC2 인스턴스 중지
│   ├── pull_models.sh            # Ollama 모델 일괄 다운로드
│   └── user_data.sh              # EC2 부팅 시 자동 설치 스크립트
└── results/
    └── *.csv                     # 실험 결과 파일
```

---

## 실험 설정 변경

**`experiments/experiment_config.sh`** 파일 하나만 수정하면 됩니다.

```bash
# 실험할 모델 목록
MODELS=(
  "phi4-mini"
  "qwen2.5:7b"
  "exaone3.5:7.8b"
  "llama3.1:8b"
)

# EC2 인스턴스 스펙
EC2_INSTANCE_TYPE="g4dn.xlarge"   # NVIDIA T4 16GB
EC2_VOLUME_SIZE=100                # EBS 스토리지 (GB)

# Ollama API 설정
API_TIMEOUT=120        # 응답 최대 대기시간 (초)
MAX_TOKENS=512         # 응답 최대 토큰 수

# 실험 설정
JSON_REPEAT=3          # Phase4 반복 횟수
```

> 모델을 추가하거나 변경할 때는 `MODELS` 배열만 수정하면 됩니다.  
> `user_data.sh` / `pull_models.sh` 에도 모델명이 있으니 함께 수정하세요.

---

## 사전 준비 (최초 1회)

### 1. 필수 도구 설치

```bash
# AWS CLI (Windows PowerShell)
winget install -e --id Amazon.AWSCLI

# Ollama (로컬 실험 시)
# https://ollama.com 에서 설치
```

### 2. 스크립트 실행 권한 부여

```bash
chmod +x scripts/*.sh experiments/*.sh
```

### 3. .env 파일 설정

```bash
cp .env.example .env
```

`.env` 파일에서 값 입력:

```bash
AWS_ACCESS_KEY_ID=...           # IAM 콘솔에서 발급
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=ap-northeast-3       # 오사카 리전

EC2_KEY_NAME=my-key             # AWS 콘솔 키 페어 이름 (.pem 제외)
EC2_KEY_PATH=/c/Users/.../my-key.pem   # 로컬 pem 파일 경로 (Git Bash 형식)
EC2_USER=ubuntu
```

> `EC2_INSTANCE_ID`, `OLLAMA_HOST`는 비워둬도 됩니다 — 스크립트가 자동으로 채워줍니다.

---

## 로컬 실험

### 1. Ollama 실행 후 모델 설치

```bash
# 모델 설치
ollama pull phi4-mini
ollama pull qwen2.5:7b
ollama pull exaone3.5:7.8b
ollama pull llama3.1:8b

# 설치 확인
ollama list
```

### 2. 실험 실행

```bash
# Git Bash에서 실행
./scripts/run_local_experiment.sh
```

결과는 `results/experiment_results_YYYYMMDD_HHMMSS.csv`에 저장됩니다.

---

## EC2 실험

### 최초 1회: 인스턴스 생성

```bash
./scripts/ec2_create.sh
```

자동으로 처리되는 항목:
- Ubuntu 22.04 최신 AMI 자동 조회
- 보안 그룹 생성 (내 IP만 SSH/Ollama 포트 허용)
- `EC2_INSTANCE_TYPE` 사양으로 인스턴스 생성
- NVIDIA 드라이버 + Ollama + 모델 자동 설치 (약 15분 소요)
- `.env`의 `EC2_INSTANCE_ID`, `OLLAMA_HOST` 자동 업데이트

### 매번 실험할 때

```bash
# 1. 인스턴스 시작
./scripts/ec2_start.sh

# 2. 실험 실행 (업로드 → EC2 실행 → 결과 수집 자동)
./scripts/run_experiment.sh

# 3. 실험 끝나면 반드시 중지 (비용 절약)
./scripts/ec2_stop.sh
```

---

## 실험 구성

| Phase | 내용 | 질문 수 |
|-------|------|---------|
| Phase 2 | 문서 없이 한국어 이해 (모델 자체 능력 테스트) | 4개 |
| Phase 3 | RAG 시뮬레이션 (규정 문서 주입) | 8개 |
| Phase 4 | JSON 구조화 출력 일관성 (N회 반복) | JSON_REPEAT × 1개 |

---

## 비용 참고 (EC2 g4dn.xlarge 기준)

| 상태 | 비용 |
|------|------|
| 실행 중 | $0.526/시간 |
| 중지 중 (EBS 100GB) | 약 $8/월 |
| 하루 2시간 실험 기준 | 약 $32/월 |

**실험 후 반드시 `ec2_stop.sh` 실행하세요.**  
완전히 사용 안 할 경우 AWS 콘솔에서 **Terminate(종료)** 해야 스토리지 비용도 없어집니다.

---

## 결과 분석

실험 결과 CSV는 `results/` 폴더에 저장됩니다.  
분석 보고서 예시: `results/LLM_실험_분석_결과.md`

| 컬럼 | 설명 |
|------|------|
| 모델 | 실험 모델명 |
| Phase | Phase2 / Phase3 / Phase4 |
| 질문ID | Q2-1, Q3-1 등 |
| 응답(앞N자) | 모델 응답 앞부분 |
| 속도(t/s) | 토큰/초 (높을수록 빠름) |
| 소요시간(ms) | 전체 응답 생성 시간 |
