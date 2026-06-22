#!/bin/bash
# EC2에서 git pull 후 실험 실행, 결과를 로컬로 가져오는 스크립트

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "오류: .env 파일이 없습니다."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

EC2_IP=$(echo "$OLLAMA_HOST" | sed 's|http://||;s|:.*||')
SSH_KEY="$EC2_KEY_PATH"
EC2_USER="${EC2_USER:-ubuntu}"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no $EC2_USER@$EC2_IP"
SCP="scp -i $SSH_KEY -o StrictHostKeyChecking=no"

REPO_URL=$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)
REPO_DIR="/home/ubuntu/EUNBEE2/local-llm-comparison"
RESULTS_DIR="$SCRIPT_DIR/../results"

echo "=== 실험 환경 ==="
echo "EC2 IP     : $EC2_IP"
echo "Repository : $REPO_URL"
echo "결과 저장  : results/"
echo ""

# 1. EC2에서 git clone 또는 git pull
echo ">>> [1/3] EC2에서 코드 동기화 중..."
$SSH "
  if [ ! -d $REPO_DIR ]; then
    echo '    git clone 실행 중...'
    mkdir -p /home/ubuntu/EUNBEE2
    git clone $REPO_URL $REPO_DIR
  else
    echo '    git pull 실행 중...'
    git -C $REPO_DIR pull
  fi
"
echo "    코드 동기화 완료"

# 2. EC2에서 실험 실행 (UTF-8 로케일 명시 — 한국어 인코딩 보장)
echo ""
echo ">>> [2/3] EC2에서 실험 실행 중..."
echo "    (모델 수 × 전체 질문 = 약 30~60분 소요)"
echo ""
$SSH "export LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8 EXPERIMENT_ENV=ec2; chmod +x $REPO_DIR/experiments/experiment.sh && bash $REPO_DIR/experiments/experiment.sh"

# 3. 결과 파일 로컬로 가져오기
echo ""
echo ">>> [3/3] 결과 파일 다운로드 중..."
mkdir -p "$RESULTS_DIR"
$SCP "$EC2_USER@$EC2_IP:~/experiment_results_*.csv" "$RESULTS_DIR/"

echo ""
echo "=============================="
echo "  실험 완료"
echo "  결과 위치: results/"
ls "$RESULTS_DIR"/*.csv 2>/dev/null | tail -1
echo "=============================="
