#!/usr/bin/env bash
# Logstash01 / Logstash02 공용 스크립트. 노드별로 NODE_NAME/NODE_IP만 다르게 지정해 실행한다.
#
# 사전조건:
#  - scripts/00-prereqs.sh ROLE=logstash 실행 완료 (/data/logstash 마운트 등)
#  - docs/02-certificates.md 절차로 /etc/logstash/certs/{ca.crt,<node>.crt,<node>.key} 배포 완료
#  - docs/03-elasticsearch.md 4.3절에서 발급한 logstash-writer-key API 키 ("<id>:<api_key>" 형식)
#
# 사용법 (Logstash01 예시):
#   sudo NODE_NAME=logstash01 NODE_IP=10.9.88.4 ./05-install-logstash.sh
# 사용법 (Logstash02 예시):
#   sudo NODE_NAME=logstash02 NODE_IP=10.9.88.9 ./05-install-logstash.sh
set -euo pipefail

NODE_NAME="${NODE_NAME:?logstash01 또는 logstash02 를 지정하세요}"
NODE_IP="${NODE_IP:?이 노드의 사설 IP를 지정하세요 (10.9.88.4 또는 10.9.88.9)}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

apt-get update -y
apt-get install -y logstash openssl

echo "== elastic_agent 입력 플러그인용 PKCS8 개인키 변환 =="
openssl pkcs8 -in "/etc/logstash/certs/${NODE_NAME}.key" -topk8 -nocrypt \
  -out "/etc/logstash/certs/${NODE_NAME}.pkcs8.key"
chown logstash:logstash "/etc/logstash/certs/${NODE_NAME}.pkcs8.key"
chmod 640 "/etc/logstash/certs/${NODE_NAME}.pkcs8.key"

echo "== 설정 파일 배포 =="
install -o root -g logstash -m 640 "$REPO_DIR/configs/logstash/logstash.yml" /etc/logstash/logstash.yml
install -o root -g logstash -m 640 "$REPO_DIR/configs/logstash/pipelines.yml" /etc/logstash/pipelines.yml
mkdir -p /etc/logstash/conf.d
install -o root -g logstash -m 640 "$REPO_DIR"/configs/logstash/conf.d/*.conf /etc/logstash/conf.d/

# 템플릿(logstash01 기준)을 실제 노드명/IP로 치환
sed -i "s/logstash01/${NODE_NAME}/g; s/10\.9\.88\.4/${NODE_IP}/g" /etc/logstash/logstash.yml
sed -i "s/logstash01/${NODE_NAME}/g" /etc/logstash/conf.d/10-elastic-agent-input.conf

mkdir -p /data/logstash/queue /data/logstash/dead_letter_queue
chown -R logstash:logstash /data/logstash

echo "== Logstash keystore에 ES API 키 저장 =="
/usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash create 2>/dev/null || true
echo ">> ES API 키 값을 '<id>:<api_key>' 형식으로 입력하세요 (docs/03-elasticsearch.md 4.3절)"
/usr/share/logstash/bin/logstash-keystore --path.settings /etc/logstash add ES_API_KEY

systemctl daemon-reload
systemctl enable logstash
systemctl start logstash

echo "기동 확인: systemctl status logstash"
echo "모니터링 API: curl http://${NODE_IP}:9600/_node/stats?pretty"
