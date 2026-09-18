EMACS ?= emacs

SRC = $(wildcard gh-radar*.el)
TEST_SRC = $(wildcard test/*-test.el)

.PHONY: all compile test check-style clean

all: compile test

compile:
	$(EMACS) -Q -batch -L . -f batch-byte-compile $(SRC)

test:
	$(EMACS) -Q -batch -L . -L test -l test/test-helper.el \
		$(foreach f,$(TEST_SRC),-l $(f)) \
		-f ert-run-tests-batch-and-exit

check-style:
	@awk 'length > 80 {print FILENAME ":" NR ":" $$0; err=1} END {exit err}' \
		$(SRC) $(wildcard test/*.el)

clean:
	rm -f *.elc test/*.elc
