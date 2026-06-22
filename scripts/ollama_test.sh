#!/bin/bash
# Ollama API 기본 동작 확인 및 속도 측정 스크립트

# .env 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "오류: .env 파일이 없습니다. .env.example을 복사해서 값을 채워주세요."
  echo "  cp .env.example .env"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

BASE_URL="$OLLAMA_HOST"
MODEL="${1:-$OLLAMA_MODEL}"   # 인자로 모델명 전달 가능: ./ollama_test.sh llama3.1:8b
TEST_PROMPT="사내 연차 규정에 대해 한 문장으로 설명해줘."

echo "=============================="
echo "  Ollama 연결 테스트"
echo "  대상: $BASE_URL"
echo "  모델: $MODEL"
echo "=============================="

# 1. 서버 응답 확인
echo ""
echo ">>> [1/3] 서버 응답 확인..."
if curl -s --max-time 5 "$BASE_URL" > /dev/null; then
  echo "    연결 성공"
else
  echo "    연결 실패 - IP 또는 Security Group 확인 필요"
  exit 1
fi

# 2. 모델 목록 확인
echo ""
echo ">>> [2/3] 설치된 모델 목록:"
curl -s "$BASE_URL/api/tags" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('models', []):
    size_gb = m.get('size', 0) / 1024**3
    print(f\"    - {m['name']} ({size_gb:.1f} GB)\")
"

# 3. 추론 속도 측정
echo ""
echo ">>> [3/3] 추론 속도 측정 중..."
echo "    프롬프트: $TEST_PROMPT"
echo ""

START_TIME=$(date +%s%N)

RESPONSE=$(curl -s "$BASE_URL/api/generate" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"prompt\": \"$TEST_PROMPT\",
    \"stream\": false
  }")

END_TIME=$(date +%s%N)
ELAPSED=$(( (END_TIME - START_TIME) / 1000000 ))  # ms 단위

ANSWER=$(echo $RESPONSE | python3 -c "import sys,json; print(json.load(sys.stdin).get('response',''))" 2>/dev/null)
EVAL_COUNT=$(echo $RESPONSE | python3 -c "import sys,json; print(json.load(sys.stdin).get('eval_count',0))" 2>/dev/null)
EVAL_DURATION=$(echo $RESPONSE | python3 -c "import sys,json; print(json.load(sys.stdin).get('eval_duration',1))" 2>/dev/null)

TOKENS_PER_SEC=$(python3 -c "print(round($EVAL_COUNT / ($EVAL_DURATION / 1e9), 1))" 2>/dev/null)

echo "  응답: $ANSWER"
echo ""
echo "=============================="
echo "  총 소요시간  : ${ELAPSED}ms"
echo "  생성 토큰수  : $EVAL_COUNT tokens"
echo "  추론 속도    : $TOKENS_PER_SEC tokens/sec"
echo "=============================="
