#!/usr/bin/env bash
# FleetKibana (10.9.88.61) 전용 - Kibana 설치
# 사전조건:
#  - scripts/00-prereqs.sh ROLE=fleet-kibana 실행 완료
#  - docs/02-certificates.md 절차로 /etc/kibana/certs/{ca.crt,fleet-kibana.crt,fleet-kibana.key} 배포 완료
#  - docs/03-elasticsearch.md 4.1절에서 elastic/kibana 서비스 토큰 발급 완료
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

apt-get update -y
apt-get install -y kibana openssl

install -o root -g kibana -m 640 "$REPO_DIR/configs/kibana/kibana.yml" /etc/kibana/kibana.yml

KEYSTORE_BIN=/usr/share/kibana/bin/kibana-keystore
# 참고: kibana-keystore 하위 명령에는 --allow-root 옵션이 없다 (bin/kibana 서버 실행 파일 전용 옵션).
"$KEYSTORE_BIN" create 2>/dev/null || true

echo ">> elastic/kibana 서비스 토큰 값을 입력하세요 (docs/03-elasticsearch.md 4.1절 출력값)"
"$KEYSTORE_BIN" add elasticsearch.serviceAccountToken

echo "== Fleet 등 encrypted saved objects에 필요한 암호화 키 자동 생성 =="
# 이 키가 없으면 Fleet 초기화가 "Agent binary source needs encrypted saved object api key to be set" 오류로 실패한다.
for KEY in xpack.encryptedSavedObjects.encryptionKey xpack.security.encryptionKey xpack.reporting.encryptionKey; do
  if ! "$KEYSTORE_BIN" list | grep -qx "$KEY"; then
    printf '%s' "$(openssl rand -hex 32)" | "$KEYSTORE_BIN" add "$KEY" --stdin
  fi
done

chown kibana:kibana /etc/kibana/kibana.keystore

systemctl daemon-reload
systemctl enable kibana
systemctl start kibana

echo "기동 확인: systemctl status kibana"
echo "접속 확인: https://10.9.88.61:5601 (또는 https://139.150.84.70:5601)"
echo "다음 단계(Fleet Server 설치, Fleet 출력/정책 구성)는 docs/04-kibana-fleet-server.md 참고"
