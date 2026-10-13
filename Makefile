# Run inside `devenv shell`.

.PHONY: test check doc clean

test:
	swipl test/unit.pl

check:
	swipl -g run_tests -t halt test/e2e.plt

doc:
	swipl --no-packs -p library=prolog tools/doc.pl

clean:
	rm -rf build doc
