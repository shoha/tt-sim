#!/usr/bin/env bash
# PreToolUse hook on Bash(godot *): the full test run and the compile check print the
# whole log for one line of totals, and every agent pays for it. Rewrite those two
# commands so the model sees failures, errors and the totals block only. The raw output
# is kept on disk at .godot/last_godot_output.txt (gitignored) for anyone who needs it.
# Other godot commands (render jobs, imports) are left alone.
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# Already piped or redirected by the caller: do not touch it.
case "$cmd" in
  *'|'*|*'>'*) printf '{}'; exit 0 ;;
esac

case "$cmd" in
  *gut_cmdln.gd*|*--quit-after*) ;;
  *) printf '{}'; exit 0 ;;
esac

log=/d/dev/tt-sim/.godot/last_godot_output.txt
pattern='\[Failed\]|\[Error\]|\[Risky\]|\[Pending\]|SCRIPT ERROR|ERROR|Error|error|Totals|Scripts|Tests|Asserts|Time|All tests passed|Warnings|Deprecated|Orphans|Leaked|HANG|godot exit:'
filtered="{ $cmd 2>&1; echo \"godot exit: \$?\"; } | tee $log | grep -E -B 1 -A 4 '$pattern' | tail -n 200"

printf '%s' "$input" | jq --arg c "$filtered" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "godot output filtered; raw log in .godot/last_godot_output.txt", updatedInput: (.tool_input + {command: $c})}}'
