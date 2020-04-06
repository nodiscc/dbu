#!/usr/bin/make -f
# Change the default shell /bin/sh which does not implement 'source'
# source is needed to work in a python virtualenv
SHELL := /bin/bash

# remove 'download_extra' to build without third party software/dotfiles
all: install_buildenv clean download_extra build

download_extra:
	make -f Makefile.extra

install_buildenv:
	# Install packages required to build the image
	sudo apt install live-build make build-essential wget git xmlstarlet unzip colordiff shellcheck apt-transport-https rename ovmf rsync

##############################

# clear all caches, only required when changing the mirrors/architecture config
clean:
	sudo lb clean --purge
	git clean -di

bump_version:
	@last_tag=$$(git tag | tail -n1); \
	echo "Please set version to $$last_tag in Makefile config/bootloaders/isolinux/live.cfg.in config/bootloaders/isolinux/menu.cfg auto/config doc/md/download-and-installation.md"

build:
	# Build the live system/ISO image
	sudo lb clean --all
	sudo lb config
	sudo lb build

##############################

release: checksums sign_checksums release_archive

checksums:
	# Generate checksums of the resulting ISO image
	@mkdir -p iso/
	mv *.iso iso/
	last_tag=$$(git tag | tail -n1); \
	cd iso/; \
	rename "s/live-image/dlc-$$last_tag-debian-buster/" *; \
	sha512sum *.iso  > SHA512SUMS; \

sign_checksums:
	# Sign checksums with a GPG private key
	cd iso; \
	gpg --detach-sign --armor SHA512SUMS; \
	mv SHA512SUMS.asc SHA512SUMS.sign

release_archive:
	git archive --format=zip -9 HEAD -o $$(basename $$PWD)-$$(git rev-parse HEAD).zip

################################

tests: test_imagesize download_iso test_kvm_bios test_kvm_uefi

test_imagesize:
	@size=$$(du -b iso/*.iso | cut -f 1); \
	echo "[INFO] ISO image size: $$size bytes"; \
	if [[ "$$size" -gt 2147483648 ]]; then \
		echo '[WARNING] ISO image size is larger than 2GB!'; \
	fi

download_iso:
	# download the iso image from a build server
	rsync -avP buildbot.xinit.se:/var/debian-live-config/debian-live-config/iso ./

test_kvm_bios:
	# Run the resulting image in KVM/virt-manager (legacy BIOS mode)
	sudo virt-install --name dlc-test --boot cdrom --disk path=/dlc-test-disk0.qcow2,format=qcow2,size=20,device=disk,bus=virtio,cache=none --cdrom 'iso/dlc-2.2.2-debian-buster-amd64.hybrid.iso' --memory 2048 --vcpu 2
	sudo virsh destroy dlc-test
	sudo virsh undefine dlc-test
	sudo rm /dlc-test-disk0.qcow2

test_kvm_uefi:
	# Run the resulting image in KVM/virt-manager (UEFI mode)
	# UEFI support must be enabled in QEMU config for EFI install tests https://wiki.archlinux.org/index.php/Libvirt#UEFI_Support (/usr/share/OVMF/*.fd)
	sudo virt-install --name dlc-test --boot loader=/usr/share/OVMF/OVMF_CODE.fd --disk path=/dlc-test-disk0.qcow2,format=qcow2,size=20,device=disk,bus=virtio,cache=none --cdrom 'iso/dlc-2.2.2-debian-buster-amd64.hybrid.iso' --memory 2048 --vcpu 2
	sudo virsh destroy dlc-test
	sudo virsh undefine dlc-test
	sudo rm /dlc-test-disk0.qcow2

#################################

# Update TODO.md by fetching issues from the main gitea instance API
# requirements: sudo apt install git jq
#               gitea-cli config defined in ~/.config/gitearc
update_todo:
	git clone https://github.com/bashup/gitea-cli gitea-cli
	-rm doc/md/TODO.md
	echo '<!-- This file is automatically generated by "make update_todo" -->' > doc/md/TODO.md
	./gitea-cli/bin/gitea issues zerodb/debian-live-config | jq -r '.[] | "- #\(.number) - \(.title)"' >> doc/md/TODO.md; \
	rm -rf gitea-cli

doc: install_dev_docs doc_md doc_html

# install documentation generator (sphinx + markdown + theme)
install_dev_docs:
	python3 -m venv .venv/
	source .venv/bin/activate && pip3 install sphinx recommonmark sphinx_rtd_theme

doc_md:
	cp README.md doc/md/index.md
	cp CHANGELOG.md doc/md/
	cp LICENSE doc/md/LICENSE.md
	sed -i 's|doc/md/||g' doc/md/*.md
	./doc/gen_package_lists.py

# HTML documentation generation (sphinx-build --help)
SPHINXOPTS    ?=
SPHINXBUILD   ?= sphinx-build
SOURCEDIR     = doc/md    # répertoire source (markdown)
BUILDDIR      = doc/html  # répertoire destination (html)
doc_html:
	source .venv/bin/activate && sphinx-build -c doc/md -b html doc/md doc/html
