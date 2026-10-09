#!/usr/bin/env bash
# PreToolUse hook on Bash(godot *): the full test run, the compile check and render jobs
# print a whole log for a few lines that matter, and every agent pays for it. Rewrite those
# commands so the model sees only what matters. The raw output is kept on disk at
# .godot/last_godot_output.txt (gitignored) for anyone who needs it.
# Other godot commands (imports, sample_pixels and other one-shot scripts) are left alone.
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

# Already piped or redirected by the caller: do not touch it.
case "$cmd" in
  *'|'*|*'>'*) printf '{}'; exit 0 ;;
esac

log=/d/dev/tt-sim/.godot/last_godot_output.txt
reason="godot output filtered; raw log in .godot/last_godot_output.txt"

case "$cmd" in
  *render_jobs/run.gd*)
    # Render jobs: the output folder (the job line), each capture with its sizes, flags,
    # saved-level loads, measurements (gpu, record) and probe results, the end of the run,
    # and each error with its indented "at:" lines (three repeats at most). A HANG or
    # TIMEOUT line is preceded by the last step line, the step that hung. The per-step lines
    # stay in the raw log and in the job's own log.txt. The program has no backslashes, so
    # no quoting layer can eat one: the literal pipe is written [|].
    prog='/^RJ[|] step / { last = substr($0, 1, 300) }
/HANG|TIMEOUT/ && last != "" { print "(last step) " last; last = "" }
/ERROR|FAILED/ { cont = 0; if (seen[$0]++ < 3) { print substr($0, 1, 400); cont = 6 }; next }
cont > 0 && /^[[:blank:]]/ { print substr($0, 1, 400); cont--; next }
{ cont = 0 }
/^RJ[|] (job|flags|started|captured|index written|done in|TIMEOUT|HANG|gpu |record |loading saved|saved level|--saved|unknown|no species|call |eval )/ || /^godot exit:/ { print substr($0, 1, 300) }'
    filtered="{ $cmd 2>&1; echo \"godot exit: \$?\"; } | tee $log | awk '$prog' | tail -n 400"
    reason="render job output filtered; raw log in .godot/last_godot_output.txt, every step in the job's log.txt"
    ;;
  *gut_cmdln.gd*|*--quit-after*)
    pattern='\[Failed\]|\[Error\]|\[Risky\]|\[Pending\]|SCRIPT ERROR|ERROR|Error|error|Totals|Scripts|Tests|Asserts|Time|All tests passed|Warnings|Deprecated|Orphans|Leaked|HANG|godot exit:'
    filtered="{ $cmd 2>&1; echo \"godot exit: \$?\"; } | tee $log | grep -E -B 1 -A 4 '$pattern' | tail -n 200"
    ;;
  *) printf '{}'; exit 0 ;;
esac

printf '%s' "$input" | jq --arg c "$filtered" --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $r, updatedInput: (.tool_input + {command: $c})}}'
