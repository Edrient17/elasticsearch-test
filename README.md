# 간단한 원격 VM 로그 서버

다른 Linux VM의 시스템 로그를 Filebeat로 수집하고, Logstash를 거쳐 Elasticsearch에 저장한 뒤 Kibana에서 검색하는 최소 구성입니다.

```text
원격 VM (/var/log, Docker 로그) -> Filebeat -> TCP 5044 -> Logstash -> Elasticsearch -> Kibana
```

Elasticsearch(9200)와 Kibana(5601)는 기본적으로 서버의 localhost에만 열리며 비밀번호 인증을 사용합니다. 원격 VM에는 수집용 5044 포트만 노출됩니다.

## 1. 로그 서버 실행

요구 사항은 Docker와 Docker Compose 플러그인입니다. RAM은 최소 2GB, 여유가 있다면 4GB 이상을 권장합니다.

```bash
# Linux에서 현재 값이 1048576보다 작을 때 한 번 실행
sudo sysctl -w vm.max_map_count=1048576

cp .env.example .env
```

`.env`의 `ELASTIC_PASSWORD`, `KIBANA_PASSWORD`, `LOGSTASH_PASSWORD`를 서로 다른 영문/숫자 조합으로 변경합니다. 이 예제의 초기화 스크립트는 특수문자가 없는 8자 이상의 비밀번호를 요구합니다. Kibana 암호화 키 3개도 각각 다른 값으로 변경하세요.

```bash
openssl rand -hex 24
openssl rand -hex 32
```

설정을 마친 뒤 실행합니다.

```bash
docker compose up -d
docker compose ps
```

서버 안에서 다음 요청이 성공하면 Elasticsearch가 준비된 것입니다.

```bash
curl -u elastic:YOUR_ELASTIC_PASSWORD http://localhost:9200
```

Kibana를 내 PC에서 안전하게 열려면 SSH 터널을 사용합니다.

```bash
ssh -L 5601:localhost:5601 USER@ELASTIC_SERVER_IP
```

그 뒤 브라우저에서 <http://localhost:5601>을 열고 사용자 `elastic`과 `.env`의 `ELASTIC_PASSWORD`로 로그인합니다.

기존에 보안이 꺼진 상태로 실행 중이었다면 데이터를 지우지 않고 다음과 같이 전환합니다.

```bash
docker compose down
# 새 .env 항목을 모두 설정한 뒤
docker compose up -d
```

`docker compose down -v`는 기존 로그와 Kibana 설정을 삭제하므로 실행하지 마세요.

## 2. 방화벽 설정

`5044/tcp`는 인터넷 전체가 아니라 로그를 보내는 VM의 사설 IP에만 허용하세요. UFW를 쓰는 예시는 다음과 같습니다.

```bash
sudo ufw allow from REMOTE_VM_PRIVATE_IP to any port 5044 proto tcp
```

클라우드 보안 그룹도 같은 방식으로 제한해야 합니다. 공용 인터넷을 통해 전송해야 한다면 이 예제 그대로 노출하지 말고, 두 VM을 VPN/WireGuard 같은 사설망으로 먼저 연결하세요.

## 3. 원격 VM에서 Filebeat 실행

이 저장소의 `remote-agent` 디렉터리를 로그를 보낼 Linux VM으로 복사한 뒤 실행합니다.

```bash
cd remote-agent
cp .env.example .env
```

`.env`에서 아래 값을 실제 환경에 맞게 변경합니다.

```dotenv
LOGSTASH_HOST=10.0.0.10:5044
VM_NAME=application-vm-01
COLLECT_DOCKER_LOGS=false
```

에이전트를 시작하고 연결 상태를 확인합니다.

```bash
docker compose up -d
docker compose logs -f filebeat
```

`COLLECT_DOCKER_LOGS=true`로 바꾸면 `/var/lib/docker/containers`의 컨테이너 로그도 함께 수집합니다.

테스트 로그를 한 줄 남길 수 있습니다.

```bash
logger "elastic remote log test"
```

## 4. Kibana에서 로그 보기

1. Kibana의 **Stack Management > Data Views**로 이동합니다.
2. 이름은 `VM Logs`, 인덱스 패턴은 `vm-logs-*`로 입력합니다.
3. Timestamp field로 `@timestamp`를 선택해 생성합니다.
4. **Discover**에서 `VM Logs`를 선택합니다.

VM별 필터에는 `host.name` 또는 `labels.vm_name`을 사용합니다. 데이터가 들어왔는지는 서버에서 바로 확인할 수도 있습니다.

```bash
curl -u elastic:YOUR_ELASTIC_PASSWORD \
  'http://localhost:9200/_cat/indices/vm-logs-*?v'
```

## MCP용 읽기 전용 API 키

MCP가 `vm-logs-*`만 읽을 수 있는 30일짜리 API 키를 생성합니다.

```bash
bash scripts/create-mcp-api-key.sh
```

출력의 `encoded` 값은 다시 표시되지 않으므로 안전한 곳에 보관하고 `ES_API_KEY`로 사용합니다. 만료 기간을 바꾸려면 인자로 전달합니다.

```bash
bash scripts/create-mcp-api-key.sh 7d
```

Elasticsearch 주소는 서버 VM 안에서 `http://localhost:9200`입니다. 내 PC의 MCP 클라이언트에서 사용하려면 먼저 SSH 터널을 열고 같은 주소를 사용합니다.

```bash
ssh -N -L 9200:127.0.0.1:9200 USER@ELASTIC_SERVER_IP
```

API 키나 `.env` 파일은 Git에 커밋하지 마세요.

## 운영 명령

```bash
# 상태 확인
docker compose ps

# 서버 로그 확인
docker compose logs -f --tail=100

# 중지 (저장 데이터 유지)
docker compose down

# 중지하면서 Elasticsearch 데이터도 삭제
docker compose down -v
```

이 구성은 작은 내부망/테스트 환경을 위한 시작점입니다. Elasticsearch 인증은 활성화되어 있지만 HTTP TLS는 사용하지 않으므로 Elasticsearch와 Kibana를 localhost에 묶고 SSH 터널로 접근합니다. 5044 포트의 접근 제어는 반드시 방화벽 또는 사설망에서 적용해야 합니다.
