# Codex compatibility

The scheduled job uses Codex by default. `AGENT_BACKEND=claude` remains available for an explicit rollback. The Codex branch uses `codex exec --cd <repo> --approve-for-me` and reads `prompts/nightly-pipeline.md` from standard input. `--approve-for-me` supplies the workspace-write sandbox and automatic approval review; the CLI rejects combining it with a separate `--sandbox` argument.

Before enabling Codex in the scheduler:

1. Verify `codex login status` in the same Windows account used by the task.
2. Test the shell script in an isolated copy with `AGENT_BACKEND=codex DRY_RUN=1 FORCE_RUN=1`. Even dry runs write `state.json` and a local log, so do not test against the live repository if its run counter matters.
3. Review the resulting log and verify that the CLI can access the repository and Git remote under the scheduled account. A dry run does not establish that publishing works.
4. Enable the Windows scheduled task only after a supervised Codex run succeeds. Keep `AGENT_BACKEND=claude` available for rollback.

The existing `.claude/settings.json` remains Claude-specific. The Codex invocation uses its own sandbox and automatic approval review. A rejected approval can prevent publication and should be investigated in the run log; do not replace it with unrestricted access.
