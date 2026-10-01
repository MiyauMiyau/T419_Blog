#!/usr/bin/env bash
# 매시 정각에 Windows 작업 스케줄러(또는 cron)가 호출하는 야간 블로그 파이프라인 실행기.
# 야간 시간대가 아니거나, 오늘 밤 실행 횟수 상한에 도달했으면 조용히 종료한다.
set -uo pipefail

# ===================== 설정 (필요시 조정) =====================
NIGHT_START_HOUR=22   # 이 시각부터
NIGHT_END_HOUR=8      # 이 시각 전까지 야간으로 간주 (22~08 = 다음날로 넘어가는 구간)
MAX_RUNS_PER_NIGHT=1  # 한밤에 글 생성 시도는 한 번만 한다 (중복 게시 방지)
CLAUDE_BIN="${CLAUDE_BIN:-claude}"  # claude CLI 경로. PATH에 없으면 전체 경로로 바꿀 것.
CODEX_BIN="${CODEX_BIN:-codex}"    # Codex CLI 경로.
AGENT_BACKEND="${AGENT_BACKEND:-codex}"  # Codex 기본 실행. 필요하면 claude로 명시적 롤백.
# ================================================================

# 테스트용 오버라이드 (평소에는 설정하지 않음)
#   FORCE_RUN=1  -> 야간 시간대 체크를 무시하고 강제 실행
#   DRY_RUN=1    -> claude를 실제로 호출하지 않고, 무엇을 할지만 로그에 남김
FORCE_RUN="${FORCE_RUN:-0}"
DRY_RUN="${DRY_RUN:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$REPO_DIR/state.json"
PROMPT_FILE="$REPO_DIR/prompts/nightly-pipeline.md"
LOG_DIR="$REPO_DIR/run-log"

mkdir -p "$LOG_DIR"

now_hour_raw="$(date +%H)"
now_hour=$((10#$now_hour_raw))  # 앞의 0으로 인한 8진수 오인식 방지
today="$(date +%Y-%m-%d)"
# 22시~08시 구간은 자정을 넘어도 같은 밤으로 취급한다.
if [ "$now_hour" -lt "$NIGHT_END_HOUR" ]; then
  night_date="$(date -d yesterday +%Y-%m-%d)"
else
  night_date="$today"
fi
now_ts="$(date +%Y-%m-%d-%H%M%S)"

is_night() {
  if [ "$NIGHT_START_HOUR" -le "$NIGHT_END_HOUR" ]; then
    [ "$now_hour" -ge "$NIGHT_START_HOUR" ] && [ "$now_hour" -lt "$NIGHT_END_HOUR" ]
  else
    # 예: 22시~다음날 8시처럼 자정을 넘어가는 구간
    [ "$now_hour" -ge "$NIGHT_START_HOUR" ] || [ "$now_hour" -lt "$NIGHT_END_HOUR" ]
  fi
}

if [ "$FORCE_RUN" != "1" ] && ! is_night; then
  # 낮 시간대: 아무 로그도 남기지 않고 조용히 종료 (사용량을 전혀 건드리지 않음)
  exit 0
fi

# ----- state.json 읽기 (jq 없이 grep/sed로 파싱; 항상 우리가 쓴 고정 포맷이라 안전) -----
read_state() {
  if [ -f "$STATE_FILE" ]; then
    state_date="$(grep -oE '"date"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | sed -E 's/.*"([0-9-]+)"/\1/')"
    state_runs="$(grep -oE '"runs"[[:space:]]*:[[:space:]]*[0-9]+' "$STATE_FILE" | grep -oE '[0-9]+$')"
  else
    state_date=""
    state_runs=""
  fi
  [ -z "${state_runs:-}" ] && state_runs=0
}

write_state() {
  local runs="$1"
  printf '{"date":"%s","runs":%s}\n' "$night_date" "$runs" > "$STATE_FILE"
}

read_state

# 날짜가 바뀌었으면 카운터 리셋 (=매일 자동 리셋)
if [ "$state_date" != "$night_date" ]; then
  state_runs=0
fi
write_state "$state_runs"

if [ "$state_runs" -ge "$MAX_RUNS_PER_NIGHT" ]; then
  # 오늘 밤 상한 도달: 조용히 종료
  exit 0
fi

new_runs=$((state_runs + 1))
write_state "$new_runs"

log_file="$LOG_DIR/${now_ts}.log"

{
  echo "===== run-nightly.sh 시작: $(date '+%Y-%m-%d %H:%M:%S') ====="
  echo "night_window=${NIGHT_START_HOUR}-${NIGHT_END_HOUR}시, this_run=${new_runs}/${MAX_RUNS_PER_NIGHT}, force_run=${FORCE_RUN}, dry_run=${DRY_RUN}"
} >> "$log_file"

if [ "$DRY_RUN" = "1" ]; then
  {
    echo "[DRY-RUN] 실제로는 다음을 실행함:"
    if [ "$AGENT_BACKEND" = "codex" ]; then
      echo "[DRY-RUN]   \"$CODEX_BIN\" exec --cd \"$REPO_DIR\" --approve-for-me - < \"$PROMPT_FILE\""
    else
      echo "[DRY-RUN]   cd \"$REPO_DIR\" && \"$CLAUDE_BIN\" -p <prompts/nightly-pipeline.md 내용>"
    fi
    echo "[DRY-RUN] 에이전트 호출과 git push는 생략함 (드라이런 모드)"
    echo "===== run-nightly.sh 종료 (dry-run) ====="
  } >> "$log_file"
  exit 0
fi

cd "$REPO_DIR" || exit 1

# .env가 있으면 읽어서 환경변수로 내보냄 (예: UNSPLASH_ACCESS_KEY) — claude 하위 프로세스가 상속받음
if [ -f "$REPO_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO_DIR/.env"
  set +a
fi

case "$AGENT_BACKEND" in
  claude)
    "$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" >> "$log_file" 2>&1
    agent_exit=$?
    ;;
  codex)
    # 승인과 sandbox를 유지한다. 무제한 승인/샌드박스 우회 옵션은 사용하지 않는다.
    "$CODEX_BIN" exec --cd "$REPO_DIR" --approve-for-me - < "$PROMPT_FILE" >> "$log_file" 2>&1
    agent_exit=$?
    ;;
  *)
    echo "지원하지 않는 AGENT_BACKEND: $AGENT_BACKEND" >> "$log_file"
    agent_exit=2
    ;;
esac

echo "$AGENT_BACKEND 종료 코드: $agent_exit" >> "$log_file"

# 프롬프트 자체에도 제한 관련 문구가 있으므로 에이전트의 단독 종료 표식만 감지한다.
if grep -qE '^USAGE_LIMIT_HIT\r?$' "$log_file"; then
  echo "USAGE_LIMIT_HIT: 사용량 제한 감지됨 -> 오늘 밤 나머지 실행 잠금" >> "$log_file"
  write_state "$MAX_RUNS_PER_NIGHT"
fi

echo "===== run-nightly.sh 종료: $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$log_file"
exit "$agent_exit"
