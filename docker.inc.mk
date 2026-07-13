# sibuild: Docker compatible tooling
#
#   1. $(BUILD_DIR)/%/Dockerfile.docker-image
#      Pattern rule that builds Dockerfile into a container image and
#      writes a stamped image based on the local image's content id.
#   2. docker_run
#      macro that runs a command inside a pre-built image while preserving
#      project layout expected by sibuild:
#        - $(PROJ_DIR) is bind-mounted at the same absolute path
#        - $(CURDIR) is used as the container workdir
#        - the host UID/GID is used to avoid permission problems
#        - /etc/localtime is mounted read-only so the timezone matches the host
#
# Typical use:
#   ```
#   include $(SIBUILD_DIR)/docker.inc.mk
#   $(BUILD_DIR)/app/Dockerfile.docker-image: DOCKER_IMAGE_NAME = app_docker_image
#   $(BUILD_DIR)/app/Dockerfile.docker-image: DOCKER_BUILD_ARGS = VER=1.0 FLAVOR=slim
#
#   in-docker: | $(BUILD_DIR)/app/Dockerfile.docker-image
#           $(call docker_run,app_docker_image,make -C app,)
#   ```
# It is recommended to invoke `make` inside docker rather than specific commands,
# since it is easy to run shell command in a recipe on the host by mistake, triggering subtle bugs.
ifeq "$(origin docker_inc_mk)" "undefined"
docker_inc_mk := defined

ifndef SIBUILD_DIR
SIBUILD_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
endif

# The container CLI. Auto detect or override e.g. make DOCKER_CLI=podman
DOCKER_CLI_AUTO := $(firstword $(foreach c,docker podman nerdctl,$(shell command -v $(c) 2>/dev/null)))
DOCKER_CLI ?= $(or $(strip $(DOCKER_CLI_AUTO)),$(error no container CLI found. Set DOCKER_CLI e.g. docker/podman/nerdctl))

# Build an image from Dockerfile. Provide tag and optional build args per image
$(BUILD_DIR)/%/Dockerfile.docker-image: DOCKER_BUILD_ARGS ?=
$(BUILD_DIR)/%/Dockerfile.docker-image: $(PROJ_DIR)/%/Dockerfile
	$(call log,DOCKER,$<)
	@$(MKDIR) $(dir $@)
	@$(DOCKER_CLI) build -t '$(DOCKER_IMAGE_NAME)' -f '$<' \
		--progress=quiet \
		$(foreach a,$(DOCKER_BUILD_ARGS),--build-arg '$(a)') \
		'$(dir $<)'
	@$(DOCKER_CLI) image inspect '$(DOCKER_IMAGE_NAME)' -f '{{.Id}}' > $@

# Run a command in a pre-built docker image, aligning with DOCKER_IMAGE_NAME provided for build.
# $(call container_run,<image>,<command>[,<extra-run-args>])
# # Note: `$(call ...)` arguments are comma-separated. If an image name, command,
# or extra run argument must contain a literal comma, define it in a variable
# first or use a `comma := ,` helper and use it as $(comma).
define docker_run
$(DOCKER_CLI) run --rm --pull=never \
       --mount type=bind,src=/etc/localtime,dst=/etc/localtime,ro \
       --mount type=bind,src=$(PROJ_DIR),dst=$(PROJ_DIR) \
    $(3) \
    -w $(CURDIR) \
    -u $(shell id -u):$(shell id -g) \
    '$(1)' \
    sh -lc '$(2)'
endef

endif # ifeq "$(origin docker_inc_mk)" "undefined"

