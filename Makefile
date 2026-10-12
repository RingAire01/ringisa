# Optional GNU make entry points; scripts/build.py also works without make.
.PHONY: all test rtl synth spec soc boot
CONFIG ?= Release
all:
	python scripts/build.py --config $(CONFIG)
test:
	python scripts/build.py --test --config $(CONFIG)
rtl:
	python scripts/rtl.py --test
synth:
	python scripts/rtl.py --synth
spec:
	python tools/specgen/generate.py
boot:
	python scripts/boot.py
soc:
	python scripts/rtl.py --test --synth --soc
