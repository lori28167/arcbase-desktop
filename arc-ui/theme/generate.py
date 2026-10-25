#!/usr/bin/env python3
# =============================================================================
#  arc UI — genera i temi SVG dai token di arc-ui.css
#
#    <out>/Kvantum/ArcGlass/ArcGlass.{svg,kvconfig}   stile delle app Qt
#  (le decorazioni delle finestre sono un plugin C++: arc-ui/decoration)
#
#  Uso: generate.py --out /usr/share
#  Gli elementi Kvantum sono rettangoli arrotondati divisi in 9 parti (angoli,
#  lati, interno) per ogni stato: normal, focused (hover), pressed, toggled,
#  disabled. Gli elementi mancanti Kvantum li prende dal suo tema di base.
# =============================================================================
import argparse
import os

# --- Token (ArcBase/ui/arc-ui.css, :root) ---------------------------------------
WHITE = (255, 255, 255)
INK = (15, 13, 20)            # --arc-bg / testo su accento bianco
WINDOW = (18, 15, 24)         # vetro delle finestre
CONTENT = (37, 34, 44)        # contenuto incassato (viste, liste) sopra il vetro
MENU = (16, 13, 22)
TOOLTIP = (15, 13, 25)
TEXT = "#f2f0f7"              # --arc-text
MUTED = "#a6a1b0"             # --arc-muted
DISABLED = "#6f6a7a"          # --arc-sub

STATES = ("normal", "focused", "pressed", "toggled", "disabled")


def white(alpha):
    return (WHITE, alpha)


def rgba(rgb, alpha):
    return (rgb, alpha)


def paint(attr, color):
    (r, g, b), a = color
    return '%s="#%02x%02x%02x" %s-opacity="%.3f"' % (attr, r, g, b, attr, a)


def box(x, y, w, h):
    """Rettangolo invisibile: fissa i limiti dell'elemento."""
    return '<rect x="%g" y="%g" width="%g" height="%g" fill="#000000" fill-opacity="0"/>' % (x, y, w, h)


class Svg:
    def __init__(self):
        self.parts = []
        self.cursor_x = 0
        self.cursor_y = 0
        self.row_h = 0

    def place(self, w, h):
        """Posizione libera sulla tela (solo per leggibilità del file)."""
        if self.cursor_x + w > 1200:
            self.cursor_x = 0
            self.cursor_y += self.row_h + 8
            self.row_h = 0
        x, y = self.cursor_x, self.cursor_y
        self.cursor_x += w + 8
        self.row_h = max(self.row_h, h)
        return x, y

    def group(self, ident, w, h, body):
        x, y = self.place(w, h)
        self.parts.append('<g id="%s" transform="translate(%g,%g)">%s%s</g>' % (ident, x, y, box(0, 0, w, h), body))

    def render(self):
        height = self.cursor_y + self.row_h + 8
        return ('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!-- arc UI — generato da arc-ui/theme/generate.py, non modificare a mano -->\n'
                '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="%d" viewBox="0 0 1200 %d">\n%s\n</svg>\n'
                % (height, height, "\n".join(self.parts)))


def frame(svg, name, s, fill, stroke):
    """9 parti di un rettangolo con raggio s e bordo da 1px."""
    f, k = paint("fill", fill), paint("stroke", stroke)
    q = s - 0.5
    arc = 'fill="none" stroke-width="1" %s' % k
    svg.group(name + "-topleft", s, s,
              '<path d="M%g,%g L1,%g A%g,%g 0 0 1 %g,1 Z" %s/>' % (s, s, s, s - 1, s - 1, s, f)
              + '<path d="M0.5,%g A%g,%g 0 0 1 %g,0.5" %s/>' % (s, q, q, s, arc))
    svg.group(name + "-topright", s, s,
              '<path d="M0,%g L%g,%g A%g,%g 0 0 0 0,1 Z" %s/>' % (s, s - 1, s, s - 1, s - 1, f)
              + '<path d="M0,0.5 A%g,%g 0 0 1 %g,%g" %s/>' % (q, q, q, s, arc))
    svg.group(name + "-bottomleft", s, s,
              '<path d="M%g,0 L1,0 A%g,%g 0 0 0 %g,%g Z" %s/>' % (s, s - 1, s - 1, s, s - 1, f)
              + '<path d="M0.5,0 A%g,%g 0 0 0 %g,%g" %s/>' % (q, q, s, q, arc))
    svg.group(name + "-bottomright", s, s,
              '<path d="M0,0 L0,%g A%g,%g 0 0 0 %g,0 Z" %s/>' % (s - 1, s - 1, s - 1, s - 1, f)
              + '<path d="M0,%g A%g,%g 0 0 0 %g,0" %s/>' % (q, q, q, q, arc))
    svg.group(name + "-top", 1, s,
              '<rect x="0" y="1" width="1" height="%g" %s/><rect x="0" y="0" width="1" height="1" %s/>'
              % (s - 1, f, paint("fill", stroke)))
    svg.group(name + "-bottom", 1, s,
              '<rect x="0" y="0" width="1" height="%g" %s/><rect x="0" y="%g" width="1" height="1" %s/>'
              % (s - 1, f, s - 1, paint("fill", stroke)))
    svg.group(name + "-left", s, 1,
              '<rect x="1" y="0" width="%g" height="1" %s/><rect x="0" y="0" width="1" height="1" %s/>'
              % (s - 1, f, paint("fill", stroke)))
    svg.group(name + "-right", s, 1,
              '<rect x="0" y="0" width="%g" height="1" %s/><rect x="%g" y="0" width="1" height="1" %s/>'
              % (s - 1, f, s - 1, paint("fill", stroke)))


def interior(svg, name, fill):
    svg.group(name, 10, 10, '<rect x="0" y="0" width="10" height="10" %s/>' % paint("fill", fill))


def element(svg, name, radius, states, with_frame=True):
    """states: {stato: (riempimento, bordo)}; gli stati mancanti usano normal."""
    for state in STATES:
        fill, stroke = states.get(state, states["normal"])
        if with_frame:
            frame(svg, "%s-%s" % (name, state), radius, fill, stroke)
        interior(svg, "%s-%s" % (name, state), fill)


CLEAR = white(0)


def kvantum_svg():
    svg = Svg()
    # Pulsanti (.arc-btn-glass)
    element(svg, "button", 8, {
        "normal": (white(0.07), white(0.10)),
        "focused": (white(0.12), white(0.18)),
        "pressed": (white(0.05), white(0.10)),
        "toggled": (white(0.18), white(0.22)),
        "disabled": (white(0.03), white(0.05)),
    })
    # Pulsanti delle barre strumenti: piatti finché non ci passa il mouse
    element(svg, "tbutton", 8, {
        "normal": (CLEAR, CLEAR),
        "focused": (white(0.10), white(0.12)),
        "pressed": (white(0.06), white(0.10)),
        "toggled": (white(0.14), white(0.16)),
        "disabled": (CLEAR, CLEAR),
    })
    # Campi di testo (.arc-input)
    element(svg, "lineedit", 8, {
        "normal": (rgba((0, 0, 0), 0.22), white(0.10)),
        "focused": (rgba((0, 0, 0), 0.28), white(0.30)),
        "pressed": (rgba((0, 0, 0), 0.28), white(0.30)),
        "toggled": (rgba((0, 0, 0), 0.28), white(0.30)),
        "disabled": (rgba((0, 0, 0), 0.12), white(0.05)),
    })
    element(svg, "common", 8, {"normal": (CLEAR, white(0.10))})
    # Contenuto delle finestre di sistema: pannello incassato arrotondato
    # sopra il corpo di vetro (la barra laterale resta vetro)
    # Concentrico con la finestra: 28 (decorazione) - 8 di margine
    element(svg, "content", 20, {"normal": (rgba(CONTENT, 0.96), white(0.08))})
    element(svg, "menu", 12, {"normal": (rgba(MENU, 0.92), white(0.12))})
    element(svg, "tooltip", 8, {"normal": (rgba(TOOLTIP, 0.94), white(0.12))})
    for name in ("menuitem", "menubaritem"):
        element(svg, name, 6, {
            "normal": (CLEAR, CLEAR),
            "focused": (white(0.10), CLEAR),
            "pressed": (white(0.14), CLEAR),
            "toggled": (white(0.14), CLEAR),
            "disabled": (CLEAR, CLEAR),
        })
    # Righe di liste e alberi; toggled = selezione
    element(svg, "itemview", 6, {
        "normal": (CLEAR, CLEAR),
        "focused": (white(0.06), CLEAR),
        "pressed": (white(0.14), white(0.10)),
        "toggled": (white(0.14), white(0.10)),
        "disabled": (CLEAR, CLEAR),
    })
    element(svg, "tab", 8, {
        "normal": (CLEAR, CLEAR),
        "focused": (white(0.06), CLEAR),
        "pressed": (white(0.10), white(0.12)),
        "toggled": (white(0.12), white(0.14)),
        "disabled": (CLEAR, CLEAR),
    })
    element(svg, "tabframe", 10, {"normal": (white(0.03), white(0.08))})
    element(svg, "group", 12, {"normal": (white(0.03), white(0.08))})
    element(svg, "scrollbarslider", 4, {
        "normal": (white(0.25), CLEAR),
        "focused": (white(0.40), CLEAR),
        "pressed": (white(0.55), CLEAR),
        "toggled": (white(0.40), CLEAR),
        "disabled": (white(0.10), CLEAR),
    })
    # Cursori: traccia vetrosa, parte piena bianca (.arc-toggle)
    element(svg, "slider", 3, {
        "normal": (white(0.14), CLEAR),
        "toggled": (white(0.92), CLEAR),
        "disabled": (white(0.06), CLEAR),
    })
    element(svg, "progress", 4, {"normal": (white(0.10), CLEAR)})
    element(svg, "progress-pattern", 4, {"normal": (white(0.92), CLEAR)})
    interior(svg, "header-normal", white(0.04))
    interior(svg, "header-focused", white(0.08))
    interior(svg, "header-pressed", white(0.10))
    interior(svg, "header-toggled", white(0.06))
    interior(svg, "header-disabled", white(0.02))
    # Sfondo delle finestre (traslucido, KWin lo sfoca)
    # Corpo delle finestre: vetro chiaro di trasparenza, KWin lo sfoca
    interior(svg, "window-normal", rgba(WINDOW, 0.62))
    interior(svg, "window-normal-inactive", rgba(WINDOW, 0.75))

    # Maniglia dei cursori
    for state, color in (("normal", white(1)), ("focused", white(1)), ("pressed", rgba((232, 230, 238), 1)),
                         ("toggled", white(1)), ("disabled", white(0.4))):
        svg.group("slidercursor-" + state, 20, 20,
                  '<circle cx="10" cy="10" r="9" %s %s stroke-width="1"/>'
                  % (paint("fill", color), paint("stroke", rgba((0, 0, 0), 0.15))))

    # Caselle di controllo e pulsanti di opzione
    check = '<path d="M5 9.5 L8 12.5 L13.5 6" fill="none" stroke="#0f0d14" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
    dash = '<path d="M5.5 9 H12.5" fill="none" stroke="#0f0d14" stroke-width="2" stroke-linecap="round"/>'
    off = {"normal": (white(0.06), white(0.30)), "focused": (white(0.10), white(0.50)),
           "pressed": (white(0.14), white(0.50)), "toggled": (white(0.06), white(0.30)),
           "disabled": (white(0.02), white(0.12))}
    for state in STATES:
        fill, stroke = off[state]
        on = white(0.4) if state == "disabled" else white(1)
        rect = '<rect x="0.5" y="0.5" width="17" height="17" rx="5" %s %s stroke-width="1"/>'
        svg.group("checkbox-" + state, 18, 18, rect % (paint("fill", fill), paint("stroke", stroke)))
        svg.group("checkbox-checked-" + state, 18, 18, rect % (paint("fill", on), paint("stroke", on)) + check)
        svg.group("checkbox-tristate-" + state, 18, 18, rect % (paint("fill", on), paint("stroke", on)) + dash)
        circle = '<circle cx="9" cy="9" r="8.5" %s %s stroke-width="1"/>'
        svg.group("radio-" + state, 18, 18, circle % (paint("fill", fill), paint("stroke", stroke)))
        svg.group("radio-checked-" + state, 18, 18,
                  circle % (paint("fill", on), paint("stroke", on)) + '<circle cx="9" cy="9" r="3.5" fill="#0f0d14"/>')

    # Frecce (chevron)
    chevrons = {"down": "M4 6 L8 10 L12 6", "up": "M4 10 L8 6 L12 10",
                "left": "M10 4 L6 8 L10 12", "right": "M6 4 L10 8 L6 12"}
    alphas = {"normal": 0.80, "focused": 1.0, "pressed": 1.0, "toggled": 1.0, "disabled": 0.30}
    for direction, d in chevrons.items():
        for state in STATES:
            svg.group("arrow-%s-%s" % (direction, state), 16, 16,
                      '<path d="%s" fill="none" %s stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>'
                      % (d, paint("stroke", white(alphas[state]))))
    return svg.render()


def section(name, **keys):
    lines = ["[%s]" % name] + ["%s=%s" % (k.replace("__", "."), v) for k, v in keys.items()]
    return "\n".join(lines)


def framed(element_name, size, interior_name=None, **extra):
    keys = dict(frame="true", frame__element=element_name, frame__top=size, frame__bottom=size,
                frame__left=size, frame__right=size, interior="true",
                interior__element=interior_name or element_name)
    keys.update(extra)
    return keys


TEXT_COLORS = dict(text__normal__color=TEXT, text__focus__color="#ffffff", text__press__color="#ffffff",
                   text__toggle__color="#ffffff", text__shadow="0")
OFF = dict(frame="false", interior="false")


def kvantum_config():
    general = section(
        "%General",
        author="ArcBase", comment="arc UI — vetro scuro (generato da arc-ui/theme/generate.py)",
        x11drag="menubar_and_primary_toolbar", alt_mnemonic="true", left_tabs="true",
        attach_active_tab="false", group_toolbar_buttons="false", spread_progressbar="true",
        composite="true", translucent_windows="true", blurring="true", popup_blurring="true",
        reduce_window_opacity="0", reduce_menu_opacity="0", menu_shadow_depth="0",
        tooltip_shadow_depth="0", shadowless_popup="true", respect_DE="true",
        scroll_width="8", scroll_min_extent="48", scrollbar_in_view="true",
        transient_scrollbar="true", transient_groove="true", slider_width="6",
        slider_handle_width="20", slider_handle_length="20", check_size="18",
        progressbar_thickness="8", textless_progressbar="false", splitter_width="6",
        layout_spacing="6", layout_margin="9", small_icon_size="16", large_icon_size="32",
        button_icon_size="16", toolbar_icon_size="22", toolbutton_style="0",
        combo_as_lineedit="true", combo_menu="true", hide_combo_checkboxes="true",
        combo_focus_rect="false", animate_states="true", menubar_mouse_tracking="true",
        fill_rubberband="false", tree_branch_line="false", submenu_overlap="0",
        dialog_button_layout="0", contrast="1.00", intensity="1.00", saturation="1.00",
        opaque="kaffeine,kmplayer,subtitlecomposer,kdenlive,vlc,avidemux,avidemux2_qt4,"
               "avidemux3_qt4,avidemux3_qt5,kamoso,QtCreator,VirtualBox,VirtualBoxVM,trojita,"
               "dragon,digikam,lyx,obs",
    )
    colors = section(
        "GeneralColors",
        window__color="#16131d", base__color="#25222c", alt__base__color="#2a2632",
        button__color="#2a2534", light__color="#3a3446", mid__light__color="#302b3b",
        dark__color="#0d0b12", mid__color="#1f1b28", highlight__color="#4a4458",
        inactive__highlight__color="#3a3546", text__color=TEXT, window__text__color=TEXT,
        button__text__color=TEXT, disabled__text__color=DISABLED, tooltip__text__color=TEXT,
        highlight__text__color="#ffffff", link__color="#c4b5fd", link__visited__color="#ddd6fe",
        progress__indicator__text__color="#0f0d14",
    )
    hacks = section(
        "Hacks",
        transparent_dolphin_view="false", blur_konsole="true", transparent_ktitle_label="true",
        transparent_menutitle="true", respect_darkness="true", blur_translucent="true",
        no_selection_tint="true", normal_default_pushbutton="true", single_top_toolbar="true",
        transparent_arrow_button="true", disabled_icon_opacity="70", kinetic_scrolling="false",
    )
    sections = [
        general, colors, hacks,
        section("PanelButtonCommand", **framed("button", 8), indicator__element="arrow", indicator__size="12",
                text__margin__left="8", text__margin__right="8", text__margin__top="2",
                text__margin__bottom="2", text__iconspacing="6", **TEXT_COLORS),
        section("PanelButtonTool", inherits="PanelButtonCommand"),
        section("ToolbarButton", **framed("tbutton", 8), indicator__element="arrow", indicator__size="12",
                text__margin__left="4", text__margin__right="4", **TEXT_COLORS),
        section("DropDownButton", inherits="PanelButtonCommand"),
        section("ComboBox", inherits="PanelButtonCommand"),
        section("LineEdit", **framed("lineedit", 8), text__margin__left="6", text__margin__right="6",
                **TEXT_COLORS),
        section("IndicatorSpinBox", inherits="PanelButtonCommand", frame="false", interior="false"),
        section("CheckBox", **OFF, indicator__element="checkbox", indicator__size="18", **TEXT_COLORS),
        section("RadioButton", **OFF, indicator__element="radio", indicator__size="18", **TEXT_COLORS),
        section("GenericFrame", frame="true", frame__element="content", frame__top="8", frame__bottom="8",
                frame__left="8", frame__right="8", interior="true", interior__element="content"),
        section("Focus", frame="false"),
        section("Menu", **framed("menu", 12), **TEXT_COLORS),
        section("MenuItem", **framed("menuitem", 6), indicator__element="arrow", indicator__size="12",
                text__margin__left="6", text__margin__right="6", text__margin__top="4",
                text__margin__bottom="4", **TEXT_COLORS),
        section("MenuBar", **OFF),
        section("MenuBarItem", **framed("menubaritem", 6), text__margin__left="6", text__margin__right="6",
                **TEXT_COLORS),
        section("ToolTip", **framed("tooltip", 8), text__margin__left="4", text__margin__right="4",
                **TEXT_COLORS),
        section("ItemView", **framed("itemview", 6), text__margin__left="4", text__margin__right="4",
                **TEXT_COLORS),
        section("Tab", **framed("tab", 8), text__margin__left="10", text__margin__right="10",
                text__margin__top="4", text__margin__bottom="4", **TEXT_COLORS),
        section("TabFrame", **framed("tabframe", 10)),
        section("TabBarFrame", **OFF),
        section("GroupBox", **framed("group", 12), **TEXT_COLORS),
        section("HeaderSection", frame="false", interior="true", interior__element="header", **TEXT_COLORS),
        section("Scrollbar", **OFF, indicator__element="arrow", indicator__size="10"),
        section("ScrollbarSlider", **framed("scrollbarslider", 4)),
        section("ScrollbarGroove", **OFF),
        section("Slider", **framed("slider", 3)),
        section("SliderCursor", frame="false", interior="true", interior__element="slidercursor"),
        section("Progressbar", **framed("progress", 4), **TEXT_COLORS),
        section("ProgressbarContents", **framed("progress-pattern", 4)),
        section("Window", frame="false", interior="true", interior__element="window"),
        section("Toolbar", **OFF),
        section("StatusBar", **OFF),
        section("TitleBar", **OFF),
        section("Dock", **OFF),
        section("DockTitle", **OFF, **TEXT_COLORS),
        section("Splitter", **OFF),
    ]
    return ("# arc UI — generato da arc-ui/theme/generate.py, non modificare a mano\n"
            + "\n\n".join(sections) + "\n")


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="cartella di destinazione (es. /usr/share)")
    out = parser.parse_args().out

    kv = os.path.join(out, "Kvantum", "ArcGlass")
    write(os.path.join(kv, "ArcGlass.svg"), kvantum_svg())
    write(os.path.join(kv, "ArcGlass.kvconfig"), kvantum_config())



if __name__ == "__main__":
    main()
