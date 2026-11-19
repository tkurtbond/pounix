# pounix -- Unix services for poc, the Peaseblossom Oberon Compiler.  See
# AGENTS.md; adapted from posockets' GNUmakefile.
#
# The library pounix is built in $(LIBDIR), with each module's C part
# (src/<Module>.c beside src/<Module>.Mod) compiled and archived with it.
# It links nothing beyond libc, so neither the library nor a program using
# it needs flags. The tests take the library from there, so they test this
# checkout and what make install would install.
#
# poc writes each module's .sym, .ll and .o, and the programs, into $(BUILD).
# Every program writes the files of the modules it compiles into the same
# $(BUILD), so make must not build two at once.
#
# make install installs the library in $(POCLIBDIR), ~/.local/lib/poc by
# default, with and without debug information, under -OC, the only size
# model the library supports. poc puts each in <triple>/<variant>/ there.

POC      ?= poc
PREFIX ?= $(HOME)/.local
POCLIBDIR ?= $(PREFIX)/lib/poc
# The size model: decided in PLAN.md, "Integer model"; never mix models.
POCFLAGS := -OC
MODELS := OC
VARIANTS := $(MODELS) $(addsuffix -g,$(MODELS))
# --track-fds=yes makes valgrind list the descriptors open at exit; the
# valgrind target requires that the test opened none of them.
# --child-silent-after-fork=yes: a child whose exec fails (TestProcesses
# makes two) ends in _exit holding the parent's argv and pipes, which
# valgrind would report as its own leaks.
VALGRIND ?= valgrind --child-silent-after-fork=yes --leak-check=full --show-leak-kinds=all --track-fds=yes --error-exitcode=99 --suppressions=poc-gc.supp
# How make test-root runs RootUsers as root.
SUDO ?= sudo

# An installed library on POC_LIBRARY_PATH would be taken in place of this
# checkout's source, or would stop the build if another poc wrote it.
unexport POC_LIBRARY_PATH

BUILD := build
LIBDIR := $(BUILD)/lib

LIBRARY := pounix
# The library's modules, in import order (PLAN.md, "Modules").
LIBMODS := UnixErrors UnixUsers UnixFiles UnixProcesses UnixTerminals

# $(call variant-flags,<variant>) gives poc's flags for a variant: OC-g gives
# -OC -g.
variant-flags = -$(firstword $(subst -, ,$(1))) $(if $(filter %-g,$(1)),-g)

# A library records the poc that built it, and another poc refuses it, so
# each library depends on poc itself.
POCBIN := $(shell command -v $(POC))
# Where a program finds pounix: this checkout's library, so an installed
# pounix is never taken in its place.
LIBPATH := -library-path $(LIBDIR)

# The modules and their C parts, whichever have one.
LIBSRC := $(LIBMODS:%=src/%.Mod) $(wildcard $(LIBMODS:%=src/%.c))
# Test programs (test/<name>.Mod, each a main module), run by make test.
TESTS := TestErrors TestUsers TestFiles TestProcesses TestTerminals
# Programs make test can't run (test/<name>.Mod): RootUsers must run as
# root (make test-root).
ROOTTESTS := RootUsers
# Programs that must halt (test/<name>.Mod), as name:Assert-code. poc's
# ASSERT(x, n) prints "assertion failed (n)" on standard error and exits
# with status 10, so `make test` requires both.
HALTTESTS := HaltFilesRange:110 HaltFilesFd:110 HaltFilesString:110 HaltFilesWait:110 HaltProcessesCommand:111 HaltProcessesWaited:112 HaltProcessesProcess:113 HaltFilesDirectory:114 HaltFilesMode:110 HaltFilesChangeMode:110 HaltTerminalsFd:110
ASSERTSTATUS := 10

TESTBINS := $(TESTS:%=$(BUILD)/%)
ROOTBINS := $(ROOTTESTS:%=$(BUILD)/%)
HALTBINS := $(foreach h,$(HALTTESTS),$(BUILD)/$(firstword $(subst :, ,$(h))))

.PHONY: all tests test test-root valgrind clean install uninstall doc
.NOTPARALLEL:

all: tests

tests: $(TESTBINS) $(ROOTBINS) $(HALTBINS)

$(BUILD):
	mkdir -p $@

$(LIBDIR)/$(LIBRARY)-%.stamp: $(LIBSRC) $(POCBIN) | $(BUILD)
	mkdir -p $(LIBDIR)
	cd src && $(POC) $(call variant-flags,$*) -output-dir $(abspath $(LIBDIR)) \
	  -library $(LIBRARY) $(LIBMODS:%=%.Mod)
	touch $@

$(TESTBINS) $(ROOTBINS): $(BUILD)/%: test/%.Mod test/Check.Mod $(LIBDIR)/$(LIBRARY)-OC.stamp | $(BUILD)
	$(POC) $(POCFLAGS) $(LIBPATH) -import-path test -output-dir $(BUILD) -o $@ $<

$(BUILD)/Halt%: test/Halt%.Mod $(LIBDIR)/$(LIBRARY)-OC.stamp | $(BUILD)
	$(POC) $(POCFLAGS) $(LIBPATH) -output-dir $(BUILD) -o $@ $<

# Run every test from test/; report all, fail at the end if any failed.
# Each halt test must exit with poc's ASSERT status and name its Assert
# code on standard error. Standard input is /dev/null. The tests make
# their files under build/test, emptied first.
test: tests
	@rm -rf $(BUILD)/test; mkdir -p $(BUILD)/test; \
	status=0; for t in $(TESTS); do \
	  echo "== $$t"; (cd test && ../$(BUILD)/$$t < /dev/null) || status=1; \
	done; \
	for h in $(HALTTESTS); do \
	  t=$${h%%:*}; code=$${h##*:}; echo "== $$t (must fail ASSERT code $$code)"; \
	  (cd test && ../$(BUILD)/$$t < /dev/null) 2> $(BUILD)/$$t.err; got=$$?; \
	  if [ $$got -eq $(ASSERTSTATUS) ] && grep -q "assertion failed ($$code)" $(BUILD)/$$t.err; then \
	    echo "ok   - $$t: $$(cat $(BUILD)/$$t.err)"; \
	  else echo "FAIL - $$t exited with $$got: $$(cat $(BUILD)/$$t.err)"; status=1; fi; \
	done; exit $$status

# The tests that must run as root, through $(SUDO) (PLAN.md, "Testing").
test-root: tests
	@status=0; for t in $(ROOTTESTS); do \
	  echo "== $$t (as root)"; (cd test && $(SUDO) ../$(BUILD)/$$t < /dev/null) || status=1; \
	done; exit $$status

# Each test under valgrind. Besides definite and indirect leaks, every
# still-reachable block must be the collector's own (test/vg-reachable.sh),
# and every descriptor open at exit must be one the test inherited
# (test/vg-fds.sh, from valgrind's --track-fds=yes report).
valgrind: tests
	@rm -rf $(BUILD)/test; mkdir -p $(BUILD)/test; \
	status=0; for t in $(TESTS); do \
	  echo "== valgrind $$t"; \
	  (cd test && $(VALGRIND) --log-file=../$(BUILD)/$$t.vg ../$(BUILD)/$$t < /dev/null) || status=1; \
	  grep -E 'ERROR SUMMARY|lost:|reachable:|FILE DESCRIPTORS' $(BUILD)/$$t.vg; \
	  test/vg-reachable.sh $(BUILD)/$$t.vg || { echo "FAIL - $$t: still-reachable memory the collector did not allocate"; status=1; }; \
	  test/vg-fds.sh $(BUILD)/$$t.vg || { echo "FAIL - $$t: descriptors left open at exit (see $(BUILD)/$$t.vg)"; status=1; }; \
	done; exit $$status

# install copies the library, in each variant, into $(POCLIBDIR) with poc
# -install-library, which copies only what a program needs: the archive
# (the C parts' objects are in it), the shared object, the manifest, and
# each module's .sym and .owner. A program then finds it with -library-path
# $(POCLIBDIR). A library records the poc that built it, and another poc
# refuses it: install again after upgrading poc.
define newline


endef

install: $(foreach v,$(VARIANTS),$(LIBDIR)/$(LIBRARY)-$(v).stamp)
	$(foreach v,$(VARIANTS),$(POC) $(call variant-flags,$(v)) \
	  $(LIBPATH) -install-library $(LIBRARY) -output-dir $(POCLIBDIR)$(newline))

# uninstall removes from $(POCLIBDIR)/<triple>/<variant> what install put
# there. It leaves other libraries' files alone, and removes a directory only
# when nothing is left in it. The triple is poc's target.
INSTALLED_FILES := $(LIBRARY).library lib$(LIBRARY).a lib$(LIBRARY).so lib$(LIBRARY).so.0.0 \
  $(foreach m,$(LIBMODS),$(m).sym $(m).owner)

uninstall:
	@triple=$$($(POC) -version | sed -n 's/^target \([^ ]*\).*/\1/p'); \
	if [ -z "$$triple" ]; then echo "uninstall: cannot get the target from $(POC) -version" >&2; exit 1; fi; \
	for v in $(VARIANTS); do \
	  dir=$(POCLIBDIR)/$$triple/$$v; \
	  if [ -d "$$dir" ]; then \
	    echo "cd $$dir && rm -f $(INSTALLED_FILES)"; \
	    (cd "$$dir" && rm -f $(INSTALLED_FILES)) || exit 1; \
	    rmdir "$$dir" 2>/dev/null || :; \
	  fi; \
	done; \
	rmdir $(POCLIBDIR)/$$triple 2>/dev/null || :; \
	rmdir $(POCLIBDIR) 2>/dev/null || :

# The reference in doc/, from each module's exported declarations and
# their comments. Its output is committed, so a reader needs no build.
DOCS := $(patsubst %,doc/%.md,$(LIBMODS))

doc: $(DOCS)

doc/%.md: src/%.Mod doc/mkref.py
	python3 doc/mkref.py $< > $@

clean:
	rm -rf $(BUILD)
