#!/usr/bin/env bash
# 로그 수집 대상 서버(10.0.0.0/8 내부 또는 랜덤 공인 IP 외부) 공용 설치 스크립트.
#
# 사전조건:
#  - CA_CERT_PATH 위치에 CA 인증서(ca.crt, docs/02-certificates.md)가 미리 복사되어 있어야 함
#    (배포 도구/골든 이미지/수동 scp 등으로 이 파일만 사전 배치)
#  - Kibana Fleet > Agents > Add agent 화면에서 대상 망에 맞는 정책(Internal-Servers 또는
#    External-Servers)을 선택해 발급받은 enrollment token
#
# 사용법 (내부 서버):
#   sudo FLEET_URL=https://10.9.88.61:8220 \
#        ENROLLMENT_TOKEN=<Internal-Servers 정책 토큰> \
#        AGENT_VERSION=9.x.y \
#        ./06-enroll-agent.sh
#
# 사용법 (외부/랜덤 공인 IP 서버, NAT 경유):
#   sudo FLEET_URL=https://139.150.84.70:8220 \
#        ENROLLMENT_TOKEN=<External-Servers 정책 토큰> \
#        AGENT_VERSION=9.x.y \
#        ./06-enroll-agent.sh
set -euo pipefail

FLEET_URL="${FLEET_URL:?Fleet Server URL을 지정하세요 (내부: https://10.9.88.61:8220, 외부: https://139.150.84.70:8220)}"
ENROLLMENT_TOKEN="${ENROLLMENT_TOKEN:?Kibana Fleet에서 발급한 enrollment token을 지정하세요}"
AGENT_VERSION="${AGENT_VERSION:?https://www.elastic.co/downloads/elastic-agent 에서 스택과 동일한 9.x 버전을 지정하세요}"
CA_CERT_PATH="${CA_CERT_PATH:-/etc/elastic-stack-ca/ca.crt}"

if [ ! -f "$CA_CERT_PATH" ]; then
  echo "CA 인증서가 없습니다: $CA_CERT_PATH (docs/02-certificates.md 참고해 미리 배포하세요)" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"
curl -L -O "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${AGENT_VERSION}-linux-x86_64.tar.gz"
tar xzf "elastic-agent-${AGENT_VERSION}-linux-x86_64.tar.gz"
cd "elastic-agent-${AGENT_VERSION}-linux-x86_64"

./elastic-agent install \
  --url="${FLEET_URL}" \
  --enrollment-token="${ENROLLMENT_TOKEN}" \
  --certificate-authorities="${CA_CERT_PATH}" \
  --non-interactive

cd /
rm -rf "$WORK_DIR"

echo "기동 확인: systemctl status elastic-agent"
echo "Kibana Fleet > Agents 화면에서 이 호스트가 Healthy 상태인지 확인"
