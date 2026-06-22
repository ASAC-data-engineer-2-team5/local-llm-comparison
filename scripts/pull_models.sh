#!/bin/bash
# 실험 대상 모델을 Ollama에 pull하는 스크립트
# EC2가 실행 중인 상태에서 사용

# .env 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "오류: .env 파일이 없습니다."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [ -z "$OLLAMA_HOST" ]; then
  echo "오류: OLLAMA_HOST가 비어 있습니다. ec2_start.sh를 먼저 실행해주세요."
  exit 1
fi

# Ollama 서버 응답 확인
if ! curl -s --max-time 5 "$OLLAMA_HOST" > /dev/null 2>&1; then
  echo "오류: Ollama 서버에 연결할 수 없습니다 ($OLLAMA_HOST)"
  echo "EC2가 실행 중인지 확인해주세요."
  exit 1
fi

echo "=== 모델 다운로드 시작 ==="
echo "대상 서버: $OLLAMA_HOST"
echo ""

MODELS=(
  "phi4-mini"           # 3.8B, MIT
  "qwen3:4b-instruct"   # 4B, Apache 2.0
  "qwen2.5:7b"          # 7B, Apache 2.0
  "exaone3.5:7.8b"      # 7.8B, LG AI (한국어 특화)
  "llama3.1:8b"         # 8B, Llama License
  "qwen2.5:14b"         # 14B, Apache 2.0 (T4 16GB 필요)
)

for MODEL in "${MODELS[@]}"; do
  echo ">>> pulling $MODEL ..."

  # 스트리밍 응답을 받으며 status 줄만 출력 (Python 없이 awk 사용)
  curl -s --no-buffer "$OLLAMA_HOST/api/pull" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$MODEL\"}" | \
    awk -F'"' '/"status"/ { print "    " $4 }'

  echo "    완료: $MODEL"
  echo ""
done

echo "=== 설치된 모델 목록 ==="
curl -s "$OLLAMA_HOST/api/tags" | \
  awk -F'"' '/"name"/ { print "  - " $4 }'
