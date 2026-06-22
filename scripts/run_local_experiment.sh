#!/bin/bash
# 로컬 Ollama에서 실험 실행

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENTS_DIR="$SCRIPT_DIR/../experiments"
RESULTS_DIR="$SCRIPT_DIR/../results"

# 로컬 Ollama 응답 확인
if ! curl -s --max-time 5 "http://localhost:11434" > /dev/null 2>&1; then
  echo "오류: 로컬 Ollama가 실행 중이지 않습니다."
  echo "Ollama를 먼저 실행해주세요 (시작 메뉴에서 Ollama 실행)"
  exit 1
fi

echo "=== 로컬 실험 환경 ==="
echo "Ollama : http://localhost:11434"
echo "결과   : results/"
echo ""
echo ">>> 설치된 모델 목록:"
curl -s http://localhost:11434/api/tags | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sed 's/^/  - /'
echo ""

# 규정 파일 및 config를 홈 디렉토리에 복사 (experiment 스크립트가 $HOME에서 읽음)
cp "$EXPERIMENTS_DIR/sample_regulation.txt" "$HOME/sample_regulation.txt"
cp "$EXPERIMENTS_DIR/experiment_config.sh"  "$HOME/experiment_config.sh"

# Python UTF-8 강제 설정 (Windows CP949 인코딩 문제 방지)
export PYTHONIOENCODING=utf-8
export PYTHONUTF8=1

# 실험 실행 (localhost 사용하도록 환경변수 오버라이드)
EXPERIMENT_ENV=local OLLAMA_ENDPOINT="http://localhost:11434" bash "$EXPERIMENTS_DIR/experiment.sh"

# 결과 파일을 results/ 로 이동
mkdir -p "$RESULTS_DIR"
mv "$HOME"/experiment_results_*.csv "$RESULTS_DIR/" 2>/dev/null

echo ""
echo "결과 파일:"
ls "$RESULTS_DIR"/*.csv 2>/dev/null | tail -3
