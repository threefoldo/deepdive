# Makefile for DeepDive

# install destination
PREFIX = ~/local
# path to the staging area
STAGE_DIR = dist/stage
# path to the package to be built
PACKAGE = $(dir $(STAGE_DIR))deepdive.tar.gz

.DEFAULT_GOAL := install

### dependency recipes ########################################################

.PHONY: depends
depends:
	# Installing and Checking dependencies...
	util/install.sh _deepdive_build_deps _deepdive_runtime_deps


### install recipes ###########################################################

.PHONY: install
install: build
	# Installing DeepDive to $(PREFIX)/
	mkdir -p $(PREFIX)
	tar cf - -C $(STAGE_DIR) . | tar xf - -C $(PREFIX)
	# DeepDive has been install to $(PREFIX)/
	# Make sure your shell is configured to include the directory in PATH environment, e.g.:
	#    export PATH="$(PREFIX)/bin:$$PATH"

.PHONY: package
package: $(PACKAGE)
$(PACKAGE): build
	tar czf $@ -C $(STAGE_DIR) .

### release recipes ###########################################################

# For example, `make release-v0.7.0` builds the package, tags it with version
# v0.7.0, then uploads the file to the GitHub release.  Installers under
# util/install/ can then download and install the binary release directly
# without building the source tree.

release-%: GITHUB_REPO = HazyResearch/deepdive
release-%: RELEASE_VERSION = $*
release-%: RELEASE_PACKAGE = deepdive-$(RELEASE_VERSION)-$(shell uname).tar.gz
release-%:
	git tag --annotate --force $(RELEASE_VERSION)
	$(MAKE) RELEASE_VERSION=$(RELEASE_VERSION) $(PACKAGE)
	ln -sfn $(PACKAGE) $(RELEASE_PACKAGE)
	# Releasing $(RELEASE_PACKAGE) to GitHub
	# (Make sure GITHUB_OAUTH_TOKEN is set directly or via ~/.netrc or OS X Keychain)
	util/upload-github-release-asset \
	    file=$(RELEASE_PACKAGE) \
	    repo=$(GITHUB_REPO) \
	    tag=$(RELEASE_VERSION)
	# Released $(RELEASE_PACKAGE) to GitHub

### build recipes #############################################################

# common build steps between build and test-build targets
define STAGING_COMMANDS
	# staging all executable code and runtime data under $(STAGE_DIR)/
	./stage.sh $(STAGE_DIR)
	# record version and build info
	util/generate-build-info.sh >$(STAGE_DIR)/.build-info.sh
endef

.PHONY: build
build: scala-assembly-jar
	$(STAGING_COMMANDS)
	# record production environment settings
	echo 'export CLASSPATH="$$DEEPDIVE_HOME"/lib/deepdive.jar' >$(STAGE_DIR)/env.sh

test-build: scala-test-build
	$(STAGING_COMMANDS)
	# record test-specific environment settings
	echo "export CLASSPATH='$$(cat $(SCALA_TEST_CLASSPATH_EXPORTED))'" >$(STAGE_DIR)/env.sh

# use bundled SBT launcher when necessary
PATH += :$(shell pwd)/sbt
# XXX For some inexplicable reason on OS X, the default SHELL (/bin/sh) won't pickup the extended PATH, so overriding it to bash.
ifeq ($(shell uname),Darwin)
export SHELL := /bin/bash
endif

include scala.mk  # for scala-build, scala-test-build, scala-assembly-jar, scala-clean, etc. targets


### test recipes #############################################################

test/*/scalatests/%.bats: test/postgresql/update-scalatests.bats.sh $(SCALA_TEST_SOURCES)
	# Regenerating .bats for Scala tests
	$<

# make sure test is against the code built and staged by this Makefile
DEEPDIVE_HOME := $(realpath $(STAGE_DIR))
export DEEPDIVE_HOME

include test/bats.mk

.PHONY: checkstyle
checkstyle:
	test/checkstyle.sh


### submodule build recipes ###################################################

.PHONY: build-sampler
build-sampler:
	git submodule update --init sampler
	[ -e sampler/lib/gtest -a -e sampler/lib/tclap ] || $(MAKE) -C sampler dep
	$(MAKE) -C sampler dw
ifeq ($(shell uname),Linux)
	cp -f sampler/dw util/sampler-dw-linux
endif
ifeq ($(shell uname),Darwin)
	cp -f sampler/dw util/sampler-dw-mac
endif

# format_converter
ifeq ($(shell uname),Linux)
test-build build: util/format_converter_linux
util/format_converter_linux: src/main/c/binarize.cpp
	$(CXX) -Os -o $@ $^
endif
ifeq ($(shell uname),Darwin)
test-build build: util/format_converter_mac
util/format_converter_mac: src/main/c/binarize.cpp
	$(CXX) -Os -o $@ $^
endif

.PHONY: build-mindbender
build-mindbender:
	git submodule update --init mindbender
	$(MAKE) -C mindbender clean-packages
	$(MAKE) -C mindbender package

.PHONY: build-ddlog
build-ddlog:
	git submodule update --init ddlog
	$(MAKE) -C ddlog ddlog.jar
	cp -f ddlog/ddlog.jar util/ddlog.jar
test-build build: build-ddlog build-sampler
