#!/bin/sh
# vg-fds.sh LOG: succeed if the valgrind log LOG (from --track-fds=yes)
# shows no descriptor open at exit but those the program inherited and
# those poc's runtime keeps for the program's life.
# valgrind reports "FILE DESCRIPTORS: <n> open (<m> inherited) at exit.",
# and one the program left open makes n greater than m, listing it below
# with the stack that opened it (valgrind 3.27.1, checked 2026-11-15).
# Tasks' self-pipe, made by TaskWaiting.-pipe the first time a program
# waits idle and never closed, is two such descriptors, which are
# allowed. A log without the line fails.
awk '
  /FILE DESCRIPTORS: [0-9]+ open \([0-9]+ inherited\) at exit/ {
    for (i = 1; i < NF; i++) if ($i == "DESCRIPTORS:") { n = $(i + 1); m = $(i + 3) }
    sub(/^\(/, "", m); found = 1
  }
  /Open (file descriptor|AF_)/ { inblock = 1; runtime = 0; next }
  inblock && /TaskWaiting\.-pipe/ { if (!runtime) { r++; runtime = 1 } }
  /^==[0-9]+== *$/ { inblock = 0 }
  END { exit !(found && n == m + r) }
' "$1"
