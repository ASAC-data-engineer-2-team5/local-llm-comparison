#!/bin/bash
# EC2 첫 부팅 시 자동 실행되는 스크립트

set -e
exec > /var/log/user_data.log 2>&1

echo "=== [1/5] 패키지 업데이트 ==="
apt-get update -y
apt-get install -y curl wget

echo "=== [2/5] NVIDIA 드라이버 + CUDA 설치 ==="
# CUDA 공식 저장소 추가 (Ubuntu 22.04)
wget -qO /tmp/cuda-keyring.deb \
  https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i /tmp/cuda-keyring.deb
apt-get update -y

# 드라이버 + CUDA toolkit 설치
apt-get install -y cuda-drivers cuda-toolkit-12-4

# PATH에 CUDA 추가
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/environment
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/environment
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

echo "NVIDIA 드라이버 + CUDA 설치 완료"
nvidia-smi && echo "GPU 인식 성공" || echo "경고: GPU 인식 실패 (드라이버 로드 후 재확인 필요)"

echo "=== [3/5] Ollama 설치 ==="
# CUDA가 설치된 상태에서 Ollama 설치 → 자동으로 GPU 버전 선택
curl -fsSL https://ollama.com/install.sh | sh

# Ollama 외부 접근 허용
mkdir -p /etc/systemd/system/ollama.service.d
cat <<EOF > /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="CUDA_VISIBLE_DEVICES=0"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama
echo "Ollama 설치 및 서비스 시작 완료"

echo "=== [4/5] GPU 연결 확인 ==="
sleep 10
# Ollama가 GPU를 인식했는지 확인
curl -s http://localhost:11434/api/tags > /dev/null && echo "Ollama API 응답 확인" || echo "Ollama 아직 준비 중"
nvidia-smi

echo "=== [5/5] 모델 다운로드 ==="
sleep 10

ollama pull phi4-mini          # 3.8B
ollama pull qwen3:4b-instruct  # 4B, 최신 Qwen3
ollama pull qwen2.5:7b         # 7B
ollama pull exaone3.5:7.8b     # 7.8B, 한국어 특화
ollama pull llama3.1:8b        # 8B
ollama pull qwen2.5:14b        # 14B, 고사양 비교군 (T4 16GB 필요)

echo "=== 설치 완료 ==="
nvidia-smi
ollama list
echo "Ollama API: http://0.0.0.0:11434"
