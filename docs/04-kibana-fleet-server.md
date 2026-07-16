# Kibana + Fleet Server 설치/설정 (FleetKibana, 10.9.88.61 / NAT 139.150.84.70)

## 1. 사전조건

- [01-prerequisites.md](01-prerequisites.md): `scripts/00-prereqs.sh` (`ROLE=fleet-kibana`) 완료
- [02-certificates.md](02-certificates.md): `/etc/kibana/certs/`, `/etc/fleet-server/certs/` 배포 완료
- [03-elasticsearch.md](03-elasticsearch.md): `elastic/kibana` 서비스 토큰, `elastic/fleet-server` 서비스 토큰 발급 완료

## 2. Kibana 설치

```bash
sudo REPO_DIR=/path/to/nLogtool ./scripts/03-install-kibana.sh
```

실행 중 `elastic/kibana` 서비스 토큰 입력을 요구한다. 이후 Fleet 등이 사용하는 encrypted saved objects용 암호화 키(`xpack.encryptedSavedObjects.encryptionKey` 등 3종)를 자동으로 생성해 keystore에 저장한다 — 이 키가 없으면 Fleet Server 설치 단계에서 `Agent binary source needs encrypted saved object api key to be set` 오류가 발생한다.

기동 후 `https://10.9.88.61:5601` (또는 `https://139.150.84.70:5601`)로 접속해 `elastic` 슈퍼유저로 로그인한다.

## 3. Fleet Server 정책/출력 사전 구성 (Kibana Fleet UI)

Fleet Server를 설치하기 전에, Fleet Server 자신이 사용할 정책과 관리 대상 에이전트가 사용할 출력/정책을 먼저 만들어 둔다. 이 리소스들은 Elasticsearch에 상태로 저장되는 Fleet 고유 객체라 Kibana UI(또는 Fleet API)로 관리하는 것이 정석이다.

### 3.1 Fleet Server Policy

Kibana 좌측 메뉴 **Fleet → Agent policies → Create agent policy**에서 `Fleet Server Policy` 생성 (또는 Fleet 화면에 처음 진입해 **Add Fleet Server**를 클릭하면 자동으로 생성되며, 이때 화면에 설치 명령이 함께 표시된다 — 그 명령을 그대로 써도 되고, `scripts/04-install-fleet-server.sh`를 써도 된다). 생성 후 정책 상세 화면 URL(`.../policies/<policy-id>`)에서 정책 ID를 확인해 둔다.

### 3.2 출력(Output) 2개 생성

**Fleet → Settings → Outputs → Add output**

| 이름 | Type | Hosts | 비고 |
|---|---|---|---|
| Logstash-Internal | Logstash | `10.9.88.40:5044` | 내부(10.0.0.0/8) 에이전트용 |
| Logstash-External | Logstash | `139.150.86.188:5044` | 외부/랜덤 공인 IP 에이전트용 |

각 출력의 SSL 설정에 `configs/elasticsearch` 인증서 생성 시 만든 CA 인증서(`ca.crt`)를 **Server SSL certificate authorities**에 붙여넣는다. Logstash 쪽은 Logstash01/02가 각자 자신의 인증서로 TLS를 종료하므로, 에이전트(출력) 쪽에는 클라이언트 인증서가 필수는 아니다(서버 인증서 신뢰만 필요). 상호 TLS(mTLS)까지 강제하려면 에이전트 출력에도 CA로 서명한 클라이언트 인증서를 발급해 추가하면 된다(선택 사항, 이 가이드에서는 서버 인증 TLS만 구성).

### 3.3 Fleet Server hosts 등록

**Fleet → Settings → Fleet Server hosts → Add**

```
이름: Fleet Server (internal+external)
Host URLs:
  - https://10.9.88.61:8220
  - https://139.150.84.70:8220
```

두 URL을 함께 등록해두면 에이전트 정책에 "이 Fleet Server 호스트 목록"으로 배포되어, 에이전트가 접속 실패 시 다른 URL로 재시도한다. 다만 내부 에이전트가 굳이 NAT를 거치지 않도록, 실제 배포 시에는 각 에이전트 설치 명령의 `--url` 값을 망 구분에 맞게 명시적으로 지정할 것을 권장한다([06-agent-enrollment.md](06-agent-enrollment.md) 참고).

### 3.4 에이전트 정책 2개 생성

**Fleet → Agent policies → Create agent policy**

| 정책 이름 | 용도 | 데이터 출력 |
|---|---|---|
| Internal-Servers | 10.0.0.0/8 내부 수집 대상 | Logstash-Internal |
| External-Servers | 랜덤 공인 IP 수집 대상 | Logstash-External |

각 정책 생성 후 **Settings 탭 → Output for integrations**을 위 표에 맞게 지정한다. 필요한 통합(Integration, 예: System, Custom Logs 등)은 이 두 정책에 각각 추가한다.

## 4. Fleet Server 설치

```bash
sudo AGENT_VERSION=9.x.y \
     FLEET_SERVER_POLICY_ID=<3.1에서 확인한 정책 ID> \
     FLEET_SERVICE_TOKEN=<elastic/fleet-server 서비스 토큰> \
     ./scripts/04-install-fleet-server.sh
```

`AGENT_VERSION`은 [Elastic Agent 다운로드 페이지](https://www.elastic.co/downloads/elastic-agent)에서 설치한 ES/Kibana와 동일한 9.x 버전을 확인해 지정한다.

설치 후 Kibana **Fleet → Agents**에서 Fleet Server 에이전트가 `Healthy` 상태인지 확인한다.

## 5. 부록 — Fleet API curl 예시 (자동화가 필요한 경우)

UI 대신 스크립트로 재현하고 싶다면 아래 curl 예시를 참고한다(정확한 스키마는 설치된 버전의 `https://<kibana>/api/fleet` 문서를 함께 확인할 것). 모든 요청에 `kbn-xsrf` 헤더와 `elastic` 인증이 필요하다.

```bash
KIBANA=https://fleet-kibana:5601
AUTH=(-u elastic:$ELASTIC_PASSWORD)
CACERT=--cacert; CA=/etc/kibana/certs/ca.crt

# 출력 생성 (Logstash-Internal 예시)
curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/fleet/outputs" -d '{
    "name": "Logstash-Internal",
    "type": "logstash",
    "hosts": ["10.9.88.40:5044"],
    "is_default": false,
    "is_default_monitoring": false,
    "ssl": { "certificate_authorities": ["<ca.crt 내용>"] }
  }'

# 에이전트 정책 생성
curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/fleet/agent_policies" -d '{
    "name": "Internal-Servers",
    "namespace": "default",
    "monitoring_enabled": ["logs", "metrics"]
  }'

# Fleet Server host 등록
curl -k "${AUTH[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "$KIBANA/api/fleet/fleet_server_hosts" -d '{
    "name": "Fleet Server (internal+external)",
    "host_urls": ["https://10.9.88.61:8220", "https://139.150.84.70:8220"],
    "is_default": true
  }'
```

> `ssl.certificate_authorities`는 파일 경로가 아니라 PEM 내용을 문자열로 전달해야 한다(kibana.yml preconfiguration과 동일한 제약). 자동화 스크립트에서는 `$(cat ca.crt)`로 치환한다.

## 6. 다음 단계

Logstash 설치 → [05-logstash.md](05-logstash.md)
