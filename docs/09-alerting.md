# 장애 전조 감지 알림 (Kibana Alerting)

`logs-*`/`metrics-*`에 이미 수집되고 있는 데이터를 근거로, 장애로 번지기 전에 잡아낼 수 있는 신호를 Kibana Alerting 규칙(Stack Rules)으로 구성한다. 이 규칙들은 Basic(무료) 라이선스에서도 동작한다 — ML 이상탐지처럼 Platinum 라이선스가 필요한 기능은 사용하지 않는다.

## 1. 사전조건

- [04-kibana-fleet-server.md](04-kibana-fleet-server.md): Kibana 접근 가능, `elastic` 계정 준비
- 알림을 받을 채널(Slack/이메일 등) 준비 — 아래 2절에서 Connector로 등록
- 디스크/JVM 힙 관련 규칙(4, 5절)은 대상 정책(Internal-Servers/External-Servers)에 **System** 통합이 켜져 있어야 `metrics-system.*` 데이터가 존재한다(대부분 기본 통합에 포함됨).

## 2. 알림 채널(Connector) 등록

Slack 웹훅 예시. 이메일 등 다른 채널도 `connector_type_id`만 바꿔 동일하게 등록한다.

```bash
KIBANA=https://fleet-kibana:5601
AUTH=(-u elastic:$ELASTIC_PASSWORD)

curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/actions/connector" -d '{
    "name": "ops-slack",
    "connector_type_id": ".slack",
    "config": {},
    "secrets": { "webhookUrl": "https://hooks.slack.com/services/XXX/YYY/ZZZ" }
  }'
# 응답의 "id"를 아래 규칙들의 CONNECTOR_ID로 사용한다.
```

## 3. 규칙 1 — 에러 로그 패턴 급증 (`logs-*`)

`OutOfMemoryError`, `Connection refused`, `too many open files` 등은 장애로 이어지기 전 로그에 먼저 나타나는 대표적인 신호다. Elasticsearch query rule로 5분간 발생 건수를 감시한다.

```bash
curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/alerting/rule" -d '{
    "name": "logs - critical error pattern spike",
    "rule_type_id": ".es-query",
    "consumer": "alerts",
    "schedule": { "interval": "1m" },
    "params": {
      "searchType": "esQuery",
      "index": ["logs-*"],
      "timeField": "@timestamp",
      "esQuery": "{\"query\":{\"query_string\":{\"query\":\"message:(\\\"OutOfMemoryError\\\" OR \\\"Connection refused\\\" OR \\\"too many open files\\\" OR \\\"Cannot allocate memory\\\")\"}}}",
      "size": 100,
      "thresholdComparator": ">",
      "threshold": [5],
      "timeWindowSize": 5,
      "timeWindowUnit": "m"
    },
    "actions": [{
      "id": "<CONNECTOR_ID>",
      "group": "query matched",
      "params": { "message": "최근 5분간 위험 에러 로그 {{context.hits.length}}건 발생. 대상 인덱스 logs-*." }
    }]
  }'
```

## 4. 규칙 2 — 디스크 사용률 임계치 (`metrics-*`)

`Elastic01`의 `/data/elasticsearch`, `Logstash01/02`의 `/data/logstash`(Persistent Queue + Dead Letter Queue)는 가득 차면 각각 색인 중단, 큐 적체/DLQ 폭증으로 이어진다. Index threshold rule로 마운트 사용률을 감시한다.

```bash
curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/alerting/rule" -d '{
    "name": "metrics - data disk usage high",
    "rule_type_id": ".index-threshold",
    "consumer": "alerts",
    "schedule": { "interval": "1m" },
    "params": {
      "index": ["metrics-system.filesystem-*"],
      "timeField": "@timestamp",
      "aggType": "avg",
      "aggField": "system.filesystem.used.pct",
      "filterKuery": "system.filesystem.mount_point : \"/data\"",
      "groupBy": "top",
      "termField": "host.name",
      "termSize": 10,
      "thresholdComparator": ">",
      "threshold": [0.85],
      "timeWindowSize": 5,
      "timeWindowUnit": "m"
    },
    "actions": [{
      "id": "<CONNECTOR_ID>",
      "group": "threshold met",
      "params": { "message": "{{context.group}} 의 /data 디스크 사용률이 85%를 초과했습니다 (현재 {{context.value}})." }
    }]
  }'
```

> 임계치는 1차 경고 85%, 2차(긴급) 95%로 2개 규칙을 나눠 만들고 액션 심각도를 다르게 연결하는 것을 권장한다.

## 5. 규칙 3 — JVM 힙 사용률 임계치 (Elasticsearch/Logstash)

Full GC 빈발/응답 지연의 선행 지표다. 힙 사용률이 지속적으로 높으면 OOM 전 단계로 본다.

```bash
curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/alerting/rule" -d '{
    "name": "metrics - jvm heap usage high",
    "rule_type_id": ".index-threshold",
    "consumer": "alerts",
    "schedule": { "interval": "1m" },
    "params": {
      "index": ["metrics-elasticsearch.stack_monitoring.node_stats-*", "metrics-logstash.node_stats-*"],
      "timeField": "@timestamp",
      "aggType": "avg",
      "aggField": "elasticsearch.node.stats.jvm.mem.heap.used.pct",
      "groupBy": "top",
      "termField": "host.name",
      "termSize": 10,
      "thresholdComparator": ">",
      "threshold": [0.8],
      "timeWindowSize": 10,
      "timeWindowUnit": "m"
    },
    "actions": [{
      "id": "<CONNECTOR_ID>",
      "group": "threshold met",
      "params": { "message": "{{context.group}} 의 JVM 힙 사용률이 10분간 80%를 초과했습니다." }
    }]
  }'
```

> 이 규칙은 Elasticsearch/Logstash 노드 자체의 스택 모니터링 메트릭이 필요하다. 해당 노드의 Elastic Agent 정책에 **Elasticsearch**/**Logstash** 통합(Stack Monitoring 데이터셋)이 추가되어 있어야 `elasticsearch.node.stats.*`, `logstash.node.stats.*` 필드가 존재한다 — 없다면 먼저 Fleet에서 통합을 추가한다.

## 6. 규칙 4 — 로그 유입 중단 감지 (`logs-*`)

평소 로그를 꾸준히 보내던 호스트에서 유입이 끊기는 것은 프로세스 크래시/행(hang)의 전조일 수 있다. "미달(IS BELOW)" 조건으로 감시한다.

```bash
curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/alerting/rule" -d '{
    "name": "logs - ingestion stopped per host",
    "rule_type_id": ".es-query",
    "consumer": "alerts",
    "schedule": { "interval": "5m" },
    "params": {
      "searchType": "esQuery",
      "index": ["logs-*"],
      "timeField": "@timestamp",
      "esQuery": "{\"query\":{\"match_all\":{}}}",
      "size": 0,
      "excludeHitsFromPreviousRun": false,
      "aggType": "count",
      "groupBy": "top",
      "termField": "host.name",
      "termSize": 20,
      "thresholdComparator": "<",
      "threshold": [1],
      "timeWindowSize": 10,
      "timeWindowUnit": "m"
    },
    "actions": [{
      "id": "<CONNECTOR_ID>",
      "group": "query matched",
      "params": { "message": "{{context.group}} 호스트에서 최근 10분간 로그 유입이 없습니다." }
    }]
  }'
```

## 7. 규칙 5 — Logstash 처리 지연/큐 적체

유입 속도가 처리 속도를 앞지르면 Persistent Queue가 쌓이다가 결국 디스크(4절)를 압박한다. 큐 이벤트 수를 직접 감시해 4절보다 먼저 신호를 잡는다.

```bash
curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/alerting/rule" -d '{
    "name": "logstash - persistent queue backlog",
    "rule_type_id": ".index-threshold",
    "consumer": "alerts",
    "schedule": { "interval": "1m" },
    "params": {
      "index": ["metrics-logstash.node_stats-*"],
      "timeField": "@timestamp",
      "aggType": "max",
      "aggField": "logstash.node.stats.pipelines.main.queue.events_count",
      "groupBy": "top",
      "termField": "host.name",
      "termSize": 5,
      "thresholdComparator": ">",
      "threshold": [50000],
      "timeWindowSize": 5,
      "timeWindowUnit": "m"
    },
    "actions": [{
      "id": "<CONNECTOR_ID>",
      "group": "threshold met",
      "params": { "message": "{{context.group}} 의 Logstash 영속 큐 적체가 임계치를 초과했습니다. Elasticsearch 색인 지연 또는 유입 폭증 여부를 확인하세요." }
    }]
  }'
```

## 8. 자동 적용 스크립트

2~7절의 curl 예시를 매번 수동으로 실행하는 대신, 규칙 정의를 `configs/kibana/alerting/*.json`으로 파일화해두고 `scripts/07-apply-alerting.sh`로 한 번에 적용할 수 있다.

```bash
sudo ELASTIC_PASSWORD=<elastic 비밀번호> \
     SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX/YYY/ZZZ \
     REPO_DIR=/path/to/nLogtool \
     ./scripts/07-apply-alerting.sh
```

동작 방식:

1. `00-connector-slack.json`을 기준으로 이름(`ops-slack`)이 같은 커넥터가 있는지 확인 후, 없으면 `SLACK_WEBHOOK_URL`을 채워 생성하고, 있으면 그 ID를 재사용한다.
2. `01-`~`05-*.json`(3~7절 규칙과 1:1 대응) 각각에 대해 이름이 같은 규칙이 있는지 확인해, 있으면 `PUT`으로 갱신하고 없으면 `POST`로 생성한다 — 재실행해도 중복 생성되지 않는다.

임계치를 바꾸고 싶으면 해당 JSON 파일의 `params.threshold` 등을 수정한 뒤 스크립트를 다시 실행하면 된다.

## 9. 우선순위 요약

| 순서 | 규칙 | 잡아내는 장애 유형 | 라이선스 요구사항 |
|---|---|---|---|
| 1 | 디스크 사용률 (4절) | 색인 중단, 큐/DLQ 폭증 | Basic |
| 2 | 에러 로그 패턴 급증 (3절) | OOM, 연결 실패, FD 고갈 | Basic |
| 3 | JVM 힙 사용률 (5절) | GC 압박 → 응답 지연/OOM | Basic (Stack Monitoring 통합 필요) |
| 4 | Logstash 큐 적체 (7절) | 처리 지연 누적 → 디스크 압박 | Basic |
| 5 | 로그 유입 중단 (6절) | 프로세스 크래시/행 | Basic |

임계치(85%, 80%, 5건, 50000건 등)는 예시 값이며, 실제 트래픽 패턴을 1~2주 관찰한 뒤 오탐/미탐 비율을 보고 조정한다.

## 10. 다음 단계

규칙이 안정화되면 ML 이상탐지(Platinum 이상 라이선스)로 확장해 정적 임계치 대신 학습 기반 이상치 탐지를 추가하는 것을 고려한다. 트러블슈팅은 [08-runbook-verification.md](08-runbook-verification.md)를 참고한다.
