# Blog_Worker — 야간 자동 블로그 파이프라인

이 프로젝트는 `E:\Claude_Project`(다중 프로젝트 워크스페이스)의 하위 프로젝트입니다.
워크스페이스 공통 규칙은 [../CLAUDE.md](../CLAUDE.md)를 따르고, 이 문서는 그보다
**우선하는** 이 프로젝트 전용 규칙입니다. 이 폴더 밖(특히 `Auto_Trader/`)은 사용자가
명시적으로 지시하지 않는 한 읽거나 수정하지 않습니다.

## 목적

Claude Code CLI만으로(별도 API 키/과금 없이, Team Standard 구독 사용량 내에서) 매일 밤
22:00~08:00 사이에 블로그 글을 정확히 1편씩 자동으로
**조사(Scout) → 작성(Writer) → 자체 검토(Reviewer) → 게시(Publish)** 해서
GitHub Pages(Jekyll)에 올리는 무인 파이프라인.

## 저장소/배포 정보

- GitHub: https://github.com/Sil-ro/T419_Blog (public)
- Pages 주소: https://sil-ro.github.io/T419_Blog/ (Settings → Pages: `main` / `/(root)`)
- 로컬 git 커밋 작성자(이 저장소에 로컬로만 설정, 전역 아님): `jin <jin88x@gmail.com>`
- push 인증: Git Credential Manager(`credential.helper=manager`, Git for Windows 내장)가
  브라우저 로그인으로 처리. 별도 PAT/SSH 설정 안 함.

## 폴더 구조

```
Blog_Worker/
├── _config.yml              # Jekyll 설정 (title, theme: minima, url/baseurl 설정됨)
├── index.md                 # 홈 (layout: home, 글 목록 자동 표시)
├── Gemfile                  # 로컬 Jekyll 빌드용 (github-pages gem)
├── _posts/                  # 게시된 글 (Jekyll 인식용 언더스코어 필수 — 스펙 원문의 posts/에서 변경)
├── prompts/nightly-pipeline.md   # Scout→Writer→Reviewer→Publish 지시문
├── scripts/run-nightly.sh   # 매시 정각 실행기 (야간 게이트/횟수 상한/사용량 감지)
├── state.json                # {"date":..., "runs":...} — git 추적 안 함(.gitignore)
├── run-log/                  # 실행 로그 — git 추적 안 함(.gitignore)
├── .claude/settings.json     # 무인 실행용 최소 권한 allowlist
└── CLAUDE.md                 # 이 문서
```

## 파이프라인 규칙 (`prompts/nightly-pipeline.md`에 상세)

- 실행당 정확히 글 1편만 작성·게시.
- 금지 주제: 특정 개인/회사 비방, 의료 조언, 금융·투자 조언.
- 저작권: 원문 그대로 복사 금지, 짧은 인용 + 출처만.
- `_posts/`에 이미 있는 제목과 겹치지 않게 Scout 단계에서 중복 배제.
- 사용량/속도 제한 문구(usage limit, rate limit, 429, quota exceeded 등) 감지 시
  **즉시 중단** + 마지막 줄에 `USAGE_LIMIT_HIT` 출력 (재시도 금지).
- Publish 단계는 `git add _posts/<새 파일만>` (`-A`/`.` 금지 — state.json/로그 오염 방지),
  커밋 메시지 `post: <제목>`.

## 안전장치 (`scripts/run-nightly.sh`)

- `NIGHT_START_HOUR=22`, `NIGHT_END_HOUR=8`: 이 시간대가 아니면 조용히 종료(로그도 안 남김).
- `MAX_RUNS_PER_NIGHT=3`: 보수적으로 시작한 값. 낮 시간대 사용량 풀과 공유되므로 며칠
  지켜보고 조정할 것 (README.md 참고).
- `state.json`은 날짜가 바뀌면 자동으로 `runs=0`으로 리셋됨.
- 로그에서 사용량 제한 문구 재감지 시 오늘 밤 카운터를 상한으로 강제 설정(이중 안전장치).
- `.claude/settings.json`에 필요한 도구만 좁게 allow 처리(WebSearch/Read/Write/Edit +
  git add/commit/push/status/diff/log) — `--dangerously-skip-permissions` 사용 안 함.

## 무인 실행 등록 상태

- Windows 작업 스케줄러에 `nightly-blog-pipeline` 이름으로 등록됨 (매시 정각 트리거,
  스크립트 자체가 야간 여부를 다시 판단).
- 로그온 모드: **대화형만**(사용자 로그인 세션 필요, 화면 잠금은 무방 / 완전 로그아웃·재부팅
  시 미실행). 관리자 권한 없어 S4U(로그오프 상태 실행) 전환 실패 — 필요시 사용자가
  작업 스케줄러 GUI에서 직접 비밀번호를 입력해 전환해야 함 (Claude가 대신 할 수 없음).

## 진행 상태 / TODO (이 문서를 읽는 다음 세션이 이어받을 것)

- [x] Jekyll 스켈레톤, 파이프라인 프롬프트, run-nightly.sh, 권한 설정, 초기 커밋
- [x] run-nightly.sh 드라이런 테스트 (야간 게이트/상한/롤오버/사용량 감지 전부 검증,
      `runs` 파싱 정규식 버그 1건 발견 후 수정함)
- [x] GitHub 저장소 연결(origin) + 첫 push + Pages 활성화
- [x] claude CLI 설치 완료 (네이티브 설치, `C:\Users\SRJIN\.local\bin\claude.exe`).
      설치 스크립트가 PATH에 자동으로 못 넣어줘서 `[Environment]::SetEnvironmentVariable`로
      사용자 PATH에 직접 추가함. 대화형 로그인(`/logout` 후 재로그인으로 계정 교정)까지
      완료, `claude -p "test"` 무인 모드 응답 확인함. `CLAUDE_BIN`은 기본값 `claude`
      그대로 사용(PATH에 있으므로 전체 경로 불필요).
- [x] 작업 스케줄러 실제 트리거(`schtasks /run`) 1회 확인 — bash 실행되고 낮 시간대
      게이트에 걸려 조용히 종료되는 것까지 정상 동작 확인함.
- [ ] 실제 `claude -p` 전체 파이프라인(웹검색→작성→커밋→push) 1회 실행 테스트 아직
      안 함 (게시 행위라 사용자 승인 후 진행 예정).
- [ ] `run-log/` 며칠 지켜보고 `MAX_RUNS_PER_NIGHT` 조정.
