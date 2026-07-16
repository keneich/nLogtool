# 검증 절차 및 트러블슈팅

## 1. 서비스 기동 확인 (각 노드)

```bash
# Elastic01
sudo systemctl status elasticsearch
curl -k --cacert /etc/elasticsearch/certs/ca.crt -u elastic:$ELASTIC_PASSWORD https://elastic01:9200

# FleetKibana
sudo systemctl status kibana
sudo systemctl status elastic-agent   # Fleet Server 프로세스

# Logstash01 / Logstash02
sudo systemctl status logstash
curl http://<node-ip>:9600/_node/stats?pretty
```

## 2. Fleet Server 상태 확인

Kibana **Fleet → Agents**에서 Fleet Server 에이전트가 `Healthy`인지 확인한다. `Unhealthy`/`Offline`이면:

```bash
sudo journalctl -u elastic-agent -n 200 --no-pager
sudo cat /opt/Elastic/Agent/data/elastic-agent-*/logs/elastic-agent-*.ndjson | tail -n 50
```

흔한 원인: `--fleet-server-es-ca` 경로 오타, `elastic/fleet-server` 서비스 토큰 만료/오타, 8220 포트 방화벽 차단.

## 3. 테스트 에이전트 1대 등록 (내부 정책)

```bash
sudo FLEET_URL=https://10.9.88.61:8220 \
     ENROLLMENT_TOKEN=<Internal-Servers 토큰> \
     AGENT_VERSION=9.x.y \
     ./scripts/06-enroll-agent.sh
```

Kibana **Fleet → Agents**에서 새 호스트가 `Healthy`로 표시되는지 확인한다.

## 4. 데이터 평면 확인 (Agent → Logstash → Elasticsearch)

### 4.1 Logstash 수신 확인

```bash
curl -s http://<logstash-ip>:9600/_node/stats/pipelines?pretty | grep -A5 '"events"'
```

`in`/`out` 카운트가 올라가는지 확인한다. 두 대 중 어느 쪽이 받는지는 LB 라운드로빈에 따라 달라질 수 있으므로 두 노드 모두 확인한다.

### 4.2 Kibana Discover 확인

**Kibana → Discover**에서 `logs-*` 데이터뷰(또는 통합에서 사용한 데이터셋)에 테스트 에이전트가 보낸 이벤트가 도착했는지 확인한다.

### 4.3 색인 실패 확인 (Dead Letter Queue)

```bash
sudo ls -la /data/logstash/dead_letter_queue/main/
```

파일이 쌓이고 있다면 Elasticsearch 매핑 충돌/권한 문제이니 Logstash 로그(`/var/log/logstash/logstash-plain.log`)를 함께 확인한다.

## 5. 제어 평면 경로별 검증

| 경로 | 확인 방법 |
|---|---|
| 내부 에이전트 → Fleet Server(10.9.88.61:8220) | 3절 테스트 에이전트가 Healthy로 표시되는지 |
| 내부 에이전트 → Logstash(내부 LB 10.9.88.40:5044) | 4.1절 파이프라인 이벤트 카운트 |
| 외부 에이전트 → Fleet Server(NAT 139.150.84.70:8220) | 랜덤 공인 IP 서버(또는 시뮬레이션 환경)에서 `FLEET_URL=https://139.150.84.70:8220`으로 6절 스크립트 실행 후 Healthy 확인 |
| 외부 에이전트 → Logstash(외부 LB 139.150.86.188:5044) | 위 외부 에이전트의 이벤트가 4.1/4.2절에서 확인되는지 |

## 6. TLS 트러블슈팅

```bash
# 인증서 SAN/체인 확인
openssl s_client -connect logstash01:5044 -CAfile /etc/logstash/certs/ca.crt -showcerts </dev/null
openssl x509 -in /etc/logstash/certs/logstash01.crt -noout -text | grep -A2 "Subject Alternative Name"
```

`hostname mismatch` 류의 오류가 나면 접속에 사용한 주소(LB IP 등)가 인증서 SAN에 포함되어 있는지 `configs/elasticsearch/instances.yml`을 다시 확인한다.

## 7. 흔한 오류 정리

| 증상 | 원인 후보 | 확인 위치 |
|---|---|---|
| Elastic Agent enroll 실패 (`x509: certificate signed by unknown authority`) | 대상 서버에 `ca.crt` 미배포/경로 오류 | [06-agent-enrollment.md](06-agent-enrollment.md) 2절 |
| Elastic Agent enroll 실패 (`invalid enrollment token`) | 토큰 오타/만료/다른 정책 것 사용 | Kibana Fleet → Agent policies → Enrollment tokens |
| Fleet Server `timed out waiting for Fleet Server to start` | `--install-servers` 누락(9.0+) 또는 서비스 토큰/ES 연결 오류 | [04-kibana-fleet-server.md](04-kibana-fleet-server.md) 4절 |
| Logstash가 이벤트를 못 받음 | LB 백엔드 헬스체크 실패, 보안그룹 5044 차단 | [01-prerequisites.md](01-prerequisites.md) 4절, LB 콘솔 |
| Logstash → ES 색인 실패 (403) | API 키 권한 부족 | [03-elasticsearch.md](03-elasticsearch.md) 4.3절 role 정의 재확인 |
| Kibana 로그인 후 Fleet 메뉴에서 오류 | `xpack.fleet.enabled` 누락 또는 `elastic/kibana` 토큰 오류 | `configs/kibana/kibana.yml`, kibana 로그 |
