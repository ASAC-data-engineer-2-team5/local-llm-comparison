#!/bin/bash
# EC2 인스턴스 생성 + .env의 EC2_INSTANCE_ID 자동 입력
# 최초 1회만 실행

# .env 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "오류: .env 파일이 없습니다."
  echo "  cp .env.example .env 후 값을 채워주세요."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

# 필수 변수 확인
if [ -z "$AWS_REGION" ] || [ -z "$EC2_KEY_NAME" ]; then
  echo "오류: .env에 AWS_REGION, EC2_KEY_NAME 값을 입력해주세요."
  exit 1
fi

if [ -n "$EC2_INSTANCE_ID" ]; then
  echo "이미 EC2_INSTANCE_ID가 설정되어 있습니다: $EC2_INSTANCE_ID"
  echo "새로 만들려면 .env에서 EC2_INSTANCE_ID를 비워주세요."
  exit 1
fi

echo "=== EC2 인스턴스 생성 시작 ==="

# 1. Ubuntu 22.04 최신 AMI ID 자동 조회
echo ">>> [1/4] Ubuntu 22.04 AMI 조회 중..."
AMI_ID=$(aws ec2 describe-images \
  --region $AWS_REGION \
  --owners 099720109477 \
  --filters \
    "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    "Name=architecture,Values=x86_64" \
    "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text)

echo "    AMI: $AMI_ID"

# 2. 보안 그룹 생성 (내 IP만 허용)
echo ">>> [2/4] 보안 그룹 생성 중..."
MY_IP=$(curl -s https://checkip.amazonaws.com)
SG_NAME="llm-experiment-sg"

SG_ID=$(aws ec2 create-security-group \
  --region $AWS_REGION \
  --group-name $SG_NAME \
  --description "LLM experiment: SSH and Ollama access" \
  --query "GroupId" \
  --output text 2>/dev/null)

if [ -z "$SG_ID" ]; then
  # 이미 존재하면 기존 SG ID 가져오기
  SG_ID=$(aws ec2 describe-security-groups \
    --region $AWS_REGION \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query "SecurityGroups[0].GroupId" \
    --output text)
  echo "    기존 보안 그룹 사용: $SG_ID"
else
  # SSH (22) 허용
  aws ec2 authorize-security-group-ingress \
    --region $AWS_REGION \
    --group-id $SG_ID \
    --protocol tcp --port 22 --cidr "$MY_IP/32" > /dev/null

  # Ollama API (11434) 허용
  aws ec2 authorize-security-group-ingress \
    --region $AWS_REGION \
    --group-id $SG_ID \
    --protocol tcp --port 11434 --cidr "$MY_IP/32" > /dev/null

  echo "    보안 그룹 생성 완료: $SG_ID (허용 IP: $MY_IP)"
fi

# 3. user_data.sh 읽기
USER_DATA_FILE="$SCRIPT_DIR/user_data.sh"
if [ ! -f "$USER_DATA_FILE" ]; then
  echo "오류: user_data.sh 파일이 없습니다."
  exit 1
fi

# 4. 인스턴스 생성
echo ">>> [3/4] 인스턴스 생성 중 (g4dn.xlarge)..."
INSTANCE_ID=$(aws ec2 run-instances \
  --region $AWS_REGION \
  --image-id $AMI_ID \
  --instance-type g4dn.xlarge \
  --key-name $EC2_KEY_NAME \
  --security-group-ids $SG_ID \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${EC2_VOLUME_SIZE:-100},\"VolumeType\":\"gp3\"}}]" \
  --user-data "$(cat "$USER_DATA_FILE")" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=llm-experiment}]' \
  --query "Instances[0].InstanceId" \
  --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
  echo "오류: 인스턴스 생성 실패. 위 에러 메시지를 확인해주세요."
  exit 1
fi

echo "    인스턴스 ID: $INSTANCE_ID"

# 5. .env에 EC2_INSTANCE_ID 자동 입력
echo ">>> [4/4] .env 업데이트 중..."
sed -i "s|^EC2_INSTANCE_ID=.*|EC2_INSTANCE_ID=$INSTANCE_ID|" "$ENV_FILE"

echo ""
echo "=============================="
echo "  인스턴스 생성 완료"
echo "=============================="
echo "  인스턴스 ID : $INSTANCE_ID"
echo "  AMI         : $AMI_ID"
echo "  타입        : g4dn.xlarge"
echo "  보안 그룹   : $SG_ID"
echo "=============================="
echo ""
echo "드라이버 + Ollama + 모델 자동 설치 중 (약 15분 소요)"
echo "완료 후 ./scripts/ec2_start.sh 실행하지 않아도 바로 접속 가능합니다."
echo "(인스턴스 생성 직후에는 이미 running 상태)"
echo ""

# 현재 IP 출력 (생성 직후 running 상태이므로 바로 확인)
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region $AWS_REGION \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

sed -i "s|^OLLAMA_HOST=.*|OLLAMA_HOST=http://$PUBLIC_IP:11434|" "$ENV_FILE"

echo "  IP          : $PUBLIC_IP"
echo "  SSH 접속    : ssh -i $EC2_KEY_PATH $EC2_USER@$PUBLIC_IP"
echo "  (15분 후 Ollama 준비 완료)"
