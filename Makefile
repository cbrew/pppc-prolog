# Run inside `devenv shell`.

.PHONY: test check doc calibrate clean

test:
	swipl test/unit.pl

check:
	swipl -g run_tests -t halt test/e2e.plt

# Re-measure the shipped cost table on this machine.
calibrate:
	swipl pppc_calibrate -o prolog/pppc/cost/default.pl

doc:
	swipl --no-packs -p library=prolog tools/doc.pl

clean:
	rm -rf build doc
