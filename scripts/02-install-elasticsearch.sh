#!/usr/bin/env bash
# Elastic01 (10.9.88.2) 전용.
# 사전조건:
#  - scripts/00-prereqs.sh ROLE=elastic01 실행 완료 (/data/elasticsearch 마운트 등)
#  - docs/02-certificates.md 절차로 /etc/elasticsearch/certs/{ca.crt,elastic01.crt,elastic01.key} 배포 완료
#  - 이 저장소(nLogtool)를 이 노드에 복사해 둔 상태 (기본값: 이 스크립트 상위 디렉터리를 저장소 루트로 간주)
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

apt-get update -y
apt-get install -y elasticsearch   # 이 시점에는 서비스가 자동 기동되지 않음 (Debian 패키지 기본 동작)

install -o root -g elasticsearch -m 640 "$REPO_DIR/configs/elasticsearch/elasticsearch.yml" /etc/elasticsearch/elasticsearch.yml
mkdir -p /etc/elasticsearch/jvm.options.d
install -o root -g elasticsearch -m 640 "$REPO_DIR/configs/elasticsearch/jvm.options.d/heap.options" /etc/elasticsearch/jvm.options.d/heap.options

chown -R elasticsearch:elasticsearch /data/elasticsearch

systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch

echo "== 기동 확인 =="
systemctl --no-pager status elasticsearch || true
echo
echo "다음 단계(계정/토큰 발급)는 docs/03-elasticsearch.md 를 참고하세요."
