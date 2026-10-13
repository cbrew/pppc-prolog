# Run inside `devenv shell`.

.PHONY: test clean

test:
	swipl test/unit.pl

clean:
	rm -rf build doc
