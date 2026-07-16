# 보안 요약 — 계정/권한/토큰/방화벽

이 문서는 앞선 문서들에서 발급한 자격증명과 방화벽 규칙을 한 곳에 정리한 참고용 문서다. 실제 값(비밀번호/토큰/키)은 여기 적지 말고 비밀 관리 도구(Vault, 클라우드 Secrets Manager 등)에 보관한다.

## 1. 발급한 계정/역할/토큰 목록

| 항목 | 발급 위치 | 용도 | 저장 위치 |
|---|---|---|---|
| `elastic` 슈퍼유저 비밀번호 | Elastic01, `elasticsearch-reset-password -u elastic` | 최초 설정/비상용 관리자 계정 | 비밀 관리 도구 (평시 로그인용 개별 계정으로 대체 권장, 3절 참고) |
| `elastic/kibana` 서비스 토큰 | Elastic01, `elasticsearch-service-tokens create elastic/kibana` | Kibana → Elasticsearch 인증 | FleetKibana `kibana.keystore` (`elasticsearch.serviceAccountToken`) |
| `elastic/fleet-server` 서비스 토큰 | Elastic01, `elasticsearch-service-tokens create elastic/fleet-server` | Fleet Server → Elasticsearch 인증 | Fleet Server 설치 시 1회성 플래그로 전달(`--fleet-server-service-token`), 이후 elastic-agent 자체 상태에 암호화 저장 |
| `logstash_writer` 역할 + `logstash-writer-key` API 키 | Elastic01, `_security/role` + `_security/api_key` | Logstash → Elasticsearch 데이터 기록(`create_doc`, `auto_configure`만 허용) | Logstash01/02 `logstash.keystore` (`ES_API_KEY`) |
| Fleet enrollment token (정책별) | Kibana Fleet UI/API, 정책당 1개 이상 | Elastic Agent enrollment 시 1회 인증 | 배포 시 CLI 인자로 전달, 이후 저장하지 않음 |

## 2. 인증서/키

| 파일 | 배포 대상 | 비고 |
|---|---|---|
| `ca.crt` | 전 노드 + 모든 수집 대상 서버 | 개인키(`ca.key`)는 인증서 생성 호스트 밖으로 절대 유출하지 않는다 |
| `elastic01.crt/.key` | Elastic01 | http+transport 겸용 |
| `fleet-kibana.crt/.key` | FleetKibana | Kibana HTTPS, Fleet Server HTTPS 겸용 |
| `logstash01.crt/.key`, `logstash02.crt/.key` | 각 Logstash 노드 | `elastic_agent` 입력용, PKCS8 변환본(`*.pkcs8.key`) 별도 보관 |

기본 유효기간 5년 — 만료 전 재발급 일정 관리 필요([02-certificates.md](02-certificates.md) 참고).

## 3. 운영 계정 권장사항

- `elastic` 슈퍼유저는 초기 설정/비상 복구 전용으로만 사용하고, 평시 로그인은 Kibana에서 개별 계정을 만들어 내장 역할(`kibana_admin`, `editor`, `viewer` 등)을 부여한다.
- Fleet 정책/출력 변경 등 운영 작업이 잦다면 `fleet_all` 계열 커스텀 역할을 만들어 최소 권한 원칙을 적용한다.

## 4. 방화벽/보안그룹 요약

전체 표는 [01-prerequisites.md](01-prerequisites.md) 4절 참고. 핵심 원칙:

- Elasticsearch 9200/9300은 **어떤 경우에도 NAT(117.52.83.173)로 노출하지 않는다** — 내부 3개 노드(Kibana/Fleet Server, Logstash01/02)만 접근 가능해야 한다. NAT IP는 SSH 등 관리 목적으로만 사용한다.
- Fleet Server 8220은 외부 랜덤 IP 에이전트를 받아야 하므로 인터넷에 노출이 불가피하다. 대신 enrollment token 노출 관리(용도 종료 시 즉시 폐기)와 Fleet Server 접근 로그 모니터링으로 보완한다.
- Logstash 5044는 LB를 통해서만 도달 가능하도록 하고, LB 자체의 소스 IP 제한(가능하다면)도 함께 건다.
- 모니터링 API(Elasticsearch 관리용 curl, Logstash 9600)는 관리자 대역으로만 제한한다.

## 5. 토큰/키 폐기 예시 (교체 시)

```bash
# 서비스 토큰 폐기
sudo /usr/share/elasticsearch/bin/elasticsearch-service-tokens delete elastic/fleet-server fleet-server-token

# API 키 폐기
curl -k --cacert /etc/elasticsearch/certs/ca.crt -u elastic:$ELASTIC_PASSWORD \
  -X DELETE "https://elastic01:9200/_security/api_key" \
  -H 'Content-Type: application/json' -d '{"ids": ["<api_key_id>"]}'
```

## 6. 다음 단계

전체 구축 검증 → [08-runbook-verification.md](08-runbook-verification.md)
