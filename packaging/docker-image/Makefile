# PROJECT_VERSION defaults to:
#   1. the version exported by rabbitmq-server-release;
#   2. the version stored in `git-revisions.txt`, if it exists;
#   3. a version based on git-describe(1), if it is a Git clone;
#   4. 0.0.0

PROJECT_VERSION := $(RABBITMQ_VERSION)

ifeq ($(PROJECT_VERSION),)
PROJECT_VERSION := $(shell \
if test -f git-revisions.txt; then \
	head -n1 git-revisions.txt | \
	awk '{print $$$(words $(PROJECT_DESCRIPTION) version);}'; \
else \
	(git describe --dirty --abbrev=7 --tags --always --first-parent \
	 2>/dev/null || echo rabbitmq_v0_0_0) | \
	sed -e 's/^rabbitmq_v//' -e 's/^v//' -e 's/_/./g' -e 's/-/+/' \
	 -e 's/-/./g'; \
fi)
endif

ifeq ($(filter-out all dist push clean,$(MAKECMDGOALS)),)
GENERIC_UNIX_ARCHIVE ?= $(wildcard $(PACKAGES_DIR)/rabbitmq-server-generic-unix-$(PROJECT_VERSION).tar.xz)

ifeq ($(GENERIC_UNIX_ARCHIVE),)
$(error Cannot find generic-unix archive; please specify GENERIC_UNIX_ARCHIVE)
endif

VERSION ?= $(patsubst rabbitmq-server-generic-unix-%.tar.xz,%,$(notdir $(GENERIC_UNIX_ARCHIVE)))
ifeq ($(VERSION),)
$(error Cannot determine version; please specify VERSION)
endif

IMAGE_TAG_1 ?= $(subst +,-,$(VERSION))
endif

REPO ?= pivotalrabbitmq/rabbitmq

all: dist

dist:
	cp -f $(GENERIC_UNIX_ARCHIVE) package-generic-unix.tar.xz
	docker build --pull \
	  --build-arg RABBITMQ_VERSION=$(VERSION) \
	  --tag $(REPO):$(IMAGE_TAG_1) \
	  .

push:
	docker push $(REPO):$(IMAGE_TAG_1)
ifdef IMAGE_TAG_2
	docker tag $(REPO):$(IMAGE_TAG_1) $(REPO):$(IMAGE_TAG_2)
	docker push $(REPO):$(IMAGE_TAG_2)
endif

clean:
	rm -f rabbitmq_server-*
