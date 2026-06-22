#!/bin/bash
# 로컬 및 EC2에서 실행하는 LLM 실험 스크립트
# 설정 변경은 experiment_config.sh 에서

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config 로드 (같은 디렉토리 또는 $HOME 에서 탐색)
if [ -f "$SCRIPT_DIR/experiment_config.sh" ]; then
  source "$SCRIPT_DIR/experiment_config.sh"
elif [ -f "$HOME/experiment_config.sh" ]; then
  source "$HOME/experiment_config.sh"
else
  echo "경고: experiment_config.sh 를 찾을 수 없습니다. 기본값으로 실행합니다."
  MODELS_LOCAL=("phi4-mini" "qwen2.5:7b" "exaone3.5:7.8b" "llama3.1:8b")
  MODELS_EC2=("phi4-mini" "qwen2.5:7b" "exaone3.5:7.8b" "llama3.1:8b" "qwen2.5:14b")
  OLLAMA_PORT=11434
  API_TIMEOUT=180
  MAX_TOKENS=512
  TEMPERATURE=0
  SEED=42
  JSON_REPEAT=3
  RESPONSE_PREVIEW_CHARS=200
fi

# 실험 환경에 따라 모델 목록 결정 (run 스크립트에서 EXPERIMENT_ENV 주입)
if [ "${EXPERIMENT_ENV}" = "ec2" ]; then
  MODELS=("${MODELS_EC2[@]}")
else
  MODELS=("${MODELS_LOCAL[@]}")
fi

RESULT_FILE="$HOME/experiment_results_$(date +%Y%m%d_%H%M%S).csv"
REGULATION_FILE="${SCRIPT_DIR}/sample_regulation.txt"
[ ! -f "$REGULATION_FILE" ] && REGULATION_FILE="$HOME/sample_regulation.txt"
REGULATION=$(cat "$REGULATION_FILE")
OLLAMA_API="${OLLAMA_ENDPOINT:-http://localhost:$OLLAMA_PORT}"

# Python 명령어 자동 감지 (EC2: python3 / Windows: python)
if command -v python3 &>/dev/null; then
  PYTHON=python3
elif command -v python &>/dev/null; then
  PYTHON=python
else
  echo "오류: Python이 설치되어 있지 않습니다."
  exit 1
fi

# GPU 상태 체크 함수
check_gpu() {
  if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu \
      --format=csv,noheader,nounits 2>/dev/null | \
      awk -F',' '{printf "  GPU  : %s\n  VRAM : 전체 %sMB | 사용 %sMB | 여유 %sMB | 점유율 %s%%\n", $1,$2,$3,$4,$5}'
  else
    echo "  GPU  : nvidia-smi 없음 (CPU 전용 환경)"
  fi
}

# 모델별 VRAM 사용량 확인 함수
check_model_gpu() {
  if command -v nvidia-smi &>/dev/null; then
    local USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
    echo "  VRAM 사용량: ${USED}MB (모델 로드 후)"
  fi
}

# 워밍업 함수 — 모델을 VRAM에 미리 올려서 첫 질문 속도 왜곡 방지
warmup_model() {
  local MODEL=$1
  echo "  (워밍업 중...)"
  curl -s --max-time 60 "$OLLAMA_API/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$MODEL\", \"prompt\": \"안녕\", \"stream\": false, \"options\": {\"num_predict\": 1, \"temperature\": $TEMPERATURE, \"seed\": $SEED}}" > /dev/null
}

# API 호출 함수 (temperature, seed 통일 적용)
call_ollama() {
  local MODEL=$1
  local PROMPT=$2
  local ENCODED_PROMPT=$(echo "$PROMPT" | $PYTHON -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  local PAYLOAD="{\"model\": \"$MODEL\", \"prompt\": $ENCODED_PROMPT, \"stream\": false, \"options\": {\"num_predict\": $MAX_TOKENS, \"temperature\": $TEMPERATURE, \"seed\": $SEED}}"

  local RESULT=$(curl -s --max-time "$API_TIMEOUT" "$OLLAMA_API/api/generate" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  # 응답이 비어있으면 5초 후 1회 재시도
  if [ -z "$RESULT" ] || ! echo "$RESULT" | $PYTHON -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    sleep 5
    RESULT=$(curl -s --max-time "$API_TIMEOUT" "$OLLAMA_API/api/generate" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD")
  fi

  echo "$RESULT"
}

# 결과 파싱 및 CSV 저장 함수
save_result() {
  local MODEL=$1
  local PHASE=$2
  local QID=$3
  local QUESTION=$4
  local RESULT=$5

  RESPONSE=$(echo "$RESULT" | $PYTHON -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('response','').replace('\n',' ').replace('\"','\"\"')[:$RESPONSE_PREVIEW_CHARS])
except:
    print('파싱오류')
")
  TOKENS=$(echo "$RESULT" | $PYTHON -c "import sys,json; d=json.load(sys.stdin); print(d.get('eval_count',0))" 2>/dev/null || echo 0)
  DURATION=$(echo "$RESULT" | $PYTHON -c "import sys,json; d=json.load(sys.stdin); print(d.get('eval_duration',1))" 2>/dev/null || echo 1)
  TPS=$($PYTHON -c "print(round($TOKENS / max($DURATION / 1e9, 0.001), 1))" 2>/dev/null || echo 0)
  ELAPSED=$($PYTHON -c "print(round($DURATION / 1e6))" 2>/dev/null || echo 0)

  Q_ESCAPED=$(echo "$QUESTION" | sed 's/"/""/g')
  echo "\"$MODEL\",\"$PHASE\",\"$QID\",\"$Q_ESCAPED\",\"$RESPONSE\",\"$TPS\",\"$ELAPSED\"" >> "$RESULT_FILE"
  echo "  [$MODEL] $QID → ${TPS}t/s | ${ELAPSED}ms"
}

# CSV 헤더
echo "모델,Phase,질문ID,질문,응답(앞${RESPONSE_PREVIEW_CHARS}자),속도(t/s),소요시간(ms)" > "$RESULT_FILE"
echo "=== 실험 시작: $(date) ===" | tee -a "$HOME/experiment_log.txt"
echo "    환경       : ${EXPERIMENT_ENV:-local}"
echo "    모델       : ${MODELS[*]}"
echo "    API        : $OLLAMA_API"
echo "    Temperature: $TEMPERATURE / Seed: $SEED"
echo ""
check_gpu
echo ""

# ============================================================
# Phase 2: 컨텍스트 없이 한국어 이해 테스트
# ============================================================
echo "=== Phase 2: 컨텍스트 없이 한국어 이해 테스트 ==="

P2_QUESTIONS=(
  "Q2-1|연차유급휴가를 사용하려면 며칠 전에 신청해야 하나요?"
  "Q2-2|3년 이상 근속한 직원은 연차가 기본 15일에서 어떻게 가산되나요?"
  "Q2-3|직장 내 괴롭힘을 당했을 때 어떻게 신고해야 하나요?"
  "Q2-4|회사 구내식당 이용 시간과 메뉴는 어떻게 확인하나요?"
)

for MODEL in "${MODELS[@]}"; do
  echo ""
  echo ">>> 모델: $MODEL"
  warmup_model "$MODEL"
  check_model_gpu
  for Q in "${P2_QUESTIONS[@]}"; do
    QID="${Q%%|*}"
    QUESTION="${Q##*|}"
    # printf로 실제 줄바꿈 처리 (\n 리터럴 버그 수정)
    PROMPT=$(printf "당신은 사내 규정 안내 챗봇입니다. 다음 질문에 간결하게 답해주세요. 모르는 내용은 모른다고 명확히 말해주세요.\n\n질문: %s" "$QUESTION")
    RESULT=$(call_ollama "$MODEL" "$PROMPT")
    save_result "$MODEL" "Phase2" "$QID" "$QUESTION" "$RESULT"
  done
done

# ============================================================
# Phase 3: RAG 시뮬레이션 (규정 문서 주입)
# ============================================================
echo ""
echo "=== Phase 3: RAG 시뮬레이션 (규정 문서 주입) ==="

P3_QUESTIONS=(
  "Q3-1|채용 공고는 최소 며칠 이상 게시해야 하나요?"
  "Q3-2|합격 통지 이후 내정이 취소될 수 있는 사유를 모두 알려주세요."
  "Q3-3|입사 후 8개월간 매달 개근했다면 연차는 총 며칠 발생하나요?"
  "Q3-4|5년 근속자의 총 연차 일수는 며칠인가요? 계산 과정도 보여주세요."
  "Q3-5|직장 내 괴롭힘 신고 시 작성해야 하는 서식 번호는 무엇인가요?"
  "Q3-6|연차 사용촉진 2차 조치는 언제 이루어지나요?"
  "Q3-7|상사의 지시가 위법하다고 판단될 때 어떻게 해야 하나요?"
  "Q3-8|야근 수당 지급 기준은 어떻게 되나요?"
)

for MODEL in "${MODELS[@]}"; do
  echo ""
  echo ">>> 모델: $MODEL"
  warmup_model "$MODEL"
  check_model_gpu
  for Q in "${P3_QUESTIONS[@]}"; do
    QID="${Q%%|*}"
    QUESTION="${Q##*|}"
    PROMPT=$(printf "당신은 사내 규정 안내 챗봇입니다. 아래 제공된 사내 규정만을 근거로 질문에 답하세요. 규정에 명시되지 않은 내용은 반드시 '해당 내용은 규정에 명시되어 있지 않습니다'라고 답하세요.\n\n[사내 규정]\n%s\n\n질문: %s" "$REGULATION" "$QUESTION")
    RESULT=$(call_ollama "$MODEL" "$PROMPT")
    save_result "$MODEL" "Phase3" "$QID" "$QUESTION" "$RESULT"
  done
done

# ============================================================
# Phase 4: JSON 구조화 출력 (일관성 테스트)
# ============================================================
echo ""
echo "=== Phase 4: JSON 구조화 출력 테스트 ==="

JSON_PROMPT='다음 직원 질문을 분석하여 반드시 JSON 형식으로만 반환하세요. 다른 텍스트는 절대 포함하지 마세요.

질문: "저는 입사한 지 4개월 됐는데 이번 달에 연차를 쓸 수 있나요?"

반환 형식:
{
  "intent": "질문 의도",
  "category": "인사/복무/급여/채용 중 하나",
  "key_terms": ["핵심 키워드 배열"],
  "needs_document": true 또는 false,
  "urgency": "high/medium/low"
}'

for MODEL in "${MODELS[@]}"; do
  echo ""
  echo ">>> 모델: $MODEL (${JSON_REPEAT}회 반복 - 일관성 확인)"
  warmup_model "$MODEL"
  check_model_gpu
  for ((i=1; i<=JSON_REPEAT; i++)); do
    RESULT=$(call_ollama "$MODEL" "$JSON_PROMPT")
    save_result "$MODEL" "Phase4" "Q4-$i" "JSON 구조화 출력 (${i}회차)" "$RESULT"
  done
done

echo ""
echo "=============================="
echo "  실험 완료"
echo "  결과 파일: $RESULT_FILE"
echo "=============================="
echo "=== 실험 완료: $(date) ===" | tee -a "$HOME/experiment_log.txt"
