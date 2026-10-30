#!/usr/bin/env python3
# =============================================================================
#  arcbase_bootloader — modulo di Calamares: installa GRUB (BIOS o UEFI)
#
#  Il sistema installato non usa initramfs: il kernel monta la root con
#  root=PARTUUID=..., e il menu di GRUB lo scrive arcbase-grub-cfg. Per questo
#  non si usa il modulo "bootloader" di Calamares (grub-mkconfig, initramfs) ma
#  arcbase-bootloader, lo stesso strumento di arcbase-install e delle immagini.
#
#  Dispositivi dalle informazioni che Calamares lascia in Global Storage:
#    partitions  elenco di {device, mountPoint, fs, ...} di ogni partizione
#    bootLoader  {installPath} scelto nella pagina delle partizioni (BIOS)
#  L'/etc/fstab lo scrive il modulo fstab di Calamares (swap e partizioni extra
#  comprese): arcbase-bootloader si chiama con --no-fstab.
# =============================================================================
import os
import subprocess

import libcalamares

import gettext
_ = gettext.translation("calamares-python",
                        localedir=libcalamares.utils.gettext_path(),
                        languages=libcalamares.utils.gettext_languages(),
                        fallback=True).gettext

ESP_MOUNT = "/boot/efi"     # dove arcbase-bootloader si aspetta la ESP
TIMEOUT = 900               # grub-install su un disco lento


def pretty_name():
    return _("Installing the boot loader.")


class BootloaderError(Exception):
    """Errore da mostrare all'utente: (titolo, descrizione)."""

    def __init__(self, title, description):
        super().__init__(title, description)
        self.title = title
        self.description = description


def find_partition(partitions, mount_point):
    """La partizione montata su @p mount_point, o None."""
    for p in partitions or []:
        if p.get("mountPoint") == mount_point:
            return p
    return None


def parent_disk(device, lsblk=None):
    """
    Il disco intero a cui appartiene @p device (che può essere il disco stesso).
    """
    if lsblk is None:
        def lsblk(dev):
            out = subprocess.run(["lsblk", "-ndo", "PKNAME", dev], capture_output=True, text=True)
            return out.stdout.strip() if out.returncode == 0 else ""
    parent = lsblk(device)
    return "/dev/" + parent if parent else device


def is_efi_firmware():
    return os.path.isdir("/sys/firmware/efi")


def plan(partitions, boot_loader, efi, cmdline, lsblk=None):
    """
    Decide cosa fare: ritorna l'elenco dei comandi da eseguire nel sistema
    installato, oppure [] se l'utente ha scelto di non installare il bootloader.
    Solleva BootloaderError se la scelta dei dischi non permette di avviarsi.
    """
    root = find_partition(partitions, "/")
    if root is None:
        raise BootloaderError(_("Boot loader error"), _("No root partition was found."))
    if root.get("fs") != "ext4":
        # Senza initramfs il kernel monta solo ciò che ha built-in: ext4
        raise BootloaderError(
            _("Unsupported root file system"),
            _("The root partition must be ext4 (it is {0}): the installed system has no "
              "initramfs, so the kernel can only mount a root it has built in.").format(root.get("fs")))

    # In BIOS la pagina delle partizioni lascia in bootLoader il disco scelto;
    # vuoto significa "nessun bootloader", scelto dall'utente (come fa il modulo
    # bootloader di Calamares: avvisa e va avanti)
    if not efi and not boot_loader:
        return []
    # In UEFI il bootloader sta nella ESP: il disco serve solo come argomento
    # (senza GRUB per BIOS), si prende quello della root
    install_path = boot_loader.get("installPath") if isinstance(boot_loader, dict) else None
    disk = parent_disk(root["device"] if efi or not install_path else install_path, lsblk)

    cmd = ["arcbase-bootloader", "--disk", disk, "--root", root["device"],
           "--no-fstab", "--cmdline", cmdline]
    commands = []
    if efi:
        esp = find_partition(partitions, ESP_MOUNT)
        if esp is None:
            raise BootloaderError(
                _("No EFI system partition"),
                _("This computer started in UEFI mode, so a FAT32 EFI system partition "
                  "mounted on {0} is needed.").format(ESP_MOUNT))
        # La voce nella NVRAM di UEFI; GRUB per BIOS non serve (e senza una
        # partizione "BIOS boot" su un disco GPT darebbe errore)
        cmd += ["--esp", esp["device"], "--no-bios"]
        commands.append(cmd)
        # Alcuni firmware dimenticano le voci: percorso di ripiego \EFI\BOOT\BOOTX64.EFI
        commands.append(["grub-install", "--target=x86_64-efi", "--efi-directory=" + ESP_MOUNT,
                         "--removable", "--no-nvram"])
    else:
        commands.append(cmd)
    return commands


def run():
    gs = libcalamares.globalstorage
    cfg = libcalamares.job.configuration or {}
    cmdline = str(cfg.get("kernelCmdline", "quiet"))

    try:
        commands = plan(gs.value("partitions"), gs.value("bootLoader"), is_efi_firmware(), cmdline)
    except BootloaderError as e:
        return (e.title, e.description)

    if not commands:
        libcalamares.utils.warning("No boot loader requested: the system will not be bootable by itself.")
        return None

    for cmd in commands:
        libcalamares.utils.debug("Running in the target: " + " ".join(cmd))
        rc = libcalamares.utils.target_env_call(cmd, "", TIMEOUT)
        if rc != 0:
            return (_("Boot loader installation failed"),
                    _("{0} exited with status {1}. On a GPT disk started in BIOS mode a small "
                      "\"BIOS boot\" partition (flag bios_grub) is needed; see the installation "
                      "log for the details.").format(cmd[0], rc))
    return None
