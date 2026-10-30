#!/usr/bin/env python3
# =============================================================================
#  Prove dei moduli di Calamares scritti per Arcbase (calamares/python/) senza
#  Calamares: al posto di `libcalamares` c'è un finto che registra le chiamate.
#  Lo lancia tests/test-calamares.sh ("python3 -I tests/calamares_modules_test.py").
# =============================================================================
import importlib.util
import os
import sys
import tempfile
import types
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class FakeCalamares(types.ModuleType):
    """Il minimo di libcalamares che i moduli usano."""

    def __init__(self):
        super().__init__("libcalamares")
        self.calls = []             # (argv, timeout) di target_env_call
        self.warnings = []
        self.target_rc = 0          # esito di target_env_call
        self.locale_output = ""     # cosa stampa `locale -a` nel target
        self.on_call = None         # funzione(argv) chiamata a ogni target_env_call
        self.gs = {}
        self.job = types.SimpleNamespace(configuration={})
        self.globalstorage = types.SimpleNamespace(value=lambda k: self.gs.get(k))
        self.utils = types.SimpleNamespace(
            gettext_path=lambda: "/nonexistent",
            gettext_languages=lambda: [],
            debug=lambda s: None,
            warning=self.warnings.append,
            target_env_call=self._call,
            check_target_env_output=lambda argv, inp="", timeout=0: self.locale_output,
        )

    def _call(self, argv, inp="", timeout=0):
        self.calls.append((list(argv), timeout))
        if self.on_call:
            self.on_call(argv)
        return self.target_rc


def load(name, fake):
    """Carica calamares/python/<name>/main.py con @p fake al posto di libcalamares."""
    sys.modules["libcalamares"] = fake
    path = os.path.join(REPO, "calamares", "python", name, "main.py")
    spec = importlib.util.spec_from_file_location("test_" + name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ROOT = {"device": "/dev/vda2", "mountPoint": "/", "fs": "ext4"}
ESP = {"device": "/dev/vda1", "mountPoint": "/boot/efi", "fs": "fat32"}
# lsblk finto: le partizioni di vda hanno per genitore vda, vda non ne ha
PARENT = {"/dev/vda1": "vda", "/dev/vda2": "vda", "/dev/vda": "", "/dev/vdb": "", "/dev/vdb1": "vdb"}


def lsblk(dev):
    return PARENT.get(dev, "")


class Bootloader(unittest.TestCase):
    def setUp(self):
        self.fake = FakeCalamares()
        self.m = load("arcbase_bootloader", self.fake)

    def test_bios_disco_scelto(self):
        cmds = self.m.plan([ROOT], {"installPath": "/dev/vda"}, False, "quiet", lsblk)
        self.assertEqual(cmds, [["arcbase-bootloader", "--disk", "/dev/vda", "--root", "/dev/vda2",
                                 "--no-fstab", "--cmdline", "quiet"]])

    def test_bios_partizione_scelta_diventa_il_disco(self):
        # "installa nel settore di avvio della partizione" non è utilizzabile: si usa il disco
        cmds = self.m.plan([ROOT], {"installPath": "/dev/vda2"}, False, "quiet", lsblk)
        self.assertEqual(cmds[0][2], "/dev/vda")

    def test_bios_senza_bootloader(self):
        self.assertEqual(self.m.plan([ROOT], None, False, "quiet", lsblk), [])

    def test_uefi(self):
        cmds = self.m.plan([ESP, ROOT], {"installPath": "/dev/vda1"}, True, "quiet splash", lsblk)
        self.assertEqual(len(cmds), 2)
        main, fallback = cmds
        self.assertEqual(main, ["arcbase-bootloader", "--disk", "/dev/vda", "--root", "/dev/vda2",
                                "--no-fstab", "--cmdline", "quiet splash", "--esp", "/dev/vda1", "--no-bios"])
        # percorso di ripiego \EFI\BOOT\BOOTX64.EFI per i firmware che dimenticano le voci
        self.assertEqual(fallback, ["grub-install", "--target=x86_64-efi", "--efi-directory=/boot/efi",
                                    "--removable", "--no-nvram"])

    def test_uefi_il_disco_e_quello_della_root(self):
        # ESP su un altro disco rispetto a installPath: conta la root
        root_b = dict(ROOT, device="/dev/vdb1")
        cmds = self.m.plan([ESP, root_b], {"installPath": "/dev/vda1"}, True, "quiet", lsblk)
        self.assertEqual(cmds[0][2], "/dev/vdb")

    def test_uefi_senza_esp(self):
        with self.assertRaises(self.m.BootloaderError):
            self.m.plan([ROOT], None, True, "quiet", lsblk)

    def test_esp_su_un_altro_punto_di_montaggio(self):
        # arcbase-bootloader si aspetta la ESP su /boot/efi
        with self.assertRaises(self.m.BootloaderError):
            self.m.plan([dict(ESP, mountPoint="/efi"), ROOT], None, True, "quiet", lsblk)

    def test_root_non_ext4(self):
        # senza initramfs btrfs/xfs (moduli del kernel) non si avviano
        for fs in ("btrfs", "xfs", "f2fs"):
            with self.assertRaises(self.m.BootloaderError, msg=fs):
                self.m.plan([dict(ROOT, fs=fs)], {"installPath": "/dev/vda"}, False, "quiet", lsblk)

    def test_senza_root(self):
        with self.assertRaises(self.m.BootloaderError):
            self.m.plan([ESP], {"installPath": "/dev/vda"}, False, "quiet", lsblk)

    def test_run_esegue_nel_target(self):
        self.fake.gs = {"partitions": [ROOT], "bootLoader": {"installPath": "/dev/vda"}}
        self.fake.job.configuration = {"kernelCmdline": "quiet loglevel=3"}
        self.m.is_efi_firmware = lambda: False
        self.m.parent_disk = lambda dev, lsblk=None: "/dev/vda"
        self.assertIsNone(self.m.run())
        (argv, timeout), = self.fake.calls
        self.assertEqual(argv[0], "arcbase-bootloader")
        self.assertIn("quiet loglevel=3", argv)
        self.assertGreaterEqual(timeout, 300)

    def test_run_errore_di_grub(self):
        self.fake.gs = {"partitions": [ROOT], "bootLoader": {"installPath": "/dev/vda"}}
        self.fake.target_rc = 1
        self.m.is_efi_firmware = lambda: False
        self.m.parent_disk = lambda dev, lsblk=None: "/dev/vda"
        result = self.m.run()
        self.assertIsInstance(result, tuple)    # (titolo, descrizione) per l'utente
        self.assertIn("bios_grub", result[1])

    def test_run_errore_di_configurazione(self):
        self.fake.gs = {"partitions": [dict(ROOT, fs="btrfs")], "bootLoader": {"installPath": "/dev/vda"}}
        self.m.is_efi_firmware = lambda: False
        result = self.m.run()
        self.assertIsInstance(result, tuple)
        self.assertEqual(self.fake.calls, [])   # non si è toccato nulla


class Localize(unittest.TestCase):
    def setUp(self):
        self.fake = FakeCalamares()
        self.m = load("arcbase_localize", self.fake)

    def test_normalize(self):
        n = self.m.normalize
        self.assertEqual(n("it_IT.UTF-8"), "it_IT.utf8")
        self.assertEqual(n("it_IT.utf8"), "it_IT.utf8")
        self.assertEqual(n("de_DE@euro"), "de_DE@euro")
        self.assertEqual(n("de_DE.ISO-8859-15@euro"), "de_DE.iso885915@euro")
        self.assertEqual(n("C.UTF-8"), "C.utf8")

    def test_localedef_args(self):
        a = self.m.localedef_args
        self.assertEqual(a("it_IT.UTF-8"), ["localedef", "-i", "it_IT", "-f", "UTF-8", "it_IT.UTF-8"])
        self.assertEqual(a("de_DE@euro"), ["localedef", "-i", "de_DE@euro", "-f", "UTF-8", "de_DE@euro"])
        self.assertEqual(a("sr_RS.UTF-8@latin"),
                         ["localedef", "-i", "sr_RS@latin", "-f", "UTF-8", "sr_RS.UTF-8@latin"])
        # glibc ha già C, POSIX e C.UTF-8
        for name in ("C", "POSIX", "C.UTF-8", ""):
            self.assertIsNone(a(name), name)

    def test_usable_locales(self):
        out = self.m.usable_locales({"LANG": "de_DE.UTF-8", "LC_TIME": "it_IT.UTF-8", "LC_PAPER": "C"},
                                    ["C", "C.utf8", "it_IT.utf8"], "C.UTF-8")
        self.assertEqual(out, {"LANG": "C.UTF-8", "LC_TIME": "it_IT.UTF-8", "LC_PAPER": "C"})

    def test_locale_conf_text(self):
        text = self.m.locale_conf_text({"LC_TIME": "it_IT.UTF-8", "LANG": "it_IT.UTF-8", "LC_PAPER": "it_IT.UTF-8"})
        self.assertEqual(text.splitlines(), ["LANG=it_IT.UTF-8", "LC_PAPER=it_IT.UTF-8", "LC_TIME=it_IT.UTF-8"])

    def test_kxkbrc(self):
        k = self.m.kxkbrc_text
        self.assertEqual(k("it"), "[Layout]\nLayoutList=it\nUse=true\n")
        self.assertEqual(k("us", "intl"), "[Layout]\nLayoutList=us\nVariantList=intl\nUse=true\n")
        # secondo layout (primo non latino) e cambio con Alt+Maiusc: le liste vanno in parallelo
        self.assertEqual(k("ru", "", "us", "intl", "grp:alt_shift_toggle"),
                         "[Layout]\nLayoutList=ru,us\nVariantList=,intl\nOptions=grp:alt_shift_toggle\nUse=true\n")

    def run_module(self, root, **gs):
        self.fake.gs = dict({"rootMountPoint": root}, **gs)
        return self.m.run()

    def test_run_genera_la_locale_mancante(self):
        self.fake.locale_output = "C\nC.utf8\nPOSIX\nit_IT.utf8\n"
        # localedef "riesce": dopo la chiamata la locale compare in `locale -a`
        self.fake.on_call = lambda argv: setattr(
            self.fake, "locale_output", self.fake.locale_output + "de_DE.utf8\n")
        with tempfile.TemporaryDirectory() as root:
            res = self.run_module(root, localeConf={"LANG": "de_DE.UTF-8", "LC_TIME": "it_IT.UTF-8"},
                                  keyboardLayout="de", keyboardVariant="")
            self.assertIsNone(res)
            with open(os.path.join(root, "etc/locale.conf")) as f:
                self.assertEqual(f.read(), "LANG=de_DE.UTF-8\nLC_TIME=it_IT.UTF-8\n")
            with open(os.path.join(root, "etc/xdg/kxkbrc")) as f:
                self.assertEqual(f.read(), "[Layout]\nLayoutList=de\nUse=true\n")
        # solo la locale che mancava è stata generata
        self.assertEqual([c[0] for c in self.fake.calls],
                         [["localedef", "-i", "de_DE", "-f", "UTF-8", "de_DE.UTF-8"]])
        self.assertEqual(self.fake.warnings, [])

    def test_run_ripiega_se_la_locale_non_si_genera(self):
        self.fake.locale_output = "C\nC.utf8\nPOSIX\n"      # localedef non produce nulla
        with tempfile.TemporaryDirectory() as root:
            self.assertIsNone(self.run_module(root, localeConf={"LANG": "xx_XX.UTF-8"}))
            with open(os.path.join(root, "etc/locale.conf")) as f:
                self.assertEqual(f.read(), "LANG=C.UTF-8\n")
        self.assertTrue(any("xx_XX.UTF-8" in w for w in self.fake.warnings))

    def test_run_locale_gia_presente_non_rigenerata(self):
        self.fake.locale_output = "C\nC.utf8\nPOSIX\nit_IT.utf8\nen_US.utf8\n"
        with tempfile.TemporaryDirectory() as root:
            self.run_module(root, localeConf={"LANG": "it_IT.UTF-8"})
        self.assertEqual(self.fake.calls, [])

    def test_run_senza_tastiera_non_scrive_kxkbrc(self):
        self.fake.locale_output = "C\nC.utf8\nit_IT.utf8\n"
        with tempfile.TemporaryDirectory() as root:
            self.run_module(root, localeConf={"LANG": "it_IT.UTF-8"})
            self.assertFalse(os.path.exists(os.path.join(root, "etc/xdg/kxkbrc")))

    def test_run_senza_root(self):
        self.assertIsInstance(self.run_module(None), tuple)


if __name__ == "__main__":
    unittest.main(verbosity=1)
