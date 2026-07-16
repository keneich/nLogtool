# 아키텍처 개요

Ubuntu 24.04 LTS 4개 노드에 Elastic Stack 9.x(최신 안정 버전)를 구축한다. 각 노드는 4 vCPU / 8 GB RAM / 100 GB 디스크 2개로 동일한 스펙을 가진다.

## 노드/네트워크 구성

| 역할 | 노드명 | Private IP | NAT/Public IP |
|---|---|---|---|
| Kibana + Fleet Server | FleetKibana | 10.9.88.61 | 139.150.84.70 |
| Logstash (수집 파이프라인) | Logstash01 | 10.9.88.4 | - |
| Logstash (수집 파이프라인) | Logstash02 | 10.9.88.9 | - |
| 내부수집용 LB (매니지드, → Logstash01/02) | - | 10.9.88.40 | - |
| 외부수집용 LB (매니지드, → Logstash01/02) | - | - | 139.150.86.188 |
| Elasticsearch 단일 노드 | Elastic01 | 10.9.88.2 | 117.52.83.173 |
| 로그 수집 대상 (Elastic Agent) | - | 10.0.0.0/8 | 필요시 랜덤 공인 IP |

> 내부 LB/외부 LB는 클라우드 매니지드 로드밸런서(예: L4 TCP 패스스루)를 사용한다고 가정한다. 본 문서는 백엔드(Logstash01/02) 연결 요구사항만 다루며, LB 자체의 리스너/헬스체크 설정은 클라우드 콘솔에서 아래 조건에 맞춰 구성한다.
> - 리스너: TCP 5044 → 백엔드 Logstash01(10.9.88.4:5044), Logstash02(10.9.88.9:5044)
> - 헬스체크: TCP 5044 (또는 Logstash 모니터링 API `9600/_node`를 헬스체크로 쓰려면 별도 HTTP 헬스체크 리스너 구성)
> - 세션 고정(sticky) 불필요 — Elastic Agent 출력은 매 연결마다 라운드로빈으로 분산되어도 무방

## 트래픽 흐름

### 1) 제어 평면 (Fleet 관리)

```
[Elastic Agent, 내부 10.0.0.0/8]  --8220/tcp(TLS)--> [Fleet Server @10.9.88.61:8220]
[Elastic Agent, 외부 랜덤 공인IP] --8220/tcp(TLS)--> [Fleet Server @139.150.84.70:8220 (NAT)]
[Fleet Server]                    --9200/tcp(TLS)--> [Elasticsearch @10.9.88.2:9200]
[Kibana @10.9.88.61:5601]         --9200/tcp(TLS)--> [Elasticsearch @10.9.88.2:9200]
```

Fleet Server는 에이전트의 정책 배포/상태 보고/enrollment를 처리하며, 이 데이터는 항상 Elasticsearch에 직접 저장된다(Fleet Server의 출력은 Logstash를 경유하지 않음 — Fleet 자체 제약).

### 2) 데이터 평면 (로그/메트릭 수집)

```
[Elastic Agent, 내부] --5044/tcp(TLS)--> [내부 LB 10.9.88.40] --> [Logstash01/02]
[Elastic Agent, 외부] --5044/tcp(TLS)--> [외부 LB 139.150.86.188] --> [Logstash01/02]
[Logstash01/02] --9200/tcp(TLS, API Key)--> [Elasticsearch @10.9.88.2:9200]
```

이를 위해 Fleet에 출력(Output)을 2개 등록한다.

| 출력 이름 | 유형 | 대상 | 사용 정책 |
|---|---|---|---|
| Logstash-Internal | Logstash | `10.9.88.40:5044` | Internal-Servers |
| Logstash-External | Logstash | `139.150.86.188:5044` | External-Servers |

그리고 에이전트 정책도 대상 네트워크에 따라 2개로 분리한다.

| 정책 이름 | 대상 | 데이터 출력 |
|---|---|---|
| Fleet Server Policy | Fleet Server 자신 | Elasticsearch 직결(기본) |
| Internal-Servers | 10.0.0.0/8 내부 서버 | Logstash-Internal |
| External-Servers | 외부/랜덤 공인 IP 서버 | Logstash-External |

## 설계 근거

1. **단일 자체 서명 CA**: Elasticsearch의 보안 자동구성(auto-configuration TLS)을 끄고 `elasticsearch-certutil`로 만든 CA 하나를 Elasticsearch, Kibana, Fleet Server, Logstash 전체에 배포한다. Logstash와 Fleet Server 등 자동구성 범위 밖의 컴포넌트까지 한 신뢰 체계로 묶어야 에이전트가 CA 인증서 하나만으로 Fleet Server와 Logstash 양쪽을 모두 신뢰할 수 있다. 상세: [02-certificates.md](02-certificates.md)
2. **Logstash 인증서에 LB IP를 SAN으로 포함**: 내부/외부 LB가 TCP 패스스루이므로 에이전트가 TLS 핸드셰이크에서 실제로 검증하는 인증서는 Logstash 자신의 인증서다. 에이전트 출력 설정의 host(`10.9.88.40`, `139.150.86.188`)와 인증서 SAN이 일치해야 hostname 검증에 실패하지 않는다.
3. **Logstash 입력은 `elastic_agent` 플러그인**: Beats 프로토콜과 호환되면서 `data_stream.*` 필드를 보존해, 출력 단계에서 Elasticsearch `data_stream` 모드로 원래의 데이터스트림(`logs-*-*`, `metrics-*-*` 등) 라우팅을 그대로 유지할 수 있다.
4. **정책/출력 2원화(Internal/External)**: 내부 에이전트가 굳이 공인 IP·외부 LB를 거치면 불필요한 비용/지연이 발생하고, 외부(랜덤 공인 IP) 에이전트는애초에 내부 IP(10.9.88.40)에 도달할 수 없다. 망 구분에 따라 출력·정책을 분리하는 것이 가장 단순한 해법이다.
5. **비밀번호/토큰은 설정 파일에 평문으로 두지 않음**: Logstash·Kibana keystore, Fleet 서비스 토큰/API 키를 사용한다. 상세: [07-security-hardening.md](07-security-hardening.md)

## 사이징

전 노드 동일 스펙(4 vCPU / 8 GB RAM / 100 GB 디스크 2개)을 가정한다.

| 노드 | JVM 힙 | 비고 |
|---|---|---|
| Elastic01 | 4g (RAM의 50%) | `vm.max_map_count=262144` 필요 |
| Logstash01/02 | 4g (RAM의 50%) | pipeline.workers는 기본값(코어 수=4) 유지 |
| FleetKibana | 별도 힙 튜닝 불요 | Kibana Node.js 기본 힙, Fleet Server는 경량 프로세스 |

디스크 2개 중 1개(OS 기본 디스크)는 그대로 두고, 2번째 디스크를 역할별 데이터 경로로 마운트한다.

| 노드 | 2번째 디스크 마운트 경로 | 용도 |
|---|---|---|
| Elastic01 | `/data/elasticsearch` | Elasticsearch data path |
| Logstash01/02 | `/data/logstash` | Persistent Queue + Dead Letter Queue |
| FleetKibana | `/data` | Fleet Server 상태/Kibana 로그 (여유 공간) |

## 문서 목차

1. [01-prerequisites.md](01-prerequisites.md) — OS 사전 준비(저장소 등록, 디스크, sysctl, 방화벽, hosts)
2. [02-certificates.md](02-certificates.md) — CA/인증서 생성 및 배포
3. [03-elasticsearch.md](03-elasticsearch.md) — Elasticsearch 설치
4. [04-kibana-fleet-server.md](04-kibana-fleet-server.md) — Kibana + Fleet Server 설치/설정
5. [05-logstash.md](05-logstash.md) — Logstash 설치/파이프라인
6. [06-agent-enrollment.md](06-agent-enrollment.md) — Elastic Agent 배포
7. [07-security-hardening.md](07-security-hardening.md) — 계정/권한/방화벽 요약
8. [08-runbook-verification.md](08-runbook-verification.md) — 검증 절차 및 트러블슈팅
