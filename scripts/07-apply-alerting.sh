#!/usr/bin/env bash
# FleetKibana(10.9.88.61) 또는 Kibana에 curl로 접근 가능한 임의의 호스트에서 실행.
# configs/kibana/alerting/*.json 에 정의된 Slack 커넥터 + Alerting 규칙을 Kibana API로 적용한다.
# 이름 기준으로 존재 여부를 확인해 재실행해도 중복 생성되지 않는다(있으면 갱신, 없으면 생성).
#
# 사전조건:
#  - docs/09-alerting.md
#  - Kibana가 기동 중이고 elastic 슈퍼유저 비밀번호를 알고 있어야 함
#  - Slack Incoming Webhook URL 준비
#
# 사용법 (전체 규칙 적용):
#   sudo ELASTIC_PASSWORD=<비밀번호> \
#        SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ \
#        ./07-apply-alerting.sh
#
# 사용법 (규칙 1개만 테스트 적용, 파일명 또는 파일명 일부로 필터):
#   sudo ELASTIC_PASSWORD=<비밀번호> \
#        SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ \
#        ONLY_RULE=02-disk-usage-high.json \
#        ./07-apply-alerting.sh
set -euo pipefail

KIBANA="${KIBANA:-https://fleet-kibana:5601}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD:?elastic 슈퍼유저 비밀번호를 지정하세요}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:?Slack Incoming Webhook URL을 지정하세요}"
KIBANA_CA="${KIBANA_CA:-/etc/kibana/certs/ca.crt}"
ONLY_RULE="${ONLY_RULE:-}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ALERT_DIR="$REPO_DIR/configs/kibana/alerting"

command -v jq >/dev/null 2>&1 || { apt-get update -y && apt-get install -y jq; }

CURL=(curl -sS -k --cacert "$KIBANA_CA" -u "elastic:${ELASTIC_PASSWORD}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json')

echo "== [1/2] Slack Connector 확인/생성 =="
CONNECTOR_NAME=$(jq -r '.name' "$ALERT_DIR/00-connector-slack.json")
EXISTING_CONNECTOR_ID=$("${CURL[@]}" "$KIBANA/api/actions/connectors" \
  | jq -r --arg n "$CONNECTOR_NAME" '.[] | select(.name==$n) | .id' | head -n1)

if [ -n "$EXISTING_CONNECTOR_ID" ]; then
  CONNECTOR_ID="$EXISTING_CONNECTOR_ID"
  echo "기존 커넥터 재사용: ${CONNECTOR_NAME} (${CONNECTOR_ID})"
else
  CONNECTOR_BODY=$(jq --arg url "$SLACK_WEBHOOK_URL" '.secrets.webhookUrl = $url' "$ALERT_DIR/00-connector-slack.json")
  CONNECTOR_ID=$("${CURL[@]}" -X POST "$KIBANA/api/actions/connector" -d "$CONNECTOR_BODY" | jq -r '.id')
  echo "커넥터 생성: ${CONNECTOR_NAME} (${CONNECTOR_ID})"
fi

echo "== [2/2] Alerting 규칙 적용 (docs/09-alerting.md 3~7절) =="
if [ -n "$ONLY_RULE" ]; then
  RULE_FILES=("$ALERT_DIR"/*"$ONLY_RULE"*)
  echo "ONLY_RULE 지정됨 — 다음 파일만 적용: ${RULE_FILES[*]##*/}"
else
  RULE_FILES=("$ALERT_DIR"/0[1-9]-*.json)
fi

for rule_file in "${RULE_FILES[@]}"; do
  [ -f "$rule_file" ] || { echo "ONLY_RULE=${ONLY_RULE} 에 매칭되는 파일이 없습니다." >&2; exit 1; }
  RULE_NAME=$(jq -r '.name' "$rule_file")
  RULE_BODY=$(jq --arg cid "$CONNECTOR_ID" '.actions[].id = $cid' "$rule_file")

  EXISTING_RULE_ID=$("${CURL[@]}" -G "$KIBANA/api/alerting/rules/_find" \
    --data-urlencode "search_fields=name" --data-urlencode "search=${RULE_NAME}" \
    --data-urlencode "per_page=100" \
    | jq -r --arg n "$RULE_NAME" '.data[] | select(.name==$n) | .id' | head -n1)

  if [ -n "$EXISTING_RULE_ID" ]; then
    echo "기존 규칙 갱신: ${RULE_NAME} (${EXISTING_RULE_ID})"
    UPDATE_BODY=$(echo "$RULE_BODY" | jq '{name, tags: (.tags // []), schedule, params, actions, notify_when: "onActiveAlert"}')
    "${CURL[@]}" -X PUT "$KIBANA/api/alerting/rule/${EXISTING_RULE_ID}" -d "$UPDATE_BODY" >/dev/null
  else
    echo "신규 규칙 생성: ${RULE_NAME}"
    "${CURL[@]}" -X POST "$KIBANA/api/alerting/rule" -d "$RULE_BODY" >/dev/null
  fi
done

echo "완료. Kibana Stack Management > Rules 에서 상태를 확인하세요."
echo "(rule_type_id/params 스키마는 설치된 버전에 따라 다를 수 있으니, 실패 시 응답 메시지와"
echo " https://<kibana>/api/alerting 문서를 함께 확인할 것 — docs/09-alerting.md 참고)"
