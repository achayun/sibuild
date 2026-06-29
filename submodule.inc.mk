# sibuild: initialize git submodules on demand.
ifeq "$(origin submodule_inc_mk)" "undefined"
submodule_inc_mk := defined

%/.git: $(shell git rev-parse --absolute-git-dir)/index
	$(info [GIT] $(@D))
	@git submodule update --recursive --init $(@D)
	@touch $@

endif # ifeq "$(origin submodule_inc_mk)" "undefined"
