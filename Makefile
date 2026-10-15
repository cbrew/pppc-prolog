# Run inside `devenv shell`.

.PHONY: test check doc calibrate bench clean

test:
	swipl test/unit.pl

check:
	swipl -g run_tests -t halt test/e2e.plt

# Re-measure the shipped cost table on this machine.
calibrate:
	swipl pppc_calibrate -o prolog/pppc/cost/default.pl

# Measure speedups and loop verdicts on this machine (several minutes;
# run it on an idle machine). Notes after the marker in the file are kept.
bench:
	swipl pppc_bench -o bench/results.md

doc:
	swipl --no-packs -p library=prolog tools/doc.pl

clean:
	rm -rf build doc
