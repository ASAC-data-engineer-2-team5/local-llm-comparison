#!/bin/bash
# EC2 인스턴스 중지 (비용 절약)

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

echo ">>> EC2 인스턴스 중지 중..."
aws ec2 stop-instances \
  --instance-ids $EC2_INSTANCE_ID \
  --region $AWS_REGION \
  --output text > /dev/null

echo ">>> 인스턴스가 stopped 상태가 될 때까지 대기 중..."
aws ec2 wait instance-stopped \
  --instance-ids $EC2_INSTANCE_ID \
  --region $AWS_REGION

echo ""
echo "=============================="
echo "  인스턴스 중지 완료"
echo "  EC2 요금 청구 중지됨"
echo "  EBS 스토리지 비용만 발생 (50GB ≈ 월 $4)"
echo "=============================="
