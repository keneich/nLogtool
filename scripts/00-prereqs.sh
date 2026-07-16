#!/usr/bin/env bash
# 전 노드 공통 사전 준비. 실행 전 아래 ROLE 값을 노드에 맞게 지정한다.
#   ROLE=elastic01      -> Elastic01  (10.9.88.2)
#   ROLE=fleet-kibana   -> FleetKibana(10.9.88.61)
#   ROLE=logstash       -> Logstash01/Logstash02 (10.9.88.4 / 10.9.88.9)
#
# 사용법: sudo ROLE=elastic01 DISK_DEVICE=/dev/sdb ./00-prereqs.sh
set -euo pipefail

ROLE="${ROLE:?ROLE 환경변수를 elastic01 | fleet-kibana | logstash 중 하나로 지정하세요}"
DISK_DEVICE="${DISK_DEVICE:-/dev/sdb}"   # lsblk로 실제 두 번째 디스크 디바이스명을 먼저 확인할 것

case "$ROLE" in
  elastic01)    MOUNT_PATH=/data/elasticsearch ;;
  fleet-kibana) MOUNT_PATH=/data ;;
  logstash)     MOUNT_PATH=/data/logstash ;;
  *) echo "알 수 없는 ROLE: $ROLE" >&2; exit 1 ;;
esac

echo "== [1/6] 시간 동기화 =="
apt-get update -y
apt-get install -y chrony apt-transport-https gnupg curl
systemctl enable --now chrony

echo "== [2/6] Elastic 9.x APT 저장소 등록 =="
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" \
  > /etc/apt/sources.list.d/elastic-9.x.list
apt-get update -y

echo "== [3/6] /etc/hosts 등록 =="
for line in \
  "10.9.88.2    elastic01" \
  "10.9.88.61   fleet-kibana" \
  "10.9.88.4    logstash01" \
  "10.9.88.9    logstash02"
do
  grep -qF "$line" /etc/hosts || echo "$line" >> /etc/hosts
done

echo "== [4/6] 스왑 비활성화 =="
swapoff -a || true
sed -i '/\sswap\s/s/^/#/' /etc/fstab

echo "== [5/6] 두 번째 디스크(${DISK_DEVICE}) 마운트 -> ${MOUNT_PATH} =="
if [ ! -b "${DISK_DEVICE}1" ]; then
  parted -s "$DISK_DEVICE" mklabel gpt mkpart primary ext4 0% 100%
  mkfs.ext4 -F "${DISK_DEVICE}1"
fi
UUID=$(blkid -s UUID -o value "${DISK_DEVICE}1")
mkdir -p "$MOUNT_PATH"
grep -q "$UUID" /etc/fstab || echo "UUID=${UUID}  ${MOUNT_PATH}  ext4  defaults,nofail  0  2" >> /etc/fstab
mount -a

echo "== [6/6] 커널/리소스 튜닝 =="
if [ "$ROLE" = "elastic01" ]; then
  echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elasticsearch.conf
  sysctl --system
fi
cat > /etc/security/limits.d/elastic-stack.conf <<'EOF'
*   soft   nofile   65535
*   hard   nofile   65535
EOF

echo "완료: ROLE=${ROLE}, MOUNT_PATH=${MOUNT_PATH}"
