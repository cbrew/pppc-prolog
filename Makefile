# Run inside `devenv shell`.

.PHONY: test doc clean

test:
	swipl test/unit.pl

doc:
	swipl --no-packs -p library=prolog tools/doc.pl

clean:
	rm -rf build doc
