# Logstash 설치 (Logstash01 10.9.88.4 / Logstash02 10.9.88.9)

동일한 절차를 두 노드에 각각 반복한다. 두 노드는 동일한 내부/외부 LB 뒤에서 무상태로 병렬 동작하므로 설정은 `node.name`, 인증서 파일명, `api.http.host`만 다르다.

## 1. 사전조건

- [01-prerequisites.md](01-prerequisites.md): `scripts/00-prereqs.sh` (`ROLE=logstash`)로 `/data/logstash` 마운트 완료
- [02-certificates.md](02-certificates.md): `/etc/logstash/certs/{ca.crt,logstash0N.crt,logstash0N.key}` 배포 완료
- [03-elasticsearch.md](03-elasticsearch.md) 4.3절: `logstash_writer` 역할 기반 API 키 발급 완료

## 2. 설치

```bash
# Logstash01
sudo NODE_NAME=logstash01 NODE_IP=10.9.88.4 REPO_DIR=/path/to/nLogtool ./scripts/05-install-logstash.sh

# Logstash02
sudo NODE_NAME=logstash02 NODE_IP=10.9.88.9 REPO_DIR=/path/to/nLogtool ./scripts/05-install-logstash.sh
```

스크립트가 수행하는 작업:

1. `logstash` apt 패키지 설치
2. 인증서 개인키를 PKCS8로 변환 — `elastic_agent` 입력 플러그인은 PKCS8/PEM 키만 지원하므로 `elasticsearch-certutil --pem`이 만든 키를 `openssl pkcs8 -topk8`로 변환한다.
3. `configs/logstash/{logstash.yml,pipelines.yml,conf.d/*.conf}` 배포 후 노드명/IP 치환
4. `/data/logstash/{queue,dead_letter_queue}` 소유권 설정 (영속 큐 + Dead Letter Queue 저장 경로)
5. Logstash keystore에 `ES_API_KEY` 저장 (평문 비밀번호를 conf 파일에 두지 않기 위함)
6. 서비스 활성화/기동

## 3. 파이프라인 구성

- **입력** (`conf.d/10-elastic-agent-input.conf`): `elastic_agent` 플러그인, TCP 5044, TLS 서버 인증. 내부/외부 LB가 TCP 패스스루로 이 포트에 연결을 전달한다.
- **가공** (`conf.d/50-filter.conf`): 현재는 확장 지점만 마련된 빈 필터. `data_stream.dataset` 값으로 분기해 파싱 규칙(grok/mutate 등)을 추가한다. 조직에서 수집할 로그 종류가 정해지면 이 파일에 실제 필터를 채운다.
- **출력** (`conf.d/90-elasticsearch-output.conf`): `elasticsearch` 플러그인, `data_stream => true`로 Elastic Agent가 부여한 원래의 데이터스트림(`logs-*-*` 등) 라우팅을 그대로 유지한 채 Elasticsearch에 기록한다.

## 4. 영속 큐 (Persistent Queue)

`queue.type: persisted`로 설정해 Elasticsearch 장애/네트워크 단절 시에도 두 번째 디스크(`/data/logstash/queue`)에 이벤트를 보존한다. `queue.max_bytes: 20gb`는 100 GB 디스크 중 여유를 두고 설정한 값으로, 처리량에 따라 조정한다. Dead Letter Queue도 활성화되어 있어 Elasticsearch 매핑 오류 등으로 색인에 실패한 이벤트를 `/data/logstash/dead_letter_queue`에서 별도로 확인할 수 있다.

## 5. LB 백엔드 헬스체크

클라우드 매니지드 LB(내부 10.9.88.40, 외부 139.150.86.188)의 백엔드 헬스체크는 TCP 5044(입력 포트) 또는 HTTP `9600/_node`(모니터링 API, 별도 헬스체크 리스너 필요)로 구성한다. Logstash 서비스가 죽으면 5044 포트가 닫히므로 TCP 헬스체크만으로도 장애 노드를 자동 제외할 수 있다.

## 6. 다음 단계

Elastic Agent 배포/enrollment → [06-agent-enrollment.md](06-agent-enrollment.md)
