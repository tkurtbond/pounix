#!/bin/sh
# vg-reachable.sh LOG: succeed if every "still reachable" loss record in
# the valgrind log LOG (from --show-leak-kinds=all) is memory the program
# was right not to free, and print every other record:
#
# - memory allocated by poc's collector, GarbageCollectedHeap: its heap
#   chunks and its finalization and marking tables, which it never frees;
# - the dynamic loader's own memory for a library loaded with dlopen
#   (a stack through glibc's dl-open.c). getaddrinfo loads the NSS
#   modules (/etc/nsswitch.conf's "hosts:") so, and glibc keeps them
#   loaded until the program exits.
#
# Any other still-reachable block is memory the program should have
# freed - something the C part allocated (an addrinfo list, say) whose
# address is held only in the Oberon heap. Adapted from polibfyaml's.
#
# The allocator is the first frame after the C library's malloc, calloc or
# realloc in the record's stack.
awk '
  function finish() {
    if (inrec && first != "" && first !~ /GarbageCollectedHeap\./ && !dlopen) {
      print rec; print first; bad = 1
    }
    inrec = 0
  }
  / are still reachable in loss record / {
    finish(); inrec = 1; first = ""; dlopen = 0; rec = $0; next
  }
  inrec && /(at|by) 0x/ {
    if ($0 ~ /\(dl-open\.c:/) dlopen = 1
    if ($0 ~ /: (malloc|calloc|realloc) \(/) next
    if (first == "") first = $0
    next
  }
  inrec && /^==[0-9]+== *$/ { finish() }
  END { finish(); exit bad }
' "$1"
