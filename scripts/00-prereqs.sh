#!/usr/bin/env bash
# 전 노드 공통 사전 준비. 실행 전 아래 ROLE 값을 노드에 맞게 지정한다.
#   ROLE=elastic01      -> Elastic01  (10.9.88.2)
#   ROLE=fleet-kibana   -> FleetKibana(10.9.88.61)
#   ROLE=logstash       -> Logstash01/Logstash02 (10.9.88.4 / 10.9.88.9)
#
# 사용법: sudo ROLE=elastic01 ./00-prereqs.sh
# (두 번째 디스크 마운트는 수동으로 처리했다고 가정하고 이 스크립트에서는 다루지 않는다.
#  MOUNT_PATH 아래 표에 맞춰 이미 마운트되어 있어야 이후 설치 스크립트가 정상 동작한다.)
set -euo pipefail

ROLE="${ROLE:?ROLE 환경변수를 elastic01 | fleet-kibana | logstash 중 하나로 지정하세요}"

case "$ROLE" in
  elastic01)    MOUNT_PATH=/data/elasticsearch ;;
  fleet-kibana) MOUNT_PATH=/data ;;
  logstash)     MOUNT_PATH=/data/logstash ;;
  *) echo "알 수 없는 ROLE: $ROLE" >&2; exit 1 ;;
esac

echo "== [1/5] 시간 동기화 =="
apt-get update -y
apt-get install -y chrony apt-transport-https gnupg curl
systemctl enable --now chrony

echo "== [2/5] Elastic 9.x APT 저장소 등록 =="
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" \
  > /etc/apt/sources.list.d/elastic-9.x.list
apt-get update -y

echo "== [3/5] /etc/hosts 등록 =="
for line in \
  "10.9.88.2    elastic01" \
  "10.9.88.61   fleet-kibana" \
  "10.9.88.4    logstash01" \
  "10.9.88.9    logstash02"
do
  grep -qF "$line" /etc/hosts || echo "$line" >> /etc/hosts
done

echo "== [4/5] 스왑 비활성화 =="
swapoff -a || true
sed -i '/\sswap\s/s/^/#/' /etc/fstab

if [ ! -d "$MOUNT_PATH" ]; then
  echo "경고: ${MOUNT_PATH} 가 존재하지 않습니다. 두 번째 디스크 마운트를 먼저 확인하세요." >&2
fi

echo "== [5/5] 커널/리소스 튜닝 =="
if [ "$ROLE" = "elastic01" ]; then
  echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elasticsearch.conf
  sysctl --system
fi
cat > /etc/security/limits.d/elastic-stack.conf <<'EOF'
*   soft   nofile   65535
*   hard   nofile   65535
EOF

echo "완료: ROLE=${ROLE}, MOUNT_PATH=${MOUNT_PATH}"
