# nLogtool

Ubuntu 24.04 LTS + Elastic Stack 9.x (Fleet Server + Kibana / Logstash x2 / Elasticsearch 단일 노드) 구축 가이드 및 설정 파일 모음.

## 대상 구성

| 역할 | 노드 | Private IP | NAT/Public IP |
|---|---|---|---|
| Kibana + Fleet Server | FleetKibana | 10.9.88.61 | 139.150.84.70 |
| Logstash | Logstash01 | 10.9.88.4 | - |
| Logstash | Logstash02 | 10.9.88.9 | - |
| 내부수집 LB | - | 10.9.88.40 | - |
| 외부수집 LB | - | - | 139.150.86.188 |
| Elasticsearch | Elastic01 | 10.9.88.2 | 117.52.83.173 |

전체 아키텍처와 설계 근거는 [docs/00-architecture.md](docs/00-architecture.md) 참고.

## 사용 방법

각 서버에서 이 저장소를 clone한 뒤, 문서 번호 순서대로 진행한다.

```bash
git clone https://github.com/keneich/nLogtool.git
cd nLogtool
```

| 순서 | 문서 | 대상 노드 |
|---|---|---|
| 1 | [docs/01-prerequisites.md](docs/01-prerequisites.md) | 전 노드 |
| 2 | [docs/02-certificates.md](docs/02-certificates.md) | 인증서 생성 노드 1곳 + 전 노드 배포 |
| 3 | [docs/03-elasticsearch.md](docs/03-elasticsearch.md) | Elastic01 |
| 4 | [docs/04-kibana-fleet-server.md](docs/04-kibana-fleet-server.md) | FleetKibana |
| 5 | [docs/05-logstash.md](docs/05-logstash.md) | Logstash01, Logstash02 |
| 6 | [docs/06-agent-enrollment.md](docs/06-agent-enrollment.md) | 로그 수집 대상 서버 |
| - | [docs/07-security-hardening.md](docs/07-security-hardening.md) | 계정/권한/방화벽 요약 |
| - | [docs/08-runbook-verification.md](docs/08-runbook-verification.md) | 전체 검증/트러블슈팅 |

## 디렉터리 구조

```
docs/       설치 가이드 (문서 번호 순서대로 진행)
configs/    elasticsearch.yml, kibana.yml, logstash 파이프라인 등 배포용 설정 파일
scripts/    각 단계에 대응하는 설치/설정 셸 스크립트
```

인증서, 비밀번호, API 키, 토큰 등은 이 저장소에 커밋하지 않는다(`.gitignore` 참고). 각 노드에서 발급/배포 절차를 통해 로컬에만 생성한다.
