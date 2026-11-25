IMAGE ?= openresty-hardened
PLATFORM ?=

.PHONY: build test scan
build:
	docker build $(if $(PLATFORM),--platform $(PLATFORM)) --target default -t $(IMAGE):dev .
	docker build $(if $(PLATFORM),--platform $(PLATFORM)) --target geoip2 -t $(IMAGE):dev-geoip2 .

test: build
	test/smoke.sh $(IMAGE):dev default
	test/smoke.sh $(IMAGE):dev-geoip2 geoip2

scan: build
	for t in dev dev-geoip2; do \
	  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest \
	    image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE):$$t || exit 1; \
	done
