package ui

import "core:fmt"
import win "core:sys/windows"
import "../core"
import "../platform"

// 设置页：模块、颜色、刷新、停靠。

draw_settings_view :: proc(dc: win.HDC) {
	layout := settings_layout()
	draw_card(dc, layout.outer)

	draw_text(dc, "core.Settings", layout.outer.left + core.dip(24), layout.outer.top + core.dip(16),
		core.dip(240), core.dip(30), core.app.fonts.title, core.COL_TEXT, platform.DT_LEFT | platform.DT_VCENTER | platform.DT_SINGLELINE)
	draw_text(dc, "Modules, colors, refresh and theme", layout.outer.left + core.dip(24), layout.outer.top + core.dip(44),
		core.dip(420), core.dip(16), core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

	fill_round(dc, layout.reset, core.app.brushes.badge, core.app.pens.border, core.dip(8))
	draw_text(dc, "Reset defaults", layout.reset.left, layout.reset.top,
		layout.reset.right - layout.reset.left, layout.reset.bottom - layout.reset.top,
		core.app.fonts.small, core.COL_TEXT, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)

	divider := win.RECT{layout.outer.left + core.dip(24), layout.outer.top + core.dip(70),
		layout.outer.right - core.dip(24), layout.outer.top + core.dip(71)}
	_ = win.FillRect(dc, &divider, core.app.brushes.line)

	draw_text(dc, "MODULES", layout.modules.left, layout.modules.top, layout.modules.right - layout.modules.left, core.dip(16),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)
	draw_text(dc, "COLORS", layout.colors.left, layout.colors.top, layout.colors.right - layout.colors.left, core.dip(16),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)
	draw_text(dc, "APPEARANCE", layout.appearance.left, layout.appearance.top, layout.appearance.right - layout.appearance.left, core.dip(16),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

	sep1 := win.RECT{layout.modules.right + core.dip(12), layout.body_top, layout.modules.right + core.dip(13), layout.body_bottom}
	sep2 := win.RECT{layout.colors.right + core.dip(12), layout.body_top, layout.colors.right + core.dip(13), layout.body_bottom}
	_ = win.FillRect(dc, &sep1, core.app.brushes.line)
	_ = win.FillRect(dc, &sep2, core.app.brushes.line)

	for i in 0..<7 {
		id := core.Module_Id(i)
		row := settings_module_row(layout, i)
		disabled := id == .cores && !core.settings.modules.cpu
		label_color := core.COL_TEXT
		if disabled {
			label_color = core.COL_MUTED
		}
		draw_text(dc, core.module_label(id), row.left, row.top, row.right - row.left - core.dip(70), row.bottom - row.top,
			core.app.fonts.small, label_color, platform.DT_LEFT | platform.DT_VCENTER | platform.DT_SINGLELINE)

		switch_rect := win.RECT{row.right - core.dip(56), row.top + (row.bottom - row.top - core.dip(20))/2,
			row.right - core.dip(16), row.top + (row.bottom - row.top - core.dip(20))/2 + core.dip(20)}
		draw_switch(dc, switch_rect, core.module_enabled(id) && !disabled, !disabled)
	}

	cores_label_y := settings_cores_label_y(layout)
	draw_text(dc, "CORES PER PAGE", layout.modules.left, cores_label_y,
		layout.modules.right - layout.modules.left, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

	options := core.CORE_PAGE_OPTIONS
	for i in 0..<len(options) {
		chip := settings_cores_page_rect(layout, i)
		option := options[i]
		selected := false
		label := ""
		label_buf: [16]u8
		if option < 0 {
			selected = is_core_page_custom()
			label = "CUSTOM"
		} else if option == 0 {
			selected = is_core_page_max()
			label = "MAX"
		} else {
			selected = core.settings.cores_per_page == option && !core.settings.cores_custom_mode
			label = fmt.bprintf(label_buf[:], "%d", option)
		}

		brush := core.app.brushes.badge
		text_color := core.COL_TEXT
		if selected {
			brush = core.app.brushes.accent
			text_color = core.COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, core.app.pens.border, core.dip(7))

		draw_text(dc, label, chip.left, chip.top,
			chip.right - chip.left, chip.bottom - chip.top, core.app.fonts.tiny, text_color,
			platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)
	}

	if is_core_page_custom() {
		row_y := settings_custom_row_y(layout)
		draw_text(dc, "CUSTOM", layout.modules.left, row_y + core.dip(5), core.dip(76), core.dip(14),
			core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

		current := core_page_per_core()
		minus := settings_custom_minus_rect(layout)
		plus := settings_custom_plus_rect(layout)
		draw_page_button(dc, minus, "-", current > 1)
		draw_page_button(dc, plus, "+", current < max(core.app.cores, 1))

		value_buf: [16]u8
		draw_text(dc, fmt.bprintf(value_buf[:], "%d", current),
			minus.right, minus.top, plus.left - minus.right, plus.bottom - minus.top,
			core.app.fonts.small, core.COL_TEXT, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
	}

	roles := [3]string{"ACCENT", "MEMORY", "GPU"}
	for role in 0..<3 {
		label_y := settings_color_label_y(layout, role)
		draw_text(dc, roles[role], layout.colors.left, label_y - core.dip(17),
			layout.colors.right - layout.colors.left, core.dip(14),
			core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

		current := core.color_for_role(role)

		chip := win.RECT{layout.colors.left + core.dip(72), label_y - core.dip(18),
			layout.colors.left + core.dip(88), label_y - core.dip(2)}
		fill_color_rect(dc, chip, current, core.dip(3))

		palette := core.palette_for_role(role)
		for i in 0..<len(palette) {
			swatch := settings_swatch_rect(layout, role, i)
			fill_color_rect(dc, swatch, palette[i], core.dip(6))
			if palette[i] == current {
				draw_text(dc, "✓", swatch.left, swatch.top, swatch.right - swatch.left, swatch.bottom - swatch.top,
					core.app.fonts.badge, core.COL_BADGE_TEXT, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
			}
		}

		custom := settings_custom_rect(layout, role)
		fill_round(dc, custom, core.app.brushes.badge, core.app.pens.border, core.dip(8))
		draw_text(dc, "Custom…", custom.left, custom.top, custom.right - custom.left, custom.bottom - custom.top,
			core.app.fonts.tiny, core.COL_TEXT, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
	}

	dock_label_y := settings_dock_label_y(layout)
	draw_text(dc, "POSITION", layout.colors.left, dock_label_y,
		layout.colors.right - layout.colors.left, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

	dock_modes := [2]core.Dock_Mode{.top, .bottom}
	dock_labels := core.DOCK_LABELS
	for i in 0..<len(dock_modes) {
		chip := settings_dock_chip_rect(layout, i)
		selected := core.settings.dock == dock_modes[i]

		brush := core.app.brushes.badge
		text_color := core.COL_TEXT
		if selected {
			brush = core.app.brushes.accent
			text_color = core.COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, core.app.pens.border, core.dip(7))

		draw_text(dc, dock_labels[i], chip.left, chip.top,
			chip.right - chip.left, chip.bottom - chip.top, core.app.fonts.tiny, text_color,
			platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)
	}

	dock_hints := core.DOCK_HINTS
	first_chip := settings_dock_chip_rect(layout, 0)
	draw_text(dc, dock_hints[int(core.settings.dock)], layout.colors.left, first_chip.bottom + core.dip(10),
		layout.colors.right - layout.colors.left, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)

	for i in 0..<len(core.THEMES) {
		preview := settings_theme_rect(layout, i)
		theme := core.THEMES[i]

		fill_color_rect(dc, preview, theme.bg, core.dip(8))
		top_strip := win.RECT{preview.left + core.dip(2), preview.top + core.dip(2), preview.right - core.dip(2), preview.top + core.dip(26)}
		fill_color_rect(dc, top_strip, theme.sidebar, core.dip(6))

		card_rect := win.RECT{preview.left + core.dip(16), preview.top + core.dip(38), preview.right - core.dip(16), preview.bottom - core.dip(16)}
		fill_color_rect(dc, card_rect, theme.card, core.dip(5))

		dot := win.RECT{preview.left + core.dip(14), preview.top + core.dip(10), preview.left + core.dip(22), preview.top + core.dip(18)}
		fill_color_rect(dc, dot, core.settings.accent, core.dip(4))

		draw_text(dc, theme.name, preview.left + core.dip(28), preview.bottom - core.dip(40),
			preview.right - preview.left - core.dip(80), core.dip(20),
			core.app.fonts.small, core.COL_TEXT, platform.DT_LEFT | platform.DT_VCENTER | platform.DT_SINGLELINE)

		if core.settings.theme == i {
			stripe := win.RECT{preview.left, preview.top + core.dip(10), preview.left + core.dip(3), preview.bottom - core.dip(10)}
			_ = win.FillRect(dc, &stripe, core.app.brushes.accent)
			draw_text(dc, "✓", preview.right - core.dip(40), preview.bottom - core.dip(40), core.dip(20), core.dip(20),
				core.app.fonts.small, core.COL_TEXT, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
		}
	}

	refresh_y := settings_refresh_label_y(layout)
	draw_text(dc, "REFRESH", layout.appearance.left, refresh_y,
		layout.appearance.right - layout.appearance.left, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

	history_buf: [32]u8
	draw_text(dc, core.refresh_history_label(history_buf[:], core.settings.refresh_ms),
		layout.appearance.left, refresh_y, layout.appearance.right - layout.appearance.left, core.dip(14),
		core.app.fonts.tiny, core.COL_MUTED, platform.DT_RIGHT | platform.DT_SINGLELINE)

	refresh_options := core.REFRESH_OPTIONS
	for i in 0..<len(refresh_options) {
		option := refresh_options[i]
		chip := settings_refresh_chip_rect(layout, i)
		selected := false
		label := ""
		label_buf: [16]u8
		if option < 0 {
			selected = core.is_refresh_custom()
			label = "CUSTOM"
		} else {
			selected = core.settings.refresh_ms == option && !core.is_refresh_custom()
			label = core.refresh_label(label_buf[:], option)
		}

		brush := core.app.brushes.badge
		text_color := core.COL_TEXT
		if selected {
			brush = core.app.brushes.accent
			text_color = core.COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, core.app.pens.border, core.dip(7))

		draw_text(dc, label, chip.left, chip.top,
			chip.right - chip.left, chip.bottom - chip.top, core.app.fonts.tiny, text_color,
			platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE | platform.DT_END_ELLIPSIS)
	}

	if core.is_refresh_custom() {
		row_y := settings_refresh_row_y(layout)
		draw_text(dc, "CUSTOM", layout.appearance.left, row_y + core.dip(5), core.dip(66), core.dip(14),
			core.app.fonts.tiny, core.COL_MUTED, platform.DT_LEFT | platform.DT_SINGLELINE)

		minus := settings_refresh_minus_rect(layout)
		plus := settings_refresh_plus_rect(layout)
		value_rect := settings_refresh_value_rect(layout)
		draw_page_button(dc, minus, "-", core.settings.refresh_ms > core.REFRESH_MIN_MS)
		draw_page_button(dc, plus, "+", core.settings.refresh_ms < core.REFRESH_MAX_MS)

		fill_round(dc, value_rect, core.app.brushes.badge, core.app.pens.border, core.dip(7))

		text_buf: [16]u8
		text := ""
		if core.app.refresh_edit {
			text = fmt.bprintf(text_buf[:], "%s|", string(core.app.refresh_edit_buf[:core.app.refresh_edit_len]))
			underline := win.RECT{value_rect.left + core.dip(6), value_rect.bottom - core.dip(3),
				value_rect.right - core.dip(6), value_rect.bottom - core.dip(1)}
			_ = win.FillRect(dc, &underline, core.app.brushes.accent)
		} else {
			text = fmt.bprintf(text_buf[:], "%d ms", core.settings.refresh_ms)
		}

		draw_text(dc, text, value_rect.left, value_rect.top,
			value_rect.right - value_rect.left, value_rect.bottom - value_rect.top,
			core.app.fonts.small, core.COL_TEXT, platform.DT_CENTER | platform.DT_VCENTER | platform.DT_SINGLELINE)
	}

	draw_text(dc, "Changes are saved automatically", layout.outer.right - core.dip(244), layout.outer.bottom - core.dip(30),
		core.dip(220), core.dip(14), core.app.fonts.tiny, core.COL_MUTED, platform.DT_RIGHT | platform.DT_SINGLELINE)
}

draw_switch :: proc(dc: win.HDC, rect: win.RECT, on: bool, enabled: bool) {
	track := core.app.brushes.track
	if on && enabled {
		track = core.app.brushes.accent
	}
	fill_round(dc, rect, track, core.app.pens.null, (rect.bottom - rect.top)/2)

	knob_size := core.dip(14)
	knob_y := rect.top + (rect.bottom - rect.top - knob_size)/2
	knob_x := rect.left + core.dip(3)
	if on {
		knob_x = rect.right - knob_size - core.dip(3)
	}
	knob_color := core.app.brushes.muted
	if on && enabled {
		knob_color = core.app.brushes.light
	}
	knob := win.RECT{knob_x, knob_y, knob_x + knob_size, knob_y + knob_size}
	fill_round(dc, knob, knob_color, core.app.pens.null, knob_size/2)
}
