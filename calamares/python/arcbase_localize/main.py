#!/usr/bin/env python3
# =============================================================================
#  arcbase_localize — modulo di Calamares: lingua di sistema e tastiera di KDE
#
#  Al posto di "localecfg", che per generare le locale usa locale-gen: in
#  Arcbase (LFS) non c'è, le locale si generano con localedef. La ISO ne ha
#  poche (C.UTF-8, la lingua di ARC_LOCALE e ARC_EXTRA_LOCALES): se l'utente ne
#  sceglie un'altra, qui la si genera nel sistema installato.
#
#    1. genera con localedef le locale scelte che mancano
#    2. scrive /etc/locale.conf (da Global Storage: localeConf)
#    3. scrive /etc/xdg/kxkbrc, il layout di tastiera di KDE/Wayland (il modulo
#       keyboard di Calamares scrive solo la configurazione di X11 e della console)
# =============================================================================
import os
import re

import libcalamares

import gettext
_ = gettext.translation("calamares-python",
                        localedir=libcalamares.utils.gettext_path(),
                        languages=libcalamares.utils.gettext_languages(),
                        fallback=True).gettext

DEFAULT_LOCALE_CONF = {"LANG": "en_US.UTF-8"}
LOCALEDEF_TIMEOUT = 300


def pretty_name():
    return _("Configuring language and keyboard.")


def normalize(name):
    """
    Il nome di una locale come lo stampa `locale -a`: it_IT.UTF-8 -> it_IT.utf8
    (glibc normalizza il set di caratteri: minuscole, senza trattini).
    """
    lang, dot, rest = name.partition(".")
    charset, at, modifier = rest.partition("@")
    if not dot:
        lang, at, modifier = lang.partition("@")
        return lang + (at + modifier if at else "")
    return lang + "." + re.sub(r"[^a-z0-9]", "", charset.lower()) + (at + modifier if at else "")


def localedef_args(name):
    """
    Argomenti di localedef per generare @p name (it_IT.UTF-8 -> -i it_IT -f UTF-8),
    oppure None se non c'è niente da generare (C, POSIX, C.UTF-8: glibc le ha già).
    """
    if name in ("", "C", "POSIX") or name.startswith("C."):
        return None
    lang, dot, rest = name.partition(".")
    charset, at, modifier = rest.partition("@")
    if not dot:
        lang, at, modifier = name.partition("@")
        charset = "UTF-8"
    return ["localedef", "-i", lang + (at + modifier if at else ""), "-f", charset or "UTF-8", name]


def usable_locales(locale_conf, available, fallback):
    """
    Le locale di @p locale_conf (mappa LANG, LC_*...), con quelle che non è
    possibile avere sostituite da @p fallback.
    """
    avail = {normalize(a) for a in available}
    out = {}
    for key, value in locale_conf.items():
        ok = localedef_args(value) is None or normalize(value) in avail
        out[key] = value if ok else fallback
    return out


def locale_conf_text(locale_conf):
    """Il testo di /etc/locale.conf: LANG per primo, poi le altre in ordine."""
    keys = sorted(locale_conf, key=lambda k: (k != "LANG", k))
    return "".join("{0}={1}\n".format(k, locale_conf[k]) for k in keys)


def kxkbrc_text(layout, variant="", extra_layout="", extra_variant="", group_switcher=""):
    """
    Il [Layout] di kxkbrc (KDE): LayoutList e VariantList vanno in parallelo, uno
    per layout; Calamares aggiunge un secondo layout quando il primo non è latino.
    """
    layouts = [layout] + ([extra_layout] if extra_layout else [])
    variants = [variant or ""] + ([extra_variant or ""] if extra_layout else [])
    lines = ["[Layout]", "LayoutList=" + ",".join(layouts)]
    if any(variants):
        lines.append("VariantList=" + ",".join(variants))
    if group_switcher:
        lines.append("Options=" + group_switcher)
    lines.append("Use=true")
    return "\n".join(lines) + "\n"


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def installed_locales():
    out = libcalamares.utils.check_target_env_output(["locale", "-a"], "", 60)
    return [line.strip() for line in str(out).splitlines() if line.strip()]


def run():
    gs = libcalamares.globalstorage
    cfg = libcalamares.job.configuration or {}
    fallback = str(cfg.get("fallbackLocale", "C.UTF-8"))

    root = gs.value("rootMountPoint")
    if not root:
        return (_("Configuration error"), _("No root mount point is given for {0} to use.").format("arcbase_localize"))

    locale_conf = dict(gs.value("localeConf") or DEFAULT_LOCALE_CONF)

    # 1. locale mancanti
    try:
        available = installed_locales()
    except Exception as e:      # locale -a non parte: si genera e si spera
        libcalamares.utils.warning("locale -a failed: {0}".format(e))
        available = []
    for name in sorted(set(locale_conf.values())):
        args = localedef_args(name)
        if args is None or normalize(name) in {normalize(a) for a in available}:
            continue
        libcalamares.utils.debug("Generating locale " + name)
        # localedef esce con 1 anche se ha solo avvisi: conta cosa c'è dopo
        libcalamares.utils.target_env_call(args, "", LOCALEDEF_TIMEOUT)
    try:
        available = installed_locales()
    except Exception:
        pass
    final = usable_locales(locale_conf, available, fallback)
    for key in locale_conf:
        if final[key] != locale_conf[key]:
            libcalamares.utils.warning("Locale {0} is not available: using {1} for {2}".format(
                locale_conf[key], final[key], key))

    # 2. /etc/locale.conf
    write(os.path.join(root, "etc", "locale.conf"), locale_conf_text(final))

    # 3. tastiera di KDE
    layout = gs.value("keyboardLayout")
    if layout:
        write(os.path.join(root, "etc", "xdg", "kxkbrc"), kxkbrc_text(
            layout, gs.value("keyboardVariant") or "",
            gs.value("keyboardAdditionalLayout") or "",
            gs.value("keyboardAdditionalVariant") or "",
            gs.value("keyboardGroupSwitcher") or ""))
    return None
