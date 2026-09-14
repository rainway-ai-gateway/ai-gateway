# Copyright(c) 2024 Beijing Yingfei Networks Technology Co.Ltd. All rights reserved.
#

HOMEDIR := $(shell pwd)

IMAGE_NAME ?= ai-gateway
VERSION ?= $(shell grep -E '^version:' VERSIONS.yaml | awk '{print $$NF}')

BFE_IMAGE ?= $(shell grep -A4 '  bfe:' VERSIONS.yaml | grep 'image:' | head -1 | sed -E 's/.*image: *//')
API_IMAGE ?= $(shell grep -A4 'ai-gateway-api:' VERSIONS.yaml | grep 'image:' | head -1 | sed -E 's/.*image: *//')
EPP_IMAGE ?= $(shell grep -A4 'ai-gateway-epp:' VERSIONS.yaml | grep 'image:' | head -1 | sed -E 's/.*image: *//')
OBS_VERSION ?= $(shell grep -A4 'observability:' VERSIONS.yaml | grep 'version:' | head -1 | awk '{print $$NF}')

REGISTRY ?=
PLATFORMS ?= linux/amd64,linux/arm64
NO_CACHE ?= false
VARIANT ?= prod

VERSION_TAG := $(VERSION)
IMAGE_LOCAL := $(IMAGE_NAME):$(VERSION_TAG)
IMAGE_LATEST_LOCAL := $(IMAGE_NAME):latest

ifeq ($(VARIANT),debug)
	IMAGE_LOCAL := $(IMAGE_NAME):$(VERSION_TAG)-debug
endif

IMAGE_REMOTE := $(if $(REGISTRY),$(REGISTRY)/$(IMAGE_NAME):$(VERSION_TAG),)
IMAGE_LATEST_REMOTE := $(if $(REGISTRY),$(REGISTRY)/$(IMAGE_NAME):latest,)

.PHONY: sync-grafana sync-doris sync docker-standalone docker-standalone-push

sync-grafana:
	@echo "Syncing Grafana config from ai-gateway-observability $(OBS_VERSION)..."
	@bash scripts/sync-grafana.sh $(OBS_VERSION)

sync-doris:
	@echo "Syncing Doris SQL from ai-gateway-observability $(OBS_VERSION)..."
	@bash scripts/sync-doris.sh $(OBS_VERSION)

sync: sync-grafana sync-doris

docker-standalone:
	@echo "Building AI Gateway standalone image..."
	@echo "  Image  : $(IMAGE_LOCAL)"
	@echo "  Variant: $(VARIANT)"
	@echo "  BFE    : $(BFE_IMAGE)"
	@echo "  API    : $(API_IMAGE)"
	@echo "  EPP    : $(EPP_IMAGE)"
	docker build \
		$$(if [ "$(NO_CACHE)" = "true" ]; then echo "--no-cache"; fi) \
		--build-arg BFE_IMAGE=$(BFE_IMAGE) \
		--build-arg API_IMAGE=$(API_IMAGE) \
		--build-arg EPP_IMAGE=$(EPP_IMAGE) \
		--build-arg VARIANT=$(VARIANT) \
		-t $(IMAGE_LOCAL) \
		-t $(IMAGE_LATEST_LOCAL) \
		-f Dockerfile.standalone \
		.

docker-standalone-push:
	@test -n "$(REGISTRY)" || (echo "REGISTRY is required, e.g. REGISTRY=ghcr.io/your-org" && exit 1)
	@docker buildx version >/dev/null 2>&1 || (echo "Error: docker buildx is not available." && exit 1)
	@echo "Building and pushing AI Gateway standalone (multi-arch)..."
	@echo "  Image    : $(IMAGE_REMOTE)"
	@echo "  Platforms: $(PLATFORMS)"
	@echo "  Variant  : $(VARIANT)"
	@echo "  BFE      : $(BFE_IMAGE)"
	@echo "  API      : $(API_IMAGE)"
	@echo "  EPP      : $(EPP_IMAGE)"
	docker buildx build \
		$$(if [ "$(NO_CACHE)" = "true" ]; then echo "--no-cache"; fi) \
		--platform $(PLATFORMS) \
		--build-arg BFE_IMAGE=$(BFE_IMAGE) \
		--build-arg API_IMAGE=$(API_IMAGE) \
		--build-arg EPP_IMAGE=$(EPP_IMAGE) \
		--build-arg API_VERSION=$(API_VERSION) \
		--build-arg VARIANT=$(VARIANT) \
		-t $(IMAGE_REMOTE) \
		-t $(IMAGE_LATEST_REMOTE) \
		-f Dockerfile.standalone \
		--push \
		.
