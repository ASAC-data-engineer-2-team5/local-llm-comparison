#!/bin/bash
# EC2 인스턴스 시작 + 접속 정보 출력

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

echo ">>> EC2 인스턴스 시작 중..."
aws ec2 start-instances \
  --instance-ids $EC2_INSTANCE_ID \
  --region $AWS_REGION \
  --output text > /dev/null

echo ">>> 인스턴스가 running 상태가 될 때까지 대기 중..."
aws ec2 wait instance-running \
  --instance-ids $EC2_INSTANCE_ID \
  --region $AWS_REGION

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $EC2_INSTANCE_ID \
  --region $AWS_REGION \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

# .env의 OLLAMA_HOST 자동 업데이트
sed -i "s|^OLLAMA_HOST=.*|OLLAMA_HOST=http://$PUBLIC_IP:11434|" "$ENV_FILE"
echo ">>> .env OLLAMA_HOST 업데이트 완료 → http://$PUBLIC_IP:11434"

echo ""
echo "=============================="
echo "  인스턴스 준비 완료"
echo "=============================="
echo "  IP          : $PUBLIC_IP"
echo "  Ollama API  : http://$PUBLIC_IP:11434"
echo "  SSH 접속    : ssh -i $EC2_KEY_PATH $EC2_USER@$PUBLIC_IP"
echo "=============================="
echo ""

# Ollama 서비스 응답 대기 (최대 60초)
echo ">>> Ollama 서비스 응답 대기 중..."
for i in $(seq 1 12); do
  if curl -s --max-time 3 "http://$PUBLIC_IP:11434" > /dev/null 2>&1; then
    echo ">>> Ollama 준비 완료!"
    break
  fi
  echo "    대기 중... ($((i * 5))초)"
  sleep 5
done

echo ""
echo ">>> 사용 가능한 모델 목록:"
curl -s "http://$PUBLIC_IP:11434/api/tags" | python3 -c "
import sys, json
data = json.load(sys.stdin)
models = data.get('models', [])
if models:
    for m in models:
        print(f\"    - {m['name']}\")
else:
    print('    모델 없음 (ollama pull 로 설치 필요)')
" 2>/dev/null || echo "    Ollama 응답 없음 (조금 더 기다린 후 재시도)"
