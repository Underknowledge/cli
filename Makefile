all: lint test build

ci: test build

.PHONY: all ci

#################################################
# Determine the type of `push` and `version`
#################################################

# If TRAVIS_TAG is set then we know this ref has been tagged.
ifdef TRAVIS_TAG
VERSION ?= $(TRAVIS_TAG)
NOT_RC  := $(shell echo $(VERSION) | grep -v -e -rc)
	ifeq ($(NOT_RC),)
PUSHTYPE := release-candidate
	else
PUSHTYPE := release
	endif
# GITHUB Actions
else ifdef GITHUB_REF
VERSION ?= $(shell echo $(GITHUB_REF) | sed 's/^refs\/tags\///')
NOT_RC  := $(shell echo $(VERSION) | grep -v -e -rc)
	ifeq ($(NOT_RC),)
PUSHTYPE := release-candidate
	else
PUSHTYPE := release
	endif
else
VERSION ?= $(shell [ -d .git ] && git describe --tags --always --dirty="-dev")
# If we are not in an active git dir then try reading the version from .VERSION.
# .VERSION contains a slug populated by `git archive`.
VERSION := $(or $(VERSION),$(shell ./.version.sh .VERSION))
	ifeq ($(TRAVIS_BRANCH),master)
PUSHTYPE := master
	else
PUSHTYPE := branch
	endif
endif

VERSION := $(shell echo $(VERSION) | sed 's/^v//')
DEB_VERSION := $(shell echo $(VERSION) | sed 's/-/~/')

ifdef V
$(info    TRAVIS_TAG is $(TRAVIS_TAG))
$(info    GITHUB_REF is $(GITHUB_REF))
$(info    VERSION is $(VERSION))
$(info    DEB_VERSION is $(DEB_VERSION))
$(info    PUSHTYPE is $(PUSHTYPE))
endif

include make/common.mk
include make/docker.mk

#########################################
# Debian
#########################################

changelog:
	$Q echo "step-cli ($(DEB_VERSION)) unstable; urgency=medium" > debian/changelog
	$Q echo >> debian/changelog
	$Q echo "  * See https://github.com/smallstep/cli/releases" >> debian/changelog
	$Q echo >> debian/changelog
	$Q echo " -- Smallstep Labs, Inc. <techadmin@smallstep.com>  $(shell date -uR)" >> debian/changelog

debian: changelog
	$Q set -e; mkdir -p $(RELEASE); \
	OUTPUT=../step-cli_*.deb; \
	rm -f $$OUTPUT; \
	dpkg-buildpackage -b -rfakeroot -us -uc && cp $$OUTPUT $(RELEASE)/

distclean: clean

.PHONY: changelog debian distclean

#################################################
# Build statically compiled step binary for various operating systems
#################################################

BINARY_OUTPUT=$(OUTPUT_ROOT)binary/
RELEASE=./dist

define BUNDLE_MAKE
	# $(1) -- Go Operating System (e.g. linux, darwin, windows, etc.)
	# $(2) -- Go Architecture (e.g. amd64, arm, arm64, etc.)
	# $(3) -- Go ARM architectural family (e.g. 7, 8, etc.)
	# $(4) -- Parent directory for executables generated by 'make'.
	$(q) GOOS_OVERRIDE='GOOS=$(1) GOARCH=$(2) GOARM=$(3)' PREFIX=$(4) make $(4)bin/step
endef

binary-linux:
	$(call BUNDLE_MAKE,linux,amd64,,$(BINARY_OUTPUT)linux/)

binary-linux-arm64:
	$(call BUNDLE_MAKE,linux,arm64,,$(BINARY_OUTPUT)linux.arm64/)

binary-linux-armv7:
	$(call BUNDLE_MAKE,linux,arm,7,$(BINARY_OUTPUT)linux.armv7/)

binary-linux-mips:
	$(call BUNDLE_MAKE,linux,mips,,$(BINARY_OUTPUT)linux.mips/)

binary-darwin:
	$(call BUNDLE_MAKE,darwin,amd64,,$(BINARY_OUTPUT)darwin/)

binary-windows:
	$(call BUNDLE_MAKE,windows,amd64,,$(BINARY_OUTPUT)windows/)

define BUNDLE
    # $(1) -- Format output as .ZIP archive, rather than .tar.gzip (for older windows architecture)
	# $(2) -- Binary Output Dir Name
	# $(3) -- Step Platform Name
	# $(4) -- Step Binary Architecture
	# $(5) -- Step Binary Name (For Windows Comaptibility)
	$(q) ./make/bundle.sh $(1) "$(BINARY_OUTPUT)$(2)" "$(RELEASE)" "$(VERSION)" "$(3)" "$(4)" "$(5)"
endef

bundle-linux: binary-linux binary-linux-arm64 binary-linux-armv7 binary-linux-mips
	$(call BUNDLE,,linux,linux,amd64,step)
	$(call BUNDLE,,linux.arm64,linux,arm64,step)
	$(call BUNDLE,,linux.armv7,linux,armv7,step)
	$(call BUNDLE,,linux.mips,linux,mips,step)

bundle-darwin: binary-darwin
	$(call BUNDLE,,darwin,darwin,amd64,step)

bundle-windows: binary-windows
	$(call BUNDLE,,windows,windows,amd64,step.exe)
	$(call BUNDLE,--zip,windows,windows,amd64,step.exe)

.PHONY: binary-linux binary-darwin binary-windows bundle-linux bundle-darwin bundle-windows

#################################################
# Targets for creating step artifacts
#################################################

docker-artifacts: docker-$(PUSHTYPE)

.PHONY: docker-artifacts
