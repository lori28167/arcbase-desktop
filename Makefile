# =============================================================================
#  Arcbase Desktop — build system
#
#  make help        elenco dei target
#  make all         build completa (ore!): dal controllo dell'host all'immagine
#
#  Tutti i target di build vanno eseguiti come root (sudo make ...).
#  Ogni stadio è riprendibile: i pacchetti già compilati vengono saltati.
# =============================================================================
SHELL := /bin/bash
S     := scripts

.PHONY: help all check prepare download toolchain temp-tools chroot-tools \
        base-system merge-usr config kernel package-managers desktop image \
        enter umount lint test clean-stamps

help:
	@echo "Arcbase Desktop — LFS + pacman (Arch) + apt (Debian)"
	@echo
	@echo "Stadi (in ordine):"
	@echo "  check             verifica i requisiti dell'host"
	@echo "  prepare           prepara \$$LFS (partizione montata) e l'utente lfs"
	@echo "  download          scarica tutti i sorgenti"
	@echo "  toolchain         LFS cap. 5: cross-toolchain (utente lfs)"
	@echo "  temp-tools        LFS cap. 6: strumenti temporanei (utente lfs)"
	@echo "  chroot-tools      LFS cap. 7: chroot e strumenti aggiuntivi"
	@echo "  base-system       LFS cap. 8: sistema base + Linux-PAM"
	@echo "  merge-usr         layout /usr compatibile con Arch (sbin -> bin)"
	@echo "  config            LFS cap. 9: configurazione, utenti, identità"
	@echo "  kernel            LFS cap. 10: kernel + GRUB BIOS/UEFI"
	@echo "  package-managers  pacman, arcbase-base, layer apt/dpkg, arc"
	@echo "  desktop           desktop (\$$ARC_DESKTOP) dai repository Arch + layer Debian"
	@echo "  image             immagine disco avviabile in out/"
	@echo
	@echo "Altro:"
	@echo "  all               tutti gli stadi in sequenza"
	@echo "  enter             shell nel chroot   |  umount  smonta il chroot"
	@echo "  lint / test       shellcheck e test di 'arc' (non richiedono root)"
	@echo "  clean-stamps      forza la ricompilazione di tutto"

all: check prepare download toolchain temp-tools chroot-tools base-system \
     merge-usr config kernel package-managers desktop image

check:
	$(S)/00-host-check.sh

prepare:
	$(S)/01-prepare.sh

download:
	$(S)/02-download.sh

toolchain:
	$(S)/03-cross-toolchain.sh

temp-tools:
	$(S)/04-temp-tools.sh

chroot-tools:
	$(S)/05-chroot.sh run 06-chroot-tools.sh

base-system:
	$(S)/05-chroot.sh run 07-base-system.sh

merge-usr:
	$(S)/05-chroot.sh merge-usr

config:
	$(S)/05-chroot.sh run 08-system-config.sh

kernel:
	$(S)/05-chroot.sh run 09-kernel-boot.sh

package-managers:
	$(S)/05-chroot.sh run 10-package-managers.sh

desktop:
	$(S)/05-chroot.sh run 11-desktop.sh

image:
	$(S)/12-image.sh

enter:
	$(S)/05-chroot.sh enter

umount:
	$(S)/05-chroot.sh umount

lint:
	shellcheck -x $(S)/*.sh $(S)/lib/common.sh $(S)/chroot/*.sh \
	    rootfs/usr/bin/arc rootfs/usr/bin/arcbase-* \
	    rootfs/usr/lib/arcbase/*.sh rootfs/usr/share/libalpm/scripts/* \
	    tests/*.sh

test:
	tests/test-recipes.sh
	tests/test-build-engine.sh
	tests/test-arc.sh

clean-stamps:
	@source config/arcbase.conf && rm -rfv "$$LFS/sources/.arcbase-stamps"
