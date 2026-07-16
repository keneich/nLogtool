# Elasticsearch 설치 (Elastic01, 단일 노드)

## 1. 사전조건

- [01-prerequisites.md](01-prerequisites.md): `scripts/00-prereqs.sh` (`ROLE=elastic01`)로 디스크(`/data/elasticsearch`), hosts, `vm.max_map_count` 준비 완료
- [02-certificates.md](02-certificates.md): `/etc/elasticsearch/certs/{ca.crt,elastic01.crt,elastic01.key}` 배포 완료

## 2. 설치

```bash
sudo REPO_DIR=/path/to/nLogtool ./scripts/02-install-elasticsearch.sh
```

이 스크립트는 다음을 수행한다.

1. `elasticsearch` apt 패키지 설치 (서비스 자동 기동 없음)
2. `configs/elasticsearch/elasticsearch.yml` 배포 — 단일 노드(`discovery.type: single-node`), 보안 자동구성 비활성화(`xpack.security.autoconfiguration.enabled: false`) 후 자체 서명 CA 기반 TLS를 http/transport 양쪽에 수동 지정
3. `configs/elasticsearch/jvm.options.d/heap.options` 배포 — `-Xms4g -Xmx4g` (8 GB RAM의 50%)
4. `/data/elasticsearch` 소유권을 `elasticsearch` 사용자로 변경
5. 서비스 활성화 및 기동

## 3. 기동 확인

```bash
sudo systemctl status elasticsearch
curl -k --cacert /etc/elasticsearch/certs/ca.crt https://elastic01:9200
# -> 이 시점에는 아직 elastic 비밀번호가 없어 401이 정상 (보안은 켜져 있음을 의미)
```

## 4. 최초 계정/토큰 발급

보안 자동구성을 껐기 때문에 `elastic` 슈퍼유저 비밀번호를 수동으로 생성해야 한다.

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic --auto
# 출력되는 비밀번호를 안전한 곳(비밀 관리 도구)에 저장 — 이하 예시에서 $ELASTIC_PASSWORD로 표기
```

### 4.1 Kibana용 서비스 토큰 (`elastic/kibana`)

비밀번호 대신 만료 없는 서비스 토큰을 사용해 kibana_system 계정 비밀번호 관리를 없앤다.

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana kibana-token
# 출력되는 토큰 값을 FleetKibana 노드의 kibana keystore(elasticsearch.serviceAccountToken)에 저장 (04-kibana-fleet-server.md)
```

### 4.2 Fleet Server용 서비스 토큰

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/fleet-server fleet-server-token
# 출력되는 토큰 값을 FleetKibana 노드의 elastic-agent(Fleet Server) 설치 시 사용 (04-kibana-fleet-server.md)
```

> `elasticsearch-service-tokens create`가 처음 실행되면 `/etc/elasticsearch/service_tokens` 파일이 새로 생성된다. 이 파일을 `elasticsearch` 프로세스가 읽을 수 있어야 서비스 토큰 인증이 동작하므로, 소유권을 확인해둔다.
> ```bash
> ls -la /etc/elasticsearch/service_tokens
> sudo chown root:elasticsearch /etc/elasticsearch/service_tokens
> sudo chmod 660 /etc/elasticsearch/service_tokens
> ```
> 권한이 잘못되어 있으면 Kibana/Fleet Server 쪽에서 `failed to authenticate service account` 오류가 발생한다.

### 4.3 Logstash 출력 전용 역할 + API 키

Logstash가 Elasticsearch에 데이터스트림(`logs-*-*`, `metrics-*-*`, `traces-*-*`) 문서를 쓸 수 있는 최소 권한 역할을 만들고, 이 역할로 API 키를 발급한다. Elastic Agent 통합(integration)이 이미 인덱스 템플릿/데이터스트림을 생성하므로 Logstash에는 문서 생성 권한만 부여한다.

```bash
curl -k --cacert /etc/elasticsearch/certs/ca.crt \
  -u elastic:$ELASTIC_PASSWORD \
  -X POST "https://elastic01:9200/_security/role/logstash_writer" \
  -H 'Content-Type: application/json' -d '{
  "cluster": ["monitor"],
  "indices": [
    {
      "names": ["logs-*-*", "metrics-*-*", "traces-*-*"],
      "privileges": ["auto_configure", "create_doc"]
    }
  ]
}'

curl -k --cacert /etc/elasticsearch/certs/ca.crt \
  -u elastic:$ELASTIC_PASSWORD \
  -X POST "https://elastic01:9200/_security/api_key" \
  -H 'Content-Type: application/json' -d '{
  "name": "logstash-writer-key",
  "role_descriptors": {
    "logstash_writer": {
      "cluster": ["monitor"],
      "indices": [
        {
          "names": ["logs-*-*", "metrics-*-*", "traces-*-*"],
          "privileges": ["auto_configure", "create_doc"]
        }
      ]
    }
  }
}'
# 응답의 "id"와 "api_key"를 "<id>:<api_key>" 형태로 합쳐 Logstash keystore에 저장 (05-logstash.md)
```

발급한 계정/토큰/키 목록은 [07-security-hardening.md](07-security-hardening.md)에 정리한다.

## 5. 다음 단계

Kibana + Fleet Server 설치 → [04-kibana-fleet-server.md](04-kibana-fleet-server.md)
