#!/usr/bin/env bash
# 매시 정각에 Windows 작업 스케줄러(또는 cron)가 호출하는 야간 블로그 파이프라인 실행기.
# 야간 시간대가 아니거나, 오늘 밤 실행 횟수 상한에 도달했으면 조용히 종료한다.
set -uo pipefail

# ===================== 설정 (필요시 조정) =====================
NIGHT_START_HOUR=22   # 이 시각부터
NIGHT_END_HOUR=8      # 이 시각 전까지 야간으로 간주 (22~08 = 다음날로 넘어가는 구간)
MAX_RUNS_PER_NIGHT=3  # 하룻밤 최대 실행 횟수 (처음엔 보수적으로 낮게 시작)
CLAUDE_BIN="${CLAUDE_BIN:-claude}"  # claude CLI 경로. PATH에 없으면 전체 경로로 바꿀 것.
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
  printf '{"date":"%s","runs":%s}\n' "$today" "$runs" > "$STATE_FILE"
}

read_state

# 날짜가 바뀌었으면 카운터 리셋 (=매일 자동 리셋)
if [ "$state_date" != "$today" ]; then
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
    echo "[DRY-RUN]   cd \"$REPO_DIR\" && \"$CLAUDE_BIN\" -p <prompts/nightly-pipeline.md 내용> "
    echo "[DRY-RUN] claude 호출과 git push는 생략함 (드라이런 모드)"
    echo "===== run-nightly.sh 종료 (dry-run) ====="
  } >> "$log_file"
  exit 0
fi

cd "$REPO_DIR" || exit 1

"$CLAUDE_BIN" -p "$(cat "$PROMPT_FILE")" >> "$log_file" 2>&1
claude_exit=$?

echo "claude 종료 코드: $claude_exit" >> "$log_file"

# 사용량/속도 제한 문구가 로그에 보이면, claude 프로세스가 스스로 멈추지 못했더라도
# 여기서 최종적으로 오늘 밤 카운터를 상한으로 강제 설정해서 더 이상 실행되지 않게 한다.
if grep -qiE 'usage limit|rate limit|429|quota exceeded|resets at|USAGE_LIMIT_HIT' "$log_file"; then
  echo "USAGE_LIMIT_HIT: 사용량 제한 감지됨 -> 오늘 밤 나머지 실행 잠금" >> "$log_file"
  write_state "$MAX_RUNS_PER_NIGHT"
fi

echo "===== run-nightly.sh 종료: $(date '+%Y-%m-%d %H:%M:%S') =====" >> "$log_file"
exit 0
