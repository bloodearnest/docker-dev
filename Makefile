
PROJECT := project
DOCKER_IMAGE := ghcr.io/opensafely-core/$(PROJECT)

REQUIREMENTS_IN ?= $(shell ls requirements*.in)
REQUIREMENTS_TXT = $(REQUIREMENTS_IN:.in=.txt)

# these enable buildkit in docker-compose
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1 

.PHONY: build
build: export BUILD_DATE=$(shell date +'%y-%m-%dT%H:%M:%S.%3NZ')
build: export GITREF=$(shell git rev-parse --short HEAD)
build:
	docker-compose build

test:
	docker-compose run test


.PHONY: lint
lint:
	@docker pull hadolint/hadolint
	@docker run --rm -i hadolint/hadolint < Dockerfile

requirements.dev.txt: requirements.dev.in
requirements.prod.txt: requirements.prod.in
	docker-compose run --rm dev pip-compile $<


clean:
	# remove all docker-compose created containers
	docker-compose rm --force --stop -v
