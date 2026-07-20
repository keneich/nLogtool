# 설치 진행 기록 (Install Total)

Kibana 로그인 완료 시점까지 각 서버별로 실제 진행한 작업을 정리한 기록. 앞으로 이어서 작업할 때 이 파일부터 보고 어디까지 됐는지 확인한다. 일반 설치 절차/이유는 `docs/00-08` 참고, 이 파일은 "실제로 뭘 했고 지금 어디까지 됐는지"만 다룬다.

## 진행 상태 요약

| 노드 | 사전준비 | 인증서 배포 | 서비스 설치 | 계정/토큰 발급 | 비고 |
|---|---|---|---|---|---|
| Elastic01 (10.9.88.2) | 완료 | 완료 | 완료 (Elasticsearch) | 완료 | |
| FleetKibana (10.9.88.61) | 완료 | 완료 | 완료 (Kibana + Fleet Server) | 완료 | |
| Logstash01 (10.9.88.4) | 완료 | 완료 | 완료 | 완료 | |
| Logstash02 (10.9.88.9) | 완료 | 완료 | 완료 | 완료 | |
| 수집 대상 에이전트 | - | - | 진행 중 (3대 완료: 10.9.88.12, 114.108.154.59, 114.108.154.60) | - | 나머지 대상 서버는 동일 절차 반복 |

**라이선스**: Basic → 2026-07-20 Trial(Platinum 상당) 시작. 정책별 출력(Output for integrations/monitoring) 커스터마이징이 Basic에서 막혀있어 트라이얼로 전환. **구매 계획 없음 — 2026-08-19(30일 후) 만료 전 단일 출력 구조로 전환할지 재검토 필요.**

## 1. 전 노드 공통 사전준비

4개 노드 전부에서 실행 완료.

```bash
sudo ROLE=elastic01    ./scripts/00-prereqs.sh   # Elastic01
sudo ROLE=fleet-kibana ./scripts/00-prereqs.sh   # FleetKibana
sudo ROLE=logstash     ./scripts/00-prereqs.sh   # Logstash01
sudo ROLE=logstash     ./scripts/00-prereqs.sh   # Logstash02
```

- 디스크 마운트는 수동으로 미리 처리해서 스크립트에서 제외함 (`scripts/00-prereqs.sh` 참고)

## 2. 인증서 생성/배포

Elastic01에서 생성 후 4개 노드에 배포 완료.

```bash
sudo apt-get install -y elasticsearch unzip
sudo ./scripts/01-generate-certs.sh "$(pwd)/configs/elasticsearch/instances.yml" /root/certs
```

- **겪은 이슈**: 처음에 상대경로로 `instances.yml`을 넘겼다가 `elasticsearch-certutil`이 내부적으로 `/usr/share/elasticsearch`로 이동한 뒤 파일을 찾아서 `NoSuchFileException` 발생 → 절대경로로 재실행해서 해결. 스크립트 자체도 `readlink -f`로 자동 절대경로 변환하도록 수정 완료 (커밋 `50da9eb`).

배포 결과:
- Elastic01: `/etc/elasticsearch/certs/{ca.crt,elastic01.crt,elastic01.key}`
- FleetKibana: `/etc/kibana/certs/`, `/etc/fleet-server/certs/` (동일 파일 세트: `ca.crt,fleet-kibana.crt,fleet-kibana.key`)
- Logstash01: `/etc/logstash/certs/{ca.crt,logstash01.crt,logstash01.key}`
- Logstash02: `/etc/logstash/certs/{ca.crt,logstash02.crt,logstash02.key}`

## 3. Elastic01 — Elasticsearch

```bash
sudo ./scripts/02-install-elasticsearch.sh
```

정상 기동 확인 완료. 이어서 계정/토큰 발급 완료 (실제 값은 비밀 관리 도구에 보관, 이 파일에는 기록하지 않음):

- `elastic` 슈퍼유저 비밀번호 (`elasticsearch-reset-password -u elastic --auto`)
- `elastic/kibana` 서비스 토큰 (`kibana-token`)
- `elastic/fleet-server` 서비스 토큰 (Kibana Fleet Server 설치 마법사에서 자동 발급받은 토큰을 대신 사용하기로 함 — 아래 4절 참고)
- `logstash_writer` 역할 + `logstash-writer-key` API 키

- **겪은 이슈**: `/etc/elasticsearch/service_tokens` 파일이 root 소유라 Elasticsearch 프로세스가 못 읽어서 Kibana 쪽에서 `failed to authenticate service account` 오류 발생 → `chown root:elasticsearch` + `chmod 660`으로 해결. (`docs/03-elasticsearch.md` 4.2절에 반영)

## 4. FleetKibana — Kibana

```bash
sudo ./scripts/03-install-kibana.sh
```

**겪은 이슈 2건 (둘 다 스크립트/문서에 반영 완료):**

1. `kibana-keystore create --allow-root` → `--allow-root`는 존재하지 않는 옵션(에러). 옵션 제거.
2. Fleet 초기화 시 `Agent binary source needs encrypted saved object api key to be set` 오류 → `xpack.encryptedSavedObjects.encryptionKey` 등 암호화 키 3종이 없어서 발생. 지금 노드는 `kibana-encryption-keys generate`로 값을 만들어 `/etc/kibana/kibana.yml`에 직접 추가해서 해결함. (이후 버전의 `scripts/03-install-kibana.sh`는 이 키들을 keystore에 자동 생성하도록 고쳐놨음 — 커밋 `c9fa491`, 다음에 새로 설치하는 노드는 수동 조치 불필요)

**결과**: `https://10.9.88.61:5601` 접속 및 `elastic` 계정 로그인 완료.

## 5. FleetKibana — Fleet Server 설치

"Add Fleet Server" 마법사가 자동 생성한 정책 ID(`fleet-server-policy`)와 서비스 토큰으로 진행.

```bash
sudo AGENT_VERSION=9.4.3 \
     FLEET_SERVER_POLICY_ID=fleet-server-policy \
     FLEET_SERVICE_TOKEN=<마법사에서 받은 토큰> \
     ./scripts/04-install-fleet-server.sh
```

- **겪은 이슈 1**: 이전 실패한 설치 잔재가 `/opt/Elastic/Agent`에 남아있어 `Error: already installed` 발생 → `sudo /opt/Elastic/Agent/elastic-agent uninstall --force` 로 제거 후 재설치해서 해결.
- **겪은 이슈 2**: Fleet Server 자체는 `HEALTHY`였지만, 에이전트 모니터링 컴포넌트(`beat/metrics-monitoring` 등)가 `127.0.0.1:9200` 접속 실패로 `DEGRADED`. 원인은 Fleet의 **기본(default) "Elasticsearch" 출력**이 초기화 시 `http://localhost:9200`으로 자동 생성된 것 — Kibana 자신의 `kibana.yml` 설정과는 별개인 Fleet 전용 saved object라 UI에서 별도로 고쳐야 함. **Fleet → Settings → Outputs → `default` → Hosts를 `https://elastic01:9200`으로 수정**하고 CA 인증서(`ca.crt`) 등록해서 해결.

결과: Fleet Server 에이전트 `HEALTHY` / `Connected` 확인 완료.

## 6. Fleet 출력/정책 구성

`docs/04-kibana-fleet-server.md` 3.2~3.4절 그대로 진행.

- Fleet → Settings → Outputs: `Logstash-Internal` (`10.9.88.40:5044`), `Logstash-External` (`139.150.86.188:5044`) 생성
- Fleet → Settings → Fleet Server hosts: `https://10.9.88.61:8220`, `https://139.150.84.70:8220` 등록 확인
- Fleet → Agent policies: `Internal-Servers`(출력=Logstash-Internal), `External-Servers`(출력=Logstash-External) 생성, 각 정책 Settings 탭에서 Output for integrations 지정

- **겪은 이슈 1 — Basic 라이선스 제약**: 정책의 "Output for integrations" 드롭다운이 비활성화되어 선택 불가. 원인은 **정책별 출력 커스터마이징이 Platinum 이상 구독 기능**이라 Basic에서 막혀있는 것. 운영 환경이 아니라 구매 계획이 없어서, **Stack Management → License Management → Start trial**로 30일 트라이얼(2026-07-20 시작, 2026-08-19 만료) 전환 후 진행하기로 결정. **30일 만료 전에 단일 출력 구조 전환 여부를 다시 판단해야 함** (외부 에이전트가 내부 LB `10.9.88.40`에 도달 불가하므로, 단일화하려면 외부 LB 공인 IP로 내부 에이전트도 나갈 수 있는지 네트워크 확인 필요 — 아직 미확인).
- **겪은 이슈 2 — Client SSL 필드 오설정**: `Logstash-Internal`/`Logstash-External` 출력 설정 시 "Server SSL certificate authorities"에 넣어야 할 CA 인증서(`ca.crt`)를 실수로 "Client SSL certificate"/"Client SSL certificate key"에도 잘못 붙여넣음 → 수집 대상 에이전트에서 `tls: found a certificate rather than a key in the PEM for the private key` 에러로 로그 출력 `FAILED`. UI에서는 한 번 저장된 client cert/key 쌍을 완전히 지우는 게 안 되고(교체 아니면 취소만 가능) **Fleet API를 curl로 직접 호출**(`PUT /api/fleet/outputs/<id>`, ssl 객체에 `certificate_authorities`만 넣고 `certificate`/`key` 생략)해서 두 출력 모두 client cert/key 제거로 해결. (`docs/04-kibana-fleet-server.md` 5절 curl 예시 참고)

## 7. Logstash01/02 설치

```bash
# Logstash01
sudo NODE_NAME=logstash01 NODE_IP=10.9.88.4 REPO_DIR=$(pwd) ./scripts/05-install-logstash.sh
# Logstash02
sudo NODE_NAME=logstash02 NODE_IP=10.9.88.9 REPO_DIR=$(pwd) ./scripts/05-install-logstash.sh
```

- keystore 생성 시 비밀번호 프롬프트는 `y`(비밀번호 없이 진행, 파일 권한만으로 보호하는 기존 방식과 동일).
- `ES_API_KEY` 입력 시 **`<id>:<api_key>` 콜론 포함 전체 값**을 넣어야 함 — `id`만 넣으면 인증 실패. 잘못 넣었을 경우 `logstash-keystore remove ES_API_KEY` 후 재입력 + `systemctl restart logstash` 필요(keystore 값은 기동 시점에만 로드됨).
- 두 노드 모두 정상 기동, ES 연결/파이프라인 시작 로그 확인 완료.

### LB 헬스체크 이슈

내부 LB(`10.9.88.40:5044`) 연결이 타임아웃되는 문제 발생 — Logstash 자체(`10.9.88.4`, `10.9.88.9`)는 직접 연결 정상이었음. **원인은 방화벽 허용 정책 미비**, 클라우드 콘솔에서 방화벽 정책 수정 후 내부/외부 LB 둘 다 연결 확인 완료.

## 8. 수집 대상 서버 Elastic Agent enrollment (진행 중)

첫 테스트 대상: `10.9.88.12` (내부망, `Internal-Servers` 정책)

```bash
sudo mkdir -p /etc/elastic-stack-ca
sudo scp root@<cert-host>:/root/certs/ca/ca.crt /etc/elastic-stack-ca/ca.crt

sudo FLEET_URL=https://10.9.88.61:8220 \
     ENROLLMENT_TOKEN=<Fleet Add agent 화면에서 발급받은 토큰> \
     AGENT_VERSION=9.4.3 \
     ./scripts/06-enroll-agent.sh
```

- **겪은 이슈**: enroll 직후 모니터링 컴포넌트가 `lookup elastic01 on 10.9.88.8:53: no such host`로 실패. 핵심 인프라 4개 노드와 달리 수집 대상 서버는 `/etc/hosts`에 `elastic01`이 없어 DNS 해석 실패 — 앞으로 늘어날 모든 수집 대상 서버마다 `/etc/hosts`를 추가하는 건 비현실적이므로, **Fleet의 `default` 출력 Hosts 값을 `https://elastic01:9200`에서 `https://10.9.88.2:9200`(IP)으로 변경**해서 근본 해결 (`elastic01` 인증서 SAN에 IP `10.9.88.2`도 포함되어 있어 TLS 검증 문제 없음, `configs/elasticsearch/instances.yml` 확인).
- 위 이슈 + 6절의 Client SSL 이슈 수정 후 `elastic-agent status` 전체 `HEALTHY` 확인 완료.

### 외부 서버 2대 추가 (114.108.154.59 Ubuntu 22.04, 114.108.154.60 CentOS7)

`External-Servers` 정책, `FLEET_URL=https://139.150.84.70:8220`(NAT)으로 동일 스크립트 진행. CentOS7은 EOL이라 우려했으나 tar.gz 바이너리 설치라 문제없이 enroll됨.

- **겪은 이슈 — 외부 에이전트 모니터링 데이터 경로 없음**: `elastic-agent status`에서 `beat/metrics-monitoring` 등이 `Elasticsearch request failed: context deadline exceeded`로 계속 `DEGRADED`. 원인은 **에이전트 자체 모니터링(로그/메트릭)이 항상 `default` 출력(ES `10.9.88.2:9200`, 사설 IP)으로 가는데, 외부 에이전트는 사설 대역에 도달할 경로 자체가 없음** — Fleet Server(NAT 8220), Logstash(외부 LB 5044)와 달리 Elasticsearch는 NAT로 노출하지 않는 설계(`docs/02-certificates.md`)라서 구조적으로 해결 불가능한 경로. **Fleet → Agent policies → External-Servers → Settings → Agent monitoring(Collect agent logs/metrics) 토글을 끔**으로써 해결 — 에이전트 자기 자신에 대한 모니터링만 끄는 것이고, 실제 수집 로그 데이터(Logstash-External 경유)는 영향 없음. 정책 저장 후 대상 호스트에 반영되기까지 1~2분 정도 걸림.

## 9. 다음에 이어서 할 작업

1. 나머지 내부/외부 수집 대상 서버 enrollment — 8절과 동일 절차 반복 (외부 서버는 `FLEET_URL=https://139.150.84.70:8220` + `External-Servers` 정책 토큰 사용, Agent monitoring은 이미 정책에서 꺼둔 상태라 추가 조치 불필요)
2. **30일 트라이얼 만료(2026-08-19) 전에 라이선스 처리 방안 재검토** — 구매 안 하기로 했으므로 단일 출력 구조 전환 여부 결정 필요 (내부망에서 외부 LB 공인 IP `139.150.86.188` 도달 가능 여부 확인이 선행되어야 함)
3. 계정/권한/방화벽 정리 → `docs/07-security-hardening.md`
4. 전체 검증 → `docs/08-runbook-verification.md`
