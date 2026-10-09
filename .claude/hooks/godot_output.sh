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
    # The test run and the compile check: GUT's run summary (each failing test with its
    # assert messages, then the totals), every error block no [ExpectedError] line claims
    # (compile errors, unexpected SCRIPT ERRORs, with up to six indented "at:" lines; three
    # repeats at most), and the exit code. Warnings, passing tests and known noise (the
    # gut_loader.gd:35 startup error, the leak reports at exit) are dropped. A test run that
    # never reaches its summary (a crash, nothing selected) prints its inline failures and
    # its last 40 lines instead. Colour codes are stripped. Same no-backslash rule as above:
    # a literal [ is written [[] and a literal ] is written []].
    gut=0
    case "$cmd" in *gut_cmdln.gd*) gut=1 ;; esac
    prog='function noise(s) { return s ~ /gut_loader[.]gd:35|resources still in use at exit|ObjectDB instances were leaked/ }
function flush(   i, show) { for (i = 1; i <= np; i++) { if (head[i]) show = seen[pl[i]]++ < 3; if (show) print pl[i] }; np = 0 }
BEGIN { esc = sprintf("%c", 27) }
{ gsub(esc "[[][0-9;]*m", ""); line = substr($0, 1, 400) }
/^godot exit:/ {
  flush()
  if (gut && !sum) {
    for (i = 1; i <= nf; i++) print fails[i]
    print "(no GUT run summary; the last 40 lines of output follow)"
    for (i = NR - 40; i < NR; i++) if (i > 0) print ring[i % 40]
  }
  print line; next
}
{ ring[NR % 40] = line }
!sum && index(line, "[Failed]") { if (nf < 50) fails[++nf] = script " " test ": " line; inblk = 0; next }
inblk && /^[[:blank:]]/ { if (keep && noise(line)) { np = bs; keep = 0 }; if (keep && cont-- > 0) { pl[++np] = line; head[np] = 0 }; next }
{ inblk = 0 }
/^(SCRIPT ERROR|SHADER ERROR|USER SCRIPT ERROR|USER ERROR|ERROR|USER WARNING|WARNING):|^[[]ERROR[]]/ {
  inblk = 1; bs = np; cont = 6
  keep = line !~ /^(USER )?WARNING/ && !noise(line)
  if (keep) { pl[++np] = line; head[np] = 1 }
  next
}
index(line, "[ExpectedError]") { np = 0; next }
index(line, "= Run Summary") { flush(); sum = 1; print line; next }
sum && !post { if (line ~ "^---- .* ----$") post = 1; if (line !~ "^=*$") print line; next }
!sum && line ~ "^res://" { flush(); script = line; next }
!sum && line ~ "^[*] " { flush(); test = substr(line, 3); next }
!sum && line ~ "^[0-9]+/[0-9]+ passed" { flush() }'
    filtered="{ $cmd 2>&1; echo \"godot exit: \$?\"; } | tee $log | awk -v gut=$gut '$prog' | tail -n 300"
    ;;
  *) printf '{}'; exit 0 ;;
esac

printf '%s' "$input" | jq --arg c "$filtered" --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $r, updatedInput: (.tool_input + {command: $c})}}'
