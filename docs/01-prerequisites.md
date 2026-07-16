# 사전 준비 (전 노드 공통 + 역할별 추가 작업)

모든 노드: Ubuntu 24.04 LTS, 4 vCPU / 8 GB RAM / 100 GB 디스크 2개(첫 번째는 OS, 두 번째는 데이터용 미사용 디스크로 가정).

## 1. 공통 작업 (Elastic01 / FleetKibana / Logstash01 / Logstash02 전부 수행)

### 1.1 시간 동기화

인증서 유효기간 검증과 로그 타임스탬프 정합성을 위해 필수.

```bash
sudo apt-get update
sudo apt-get install -y chrony
sudo systemctl enable --now chrony
timedatectl set-timezone Asia/Seoul   # 조직 표준 타임존에 맞게 조정
```

### 1.2 Elastic 9.x APT 저장소 등록

```bash
sudo apt-get install -y apt-transport-https gnupg curl
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" | \
  sudo tee /etc/apt/sources.list.d/elastic-9.x.list
sudo apt-get update
```

이 저장소 하나로 elasticsearch / kibana / logstash 패키지를 모두 설치할 수 있다. Elastic Agent(Fleet Server 포함)는 apt 패키지가 아니라 tar.gz 아카이브로 배포되므로 [04-kibana-fleet-server.md](04-kibana-fleet-server.md), [06-agent-enrollment.md](06-agent-enrollment.md)에서 별도로 다운로드한다.

### 1.3 `/etc/hosts` 등록 (전 노드 동일 파일 배포)

인증서 SAN에 사용하는 DNS 이름과 실제 IP를 모든 노드가 해석할 수 있어야 한다.

```
10.9.88.2    elastic01
10.9.88.61   fleet-kibana
10.9.88.4    logstash01
10.9.88.9    logstash02
```

### 1.4 스왑 비활성화 (Elasticsearch/Logstash 성능 및 메모리 락 이슈 방지)

```bash
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
```

## 2. 두 번째 디스크 마운트 (역할별 경로만 다름)

두 번째 디스크 디바이스명은 클라우드 제공자에 따라 `/dev/sdb` 또는 `/dev/vdb`일 수 있다. 아래는 `/dev/sdb` 기준 예시이며, 노드에서 `lsblk`로 실제 디바이스명을 먼저 확인한다.

```bash
lsblk                                   # 두 번째 디스크 디바이스명 확인
sudo parted -s /dev/sdb mklabel gpt mkpart primary ext4 0% 100%
sudo mkfs.ext4 /dev/sdb1
sudo blkid /dev/sdb1                    # UUID 확인
```

| 노드 | 마운트 경로 |
|---|---|
| Elastic01 | `/data/elasticsearch` |
| Logstash01 / Logstash02 | `/data/logstash` |
| FleetKibana | `/data` |

```bash
MOUNT_PATH=/data/elasticsearch   # 노드별로 위 표의 값으로 치환
sudo mkdir -p "$MOUNT_PATH"
echo "UUID=<blkid로 확인한 UUID>  $MOUNT_PATH  ext4  defaults,nofail  0  2" | sudo tee -a /etc/fstab
sudo mount -a
```

## 3. 커널/리소스 튜닝

### 3.1 Elastic01 전용: `vm.max_map_count`

```bash
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl --system
```

### 3.2 Elastic01 / Logstash01 / Logstash02: 파일 디스크립터 상향

```bash
sudo tee /etc/security/limits.d/elastic-stack.conf > /dev/null <<'EOF'
*   soft   nofile   65535
*   hard   nofile   65535
EOF
```

systemd로 기동되는 서비스는 각 유닛의 `LimitNOFILE`이 패키지 기본값(65535)으로 이미 설정되어 있으므로 위 설정은 셸/수동 실행 시 대비용이다.

## 4. 방화벽 / 보안그룹 규칙표

클라우드 보안그룹(Security Group/NACL)을 1차 통제 수단으로 사용하고, 아래 UFW 규칙은 인스턴스 내부 방화벽으로 보조 적용한다(둘 다 설정 권장). `10.9.88.0/24`는 관리·데이터 평면 노드가 속한 내부 서브넷이라고 가정했으므로, 실제 VPC 서브넷 CIDR에 맞게 조정한다.

| 대상 노드 | 포트/프로토콜 | 허용 출발지 | 용도 |
|---|---|---|---|
| Elastic01 | 9200/tcp | 10.9.88.61/32, 10.9.88.4/32, 10.9.88.9/32 | Kibana, Fleet Server, Logstash → ES |
| Elastic01 | 9300/tcp | 127.0.0.1 (기본, 외부 오픈 불필요) | 단일 노드 transport, 확장 대비 |
| Elastic01 | 22/tcp | 관리자 접근 IP 대역 | SSH |
| FleetKibana | 5601/tcp | 관리자 접근 IP 대역 (필요시 139.150.84.70 경유 접근 허용) | Kibana UI |
| FleetKibana | 8220/tcp | 10.0.0.0/8 (내부 에이전트) + NAT 경유 외부 에이전트 트래픽 | Fleet Server enrollment/checkin |
| FleetKibana | 22/tcp | 관리자 접근 IP 대역 | SSH |
| Logstash01/02 | 5044/tcp | 10.9.88.0/24 (내부 LB 소스 대역, 실제 LB 아웃바운드 IP로 좁혀서 조정) | 내부/외부 LB → Logstash 입력 |
| Logstash01/02 | 9600/tcp | 관리자/모니터링 대역만 | Logstash 모니터링 API |
| Logstash01/02 | 22/tcp | 관리자 접근 IP 대역 | SSH |

UFW 예시(Elastic01 기준, 다른 노드도 동일 패턴으로 대체):

```bash
sudo ufw allow from 10.9.88.61 to any port 9200 proto tcp
sudo ufw allow from 10.9.88.4  to any port 9200 proto tcp
sudo ufw allow from 10.9.88.9  to any port 9200 proto tcp
sudo ufw allow ssh
sudo ufw enable
```

> 외부 LB(139.150.86.188)의 실제 아웃바운드(백엔드로 나가는) 소스 IP는 클라우드 LB 제품마다 다르다(내부 IP를 그대로 쓰는 경우와 별도 서브넷을 쓰는 경우가 있음). 콘솔에서 확인 후 표의 `10.9.88.0/24` 규칙을 실제 값으로 좁힐 것을 권장한다.
> Fleet Server 8220 포트는 정책상 인터넷 전체에 노출해야 하는 경우가 많다(랜덤 공인 IP 에이전트). 이 경우 TLS + enrollment token만으로 인증되므로, 토큰 노출 관리(주기적 로테이션)에 유의한다. 상세: [07-security-hardening.md](07-security-hardening.md)

## 5. 다음 단계

인증서 생성 → [02-certificates.md](02-certificates.md)
