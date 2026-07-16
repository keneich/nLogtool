#!/usr/bin/env bash
# FleetKibana (10.9.88.61) 전용 - Fleet Server 설치 (Kibana와 같은 노드에 colocate)
#
# 사전조건:
#  - Kibana가 기동 중이고 Fleet UI에서 "Fleet Server Policy"가 생성되어 있어야 함
#    (Kibana Fleet 화면에서 최초 "Add Fleet Server" 진입 시 자동 생성되며, 이때 화면에 표시되는
#     설치 명령을 그대로 사용해도 된다 — 아래 스크립트는 그 명령과 동일한 내용을 재현한 템플릿이다)
#  - /etc/fleet-server/certs/{ca.crt,fleet-kibana.crt,fleet-kibana.key} 배포 완료 (02-certificates.md)
#  - docs/03-elasticsearch.md 4.2절에서 발급한 fleet-server 서비스 토큰
#
# 사용법:
#   sudo AGENT_VERSION=9.x.y \
#        FLEET_SERVER_POLICY_ID=<Kibana Fleet에서 확인한 정책 ID> \
#        FLEET_SERVICE_TOKEN=<elasticsearch-service-tokens 출력값> \
#        ./04-install-fleet-server.sh
set -euo pipefail

AGENT_VERSION="${AGENT_VERSION:?https://www.elastic.co/downloads/elastic-agent 에서 ES/Kibana와 동일한 9.x 버전을 확인해 지정하세요 (예: 9.1.3)}"
FLEET_SERVER_POLICY_ID="${FLEET_SERVER_POLICY_ID:?Kibana Fleet > Agent policies > Fleet Server Policy 의 ID를 지정하세요}"
FLEET_SERVICE_TOKEN="${FLEET_SERVICE_TOKEN:?docs/03-elasticsearch.md 4.2절에서 발급한 서비스 토큰을 지정하세요}"
CERT_DIR="${CERT_DIR:-/etc/fleet-server/certs}"

case "$(uname -m)" in
  x86_64)          PKG_ARCH=x86_64 ;;
  aarch64|arm64)   PKG_ARCH=arm64 ;;
  *) echo "지원하지 않는 아키텍처: $(uname -m)" >&2; exit 1 ;;
esac

WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"
curl -L -O "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${AGENT_VERSION}-linux-${PKG_ARCH}.tar.gz"
tar xzf "elastic-agent-${AGENT_VERSION}-linux-${PKG_ARCH}.tar.gz"
cd "elastic-agent-${AGENT_VERSION}-linux-${PKG_ARCH}"

# --install-servers: 9.0+ 에서 --fleet-server-* 옵션 사용 시 명시적으로 필요
# (없으면 "timed out waiting for Fleet Server to start" 오류로 실패할 수 있음).
# 설치 중인 elastic-agent 버전에서 사용 가능한 최신 플래그는 `./elastic-agent install --help` 로 재확인할 것.
./elastic-agent install \
  --install-servers \
  --url="https://fleet-kibana:8220" \
  --fleet-server-es="https://elastic01:9200" \
  --fleet-server-es-ca="${CERT_DIR}/ca.crt" \
  --fleet-server-service-token="${FLEET_SERVICE_TOKEN}" \
  --fleet-server-policy="${FLEET_SERVER_POLICY_ID}" \
  --fleet-server-cert="${CERT_DIR}/fleet-kibana.crt" \
  --fleet-server-cert-key="${CERT_DIR}/fleet-kibana.key" \
  --fleet-server-port=8220 \
  --certificate-authorities="${CERT_DIR}/ca.crt" \
  --non-interactive

cd /
rm -rf "$WORK_DIR"

echo "기동 확인: systemctl status elastic-agent"
echo "Kibana Fleet > Agents 화면에서 Fleet Server 에이전트가 Healthy 상태인지 확인"
