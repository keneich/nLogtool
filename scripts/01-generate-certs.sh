#!/usr/bin/env bash
# Elastic01 등 elasticsearch 패키지가 설치된 노드 한 곳에서 1회만 실행한다.
# (elasticsearch-certutil은 elasticsearch 패키지에 포함되어 있으며, 서비스 기동 여부와 무관하게 사용 가능)
#
# 사전조건: apt-get install -y elasticsearch 로 패키지 설치까지만 되어 있고,
#          아직 elasticsearch.yml 보안 설정 / 서비스 기동은 하지 않은 상태
#
# 사용법: sudo ./01-generate-certs.sh /path/to/instances.yml /root/certs
set -euo pipefail

INSTANCES_YML="${1:?instances.yml 경로를 지정하세요}"
OUT_DIR="${2:-/root/certs}"
CERTUTIL=/usr/share/elasticsearch/bin/elasticsearch-certutil

# elasticsearch-certutil은 내부적으로 ES_HOME(/usr/share/elasticsearch)으로 cd한 뒤 파일을 열기 때문에
# 상대경로를 넘기면 엉뚱한 위치에서 파일을 찾는다. 절대경로로 변환해서 넘긴다.
INSTANCES_YML="$(readlink -f "$INSTANCES_YML")"
mkdir -p "$OUT_DIR"
OUT_DIR="$(readlink -f "$OUT_DIR")"
cd "$OUT_DIR"

echo "== CA 생성 (PEM) =="
"$CERTUTIL" ca --pem --out "$OUT_DIR/ca.zip" --silent
unzip -o ca.zip -d .
# -> $OUT_DIR/ca/ca.crt, $OUT_DIR/ca/ca.key

echo "== 노드별 인증서 생성 (PEM) =="
"$CERTUTIL" cert --pem \
  --ca-cert "$OUT_DIR/ca/ca.crt" \
  --ca-key  "$OUT_DIR/ca/ca.key" \
  --in "$INSTANCES_YML" \
  --out "$OUT_DIR/certs-bundle.zip" \
  --silent
unzip -o certs-bundle.zip -d certs
# -> $OUT_DIR/certs/elastic01/{elastic01.crt,elastic01.key}
#    $OUT_DIR/certs/fleet-kibana/{fleet-kibana.crt,fleet-kibana.key}
#    $OUT_DIR/certs/logstash01/{logstash01.crt,logstash01.key}
#    $OUT_DIR/certs/logstash02/{logstash02.crt,logstash02.key}

chmod 700 "$OUT_DIR/ca"
chmod 600 "$OUT_DIR/ca/ca.key"

echo "완료. 아래 파일들을 각 노드로 배포하세요 (docs/02-certificates.md 4절 참고):"
echo "  CA 인증서(전 노드 공통): $OUT_DIR/ca/ca.crt"
echo "  노드별 인증서/키       : $OUT_DIR/certs/<node-name>/"
