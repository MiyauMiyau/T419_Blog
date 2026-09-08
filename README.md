# 야간 자동 블로그 파이프라인

Claude Code CLI(추가 API 키/과금 없이, Team Standard 구독 사용량만으로)를 이용해
매일 밤 22:00~08:00 사이에 블로그 글을 1편씩 자동으로
조사 → 작성 → 자체 검토 → GitHub Pages(Jekyll) 게시까지 수행하는 파이프라인입니다.

## 폴더 구조

```
Blog_Worker/
├── _config.yml              # Jekyll 설정 (제목, 테마, 플러그인)
├── index.md                 # 홈 페이지 (글 목록)
├── Gemfile                  # 로컬에서 Jekyll을 미리 빌드해보고 싶을 때 필요
├── _posts/                  # 게시된 글이 쌓이는 곳 (Jekyll이 인식하는 폴더명은 반드시 _posts)
├── prompts/
│   └── nightly-pipeline.md  # Scout→Writer→Reviewer→Publish 지시문
├── scripts/
│   └── run-nightly.sh       # 매시 정각에 호출되는 실행기 (야간/횟수 상한/사용량 감지)
├── state.json                # {"date":..., "runs":...} — 오늘 밤 실행 횟수 기록 (git 추적 안 함)
├── run-log/                  # 실행 로그 (git 추적 안 함)
├── .claude/settings.json     # 무인 실행에 필요한 최소 권한만 허용 (아래 참고)
└── .gitignore
```

### 왜 `_posts/`(언더스코어)인가요?

요청하신 스펙에는 `posts/`로 적혀 있었지만, Jekyll은 글을 **`_posts/`** 폴더에서만
자동으로 인식합니다(파일명 규칙: `YYYY-MM-DD-slug.md`). 그래서 실제 폴더명은
`_posts/`로 만들었고, `prompts/nightly-pipeline.md`에도 이 경로로 저장하도록
지시해뒀습니다.

## 안전장치 요약

- **야간 시간대만 실행**: `scripts/run-nightly.sh`가 매시 정각에 불려도, 현재 시각이
  `NIGHT_START_HOUR`(22시)~`NIGHT_END_HOUR`(8시) 사이가 아니면 **아무 것도 하지 않고
  조용히 종료**합니다. 로그도 남기지 않아서 낮 시간대 실행 흔적조차 없습니다.
- **하룻밤 실행 횟수 상한**: `state.json`에 오늘 날짜와 실행 횟수를 기록합니다. 날짜가
  바뀌면 자동으로 0으로 리셋됩니다(=매일 리셋 효과). `MAX_RUNS_PER_NIGHT`에 도달하면
  더 이상 실행하지 않습니다.
- **사용량 제한 감지 시 즉시 중단**: 프롬프트(`nightly-pipeline.md`) 자체에도 "usage
  limit 관련 문구를 보면 즉시 중단하고 `USAGE_LIMIT_HIT`을 출력하라"고 지시해뒀고,
  감싸는 `run-nightly.sh`도 로그 전체에서 `usage limit|rate limit|429|quota
  exceeded|USAGE_LIMIT_HIT` 패턴을 다시 한 번 검사해서, 감지되면 오늘 밤 카운터를
  상한값으로 강제 설정해 이후 실행을 잠급니다. **재시도는 하지 않습니다.**
- **실행당 정확히 1편**: 프롬프트에 명시되어 있고, `git add`도 방금 만든 파일 하나만
  스테이징하도록 되어 있습니다(`git add -A` 금지 — `state.json`/로그가 같이
  커밋되는 걸 방지).
- **무인 실행 시 권한 프롬프트 방지**: `.claude/settings.json`에 이 파이프라인이 실제로
  필요한 도구만 좁게 허용해뒀습니다 — 웹 검색, 파일 읽기/쓰기/편집, 그리고
  `git add/commit/push/status/diff/log` 뿐입니다. `--dangerously-skip-permissions`
  같은 전체 허용 플래그는 쓰지 않았습니다.

## ⚠️ 꼭 읽어주세요: MAX_RUNS_PER_NIGHT

Claude Code는 **낮에 채팅으로 쓰는 사용량과 같은 풀(pool)을 공유**합니다. 이 파이프라인이
밤새 너무 많이 돌면, 다음 날 낮 업무용 대화에 쓸 사용량이 줄어들 수 있습니다.

`scripts/run-nightly.sh` 상단의 `MAX_RUNS_PER_NIGHT=3`은 **의도적으로 보수적인 시작
값**입니다. 며칠간 실제로 얼마나 소모되는지 `run-log/`와 사용량 현황을 지켜본 뒤에
서서히 올리는 걸 권장합니다. 글 1편당 조사(웹 검색 여러 번)+작성+검토가 포함돼서
생각보다 사용량이 꽤 들 수 있습니다.

## GitHub Pages 수익화에 대해

GitHub Pages 호스팅 자체는 무료입니다. 하지만 **애드센스 등으로 실제 수익화하려면
별도로 애드센스 계정 신청 → 사이트 심사(보통 콘텐츠/트래픽 기준 있음) → 승인까지
별도의 시간이 걸립니다.** 이 저장소를 세팅한다고 바로 수익이 나는 게 아니라는 점을
참고해주세요. 애드센스 신청 및 계정 정보 입력은 본인이 직접 진행해야 하는 절차입니다.

## 사전 준비 (아직 안 하신 것)

1. **GitHub 저장소 생성** — 이 폴더(Blog_Worker)를 push할 GitHub 저장소가 아직 없습니다.
   본인 계정으로 새 저장소를 만들고 `git remote add origin <저장소 URL>`을 해주세요.
2. **GitHub Pages 활성화** — 저장소 Settings → Pages에서 배포 브랜치를 지정하세요
   (가장 간단한 방법: `main` 브랜치 `/ (root)`로 배포, 또는 Jekyll용 GitHub Actions
   워크플로 사용).
3. **`_config.yml`의 `url`/`baseurl`**을 실제 저장소 정보로 채워주세요.
4. **claude CLI 경로 확인** — 작업 스케줄러가 사용자 세션 없이도 `claude` 명령을 찾을
   수 있는지 꼭 테스트해보세요 (아래 등록 방법 참고). 못 찾으면 `run-nightly.sh` 상단의
   `CLAUDE_BIN`을 전체 경로로 바꾸세요.

## 매시 정각 자동 실행 등록 방법

이 스크립트(`scripts/run-nightly.sh`)를 매시 정각에 실행하도록 등록해야 실제로
동작합니다. 두 가지 방법이 있습니다 — 본인 OS/환경에 맞는 걸 고르세요.

### 방법 A. Windows 작업 스케줄러 (Windows 네이티브, 권장)

이 PC(Windows 10 Pro)에서 가장 안정적인 방법입니다. 사용자가 로그인해 있지 않아도
(화면 잠금 상태 등) 실행되도록 설정할 수 있습니다.

1. 시작 메뉴 → "작업 스케줄러" 실행
2. 오른쪽 "작업 만들기" 클릭 (마법사 말고 "작업 만들기"를 권장 — 더 세밀하게 설정 가능)
3. **일반** 탭: 이름 입력 (예: `nightly-blog-pipeline`), "사용자가 로그온했는지 여부에
   관계없이 실행" 선택
4. **트리거** 탭: 새로 만들기 → "매일" → 반복 간격 "1시간마다", 시작 시각은 아무 때나
   (예: 00:00), 기간을 "무기한"으로
5. **동작** 탭: 새로 만들기 →
   - 프로그램/스크립트: `C:\Program Files\Git\usr\bin\bash.exe` (이 PC에 설치된 Git Bash
     경로 — 다르면 `where bash`로 확인)
   - 인수 추가: `-lc "scripts/run-nightly.sh"`
   - 시작 위치: `E:\Claude_Project\Blog_Worker`
6. **조건/설정** 탭: "AC 전원에 연결된 경우에만 시작" 체크 해제 권장(노트북이면 배터리
   중에도 동작하게), "작업이 실패하면 다시 시작" 옵션은 꺼두는 걸 권장 (사용량 제한으로
   실패한 걸 재시도하면 안 되므로)

명령줄로 등록하고 싶다면(관리자 권한 필요):
```bash
schtasks /create /tn "nightly-blog-pipeline" /tr "\"C:\Program Files\Git\usr\bin\bash.exe\" -lc \"cd /e/Claude_Project/Blog_Worker && ./scripts/run-nightly.sh\"" /sc hourly /mo 1 /ru "%USERNAME%" /rl LIMITED
```

### 방법 B. WSL crontab (WSL을 쓰는 경우)

WSL(Windows Subsystem for Linux)이 설치돼 있고 그 안에서 cron을 쓰고 싶다면:

```bash
crontab -e
```
아래 줄 추가 (매시 정각 실행):
```
0 * * * * /mnt/e/Claude_Project/Blog_Worker/scripts/run-nightly.sh
```
WSL의 cron 데몬(`service cron start`)이 항상 떠 있어야 하고, WSL이 꺼져 있으면 실행되지
않는다는 점에 유의하세요. 또한 이 경우 `claude` CLI가 WSL 안에도 설치돼 있어야 합니다.

### 방법 C. Claude Desktop 자체 예약 실행 기능

OS 스케줄러 대신 Claude Desktop 앱 자체의 예약 실행 기능(`/schedule`)을 쓸 수도
있습니다. 이 경우 OS 부팅 여부와 무관하게 클라우드 쪽에서 실행되지만, "정확히 이
쉘 스크립트 파일을 실행"하는 형태가 아니라 Claude에게 프롬프트를 반복 실행시키는
방식이라 이 저장소의 `run-nightly.sh`가 담당하는 시간대/횟수 제한/사용량 감지 로직을
그대로 재현하려면 프롬프트 자체에 세팅을 더 넣어야 합니다. 로컬 파일 시스템(git
저장소)에 직접 커밋/푸시하는 이 파이프라인 특성상, 방법 A(Windows 작업 스케줄러)가 더
간단하고 안전합니다.

## 글 직접 수정하기

자동 게시된 글을 직접 고치고 싶으면 GitHub 웹 편집기를 쓰면 됩니다 (별도 설치 불필요):

1. https://github.com/MiyauMiyau/T419_Blog 접속 → `_posts/<카테고리>/` 폴더 → 고칠 글 파일 클릭
2. 오른쪽 위 연필 아이콘(✏️) 클릭 → 마크다운 원본을 그대로 수정
3. 아래로 스크롤 → **Commit changes**
4. 1~2분 후 사이트에 반영됨 (GitHub Pages가 자동 재빌드)

## 직접 테스트해보기

```bash
# 야간 시간대가 아니어도 강제로 한 번 돌려보기 (실제 claude 호출 없이 로직만 확인)
DRY_RUN=1 FORCE_RUN=1 ./scripts/run-nightly.sh
cat run-log/*.log

# state.json 초기화하고 다시 테스트하고 싶으면
echo '{"date":"1970-01-01","runs":0}' > state.json
```

`DRY_RUN`을 빼고 `FORCE_RUN=1`만 주면 실제로 `claude -p`가 호출되어 진짜 글이 하나
작성되고 git commit/push까지 실행됩니다 (원격 저장소가 설정돼 있어야 push가
성공합니다).
