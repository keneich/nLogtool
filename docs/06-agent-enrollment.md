# Elastic Agent 배포 (수집 대상 서버)

대상: `10.0.0.0/8` 내부 서버 전부 + 필요시 랜덤 공인 IP를 가진 외부 서버.

## 1. 정책별 enrollment token 확인/발급

Kibana **Fleet → Agents → Add agent**에서 등록하려는 서버가 속한 망에 맞는 정책을 선택한다.

| 대상 서버 | 선택 정책 | Fleet Server URL |
|---|---|---|
| 10.0.0.0/8 내부 서버 | Internal-Servers | `https://10.9.88.61:8220` |
| 랜덤 공인 IP 외부 서버 | External-Servers | `https://139.150.84.70:8220` (NAT) |

정책을 선택하면 Kibana가 해당 정책의 enrollment token과 완전한 설치 명령(다운로드 URL 포함)을 화면에 보여준다. 이 화면의 명령을 그대로 복사해 써도 되고, 자동화가 필요하면 `scripts/06-enroll-agent.sh`를 사용한다.

토큰을 API로 조회하려면:

```bash
curl -k -u elastic:$ELASTIC_PASSWORD -H 'kbn-xsrf: true' \
  "https://fleet-kibana:5601/api/fleet/enrollment_api_keys?kuery=policy_id:\"<policy-id>\""
```

## 2. CA 인증서 사전 배포

수집 대상 서버는 우리 인프라 밖의 임의 서버이므로, enrollment 전에 `docs/02-certificates.md`에서 만든 CA 인증서(`ca.crt`)만 미리 해당 서버에 복사해 둔다(배포 도구/골든 이미지/수동 scp 중 조직에서 쓰는 방식 사용). 기본 경로는 `/etc/elastic-stack-ca/ca.crt`(스크립트의 `CA_CERT_PATH` 기본값)이다.

```bash
sudo mkdir -p /etc/elastic-stack-ca
sudo scp root@<cert-host>:/root/certs/ca/ca.crt /etc/elastic-stack-ca/ca.crt
```

## 3. 설치

```bash
# 내부 서버 (10.0.0.0/8)
sudo FLEET_URL=https://10.9.88.61:8220 \
     ENROLLMENT_TOKEN=<Internal-Servers 토큰> \
     AGENT_VERSION=9.x.y \
     ./scripts/06-enroll-agent.sh

# 외부/랜덤 공인 IP 서버
sudo FLEET_URL=https://139.150.84.70:8220 \
     ENROLLMENT_TOKEN=<External-Servers 토큰> \
     AGENT_VERSION=9.x.y \
     ./scripts/06-enroll-agent.sh
```

## 4. 확인

- Kibana **Fleet → Agents**에서 새 호스트가 `Healthy` 상태로 나타나는지 확인
- 해당 호스트가 속한 정책의 **Output for integrations**이 의도한 Logstash 출력(Internal/External)으로 지정되어 있는지 재확인
- 통합(Integration)을 정책에 추가하면 대상 서버에 자동 배포되어 수집이 시작된다 (예: System, Custom Logs 등 필요한 통합을 Internal-Servers/External-Servers 정책에 추가)

## 5. 다음 단계

계정/권한/방화벽 정리 → [07-security-hardening.md](07-security-hardening.md), 전체 검증 → [08-runbook-verification.md](08-runbook-verification.md)
