# 인증서 (자체 서명 CA, 단일 신뢰 체계)

Elasticsearch의 보안 자동구성(security auto-configuration)을 사용하지 않고, `elasticsearch-certutil`로 만든 CA 하나를 Elasticsearch / Kibana / Fleet Server / Logstash 전체가 공유한다. 이렇게 하면 Elastic Agent는 CA 인증서(`ca.crt`) 하나만 신뢰하면 Fleet Server(제어 평면)와 Logstash(데이터 평면) 양쪽에 모두 TLS 연결할 수 있다.

전 구간 PEM 포맷을 사용한다(PKCS12 변환 불필요) — Elasticsearch, Kibana, Logstash 모두 PEM 인증서/키를 직접 지원한다.

## 1. 생성 위치

Elastic01(또는 elasticsearch 패키지가 설치된 아무 관리 호스트)에서 **한 번만** 실행한다.

```bash
sudo apt-get install -y elasticsearch unzip   # 아직 서비스는 기동하지 않음
```

## 2. SAN 설계 (`configs/elasticsearch/instances.yml`)

| 인스턴스 | DNS | IP (SAN) | 이유 |
|---|---|---|---|
| elastic01 | elastic01 | 10.9.88.2 | 내부 전용, NAT IP 불필요 (9200을 외부에 노출하지 않음) |
| fleet-kibana | fleet-kibana | 10.9.88.61, 139.150.84.70 | 외부 에이전트가 NAT IP로 Fleet Server(8220)에 직접 접속 |
| logstash01 | logstash01 | 10.9.88.4, 10.9.88.40, 139.150.86.188 | 내부/외부 LB가 TCP 패스스루라 에이전트가 검증하는 인증서는 Logstash 자신의 것 |
| logstash02 | logstash02 | 10.9.88.9, 10.9.88.40, 139.150.86.188 | logstash01과 동일한 LB 뒤에 있으므로 동일 SAN 세트 |

`configs/elasticsearch/instances.yml` 파일을 그대로 사용한다.

## 3. 생성 실행

```bash
scp configs/elasticsearch/instances.yml root@elastic01:/root/certs/instances.yml   # 로컬에서 업로드하거나 직접 작성
ssh root@elastic01
sudo ./scripts/01-generate-certs.sh /root/certs/instances.yml /root/certs
```

결과:

```
/root/certs/ca/ca.crt                          # 전 노드 공통 CA (개인키 ca.key는 절대 배포하지 않음)
/root/certs/certs/elastic01/elastic01.crt,.key
/root/certs/certs/fleet-kibana/fleet-kibana.crt,.key
/root/certs/certs/logstash01/logstash01.crt,.key
/root/certs/certs/logstash02/logstash02.crt,.key
```

기본 유효기간은 5년이다. 장기 운영 시 만료일을 캘린더에 등록해 재발급 절차를 준비한다(재발급 시 CA는 재사용하고 `cert` 단계만 반복하면 된다).

## 4. 노드별 배포

각 노드에 다음 경로로 배포하고 권한을 제한한다. (Elasticsearch는 `elasticsearch` 사용자, Logstash는 `logstash` 사용자, Kibana/Fleet Server는 `root`로 기동되는 elastic-agent 프로세스가 파일을 읽을 수 있어야 하므로 아래 예시 권한을 기준으로 조정)

### Elastic01

```bash
sudo mkdir -p /etc/elasticsearch/certs
sudo scp root@<cert-host>:/root/certs/ca/ca.crt /etc/elasticsearch/certs/
sudo scp root@<cert-host>:/root/certs/certs/elastic01/{elastic01.crt,elastic01.key} /etc/elasticsearch/certs/
sudo chown -R root:elasticsearch /etc/elasticsearch/certs
sudo chmod 750 /etc/elasticsearch/certs
sudo chmod 640 /etc/elasticsearch/certs/*.crt /etc/elasticsearch/certs/*.key
```

### FleetKibana (Kibana + Fleet Server 둘 다 사용)

```bash
sudo mkdir -p /etc/kibana/certs /etc/fleet-server/certs
sudo scp root@<cert-host>:/root/certs/ca/ca.crt /etc/kibana/certs/
sudo scp root@<cert-host>:/root/certs/certs/fleet-kibana/{fleet-kibana.crt,fleet-kibana.key} /etc/kibana/certs/
sudo cp -r /etc/kibana/certs/. /etc/fleet-server/certs/
sudo chown -R root:kibana /etc/kibana/certs && sudo chmod 750 /etc/kibana/certs
```

### Logstash01 / Logstash02 (각자 자신의 인증서만 배포)

```bash
sudo mkdir -p /etc/logstash/certs
sudo scp root@<cert-host>:/root/certs/ca/ca.crt /etc/logstash/certs/
sudo scp root@<cert-host>:/root/certs/certs/logstash01/{logstash01.crt,logstash01.key} /etc/logstash/certs/   # logstash02는 logstash02.*
sudo chown -R root:logstash /etc/logstash/certs
sudo chmod 750 /etc/logstash/certs
```

## 5. 다음 단계

Elasticsearch 설치/보안 활성화 → [03-elasticsearch.md](03-elasticsearch.md)
