package main

import "core:fmt"
import win "core:sys/windows"

// 设置页：模块、颜色、刷新、停靠。

draw_settings_view :: proc(dc: win.HDC) {
	layout := settings_layout()
	draw_card(dc, layout.outer)

	draw_text(dc, "Settings", layout.outer.left + dip(24), layout.outer.top + dip(16),
		dip(240), dip(30), app.fonts.title, COL_TEXT, DT_LEFT | DT_VCENTER | DT_SINGLELINE)
	draw_text(dc, "Modules, colors, refresh and theme", layout.outer.left + dip(24), layout.outer.top + dip(44),
		dip(420), dip(16), app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	fill_round(dc, layout.reset, app.brushes.badge, app.pens.border, dip(8))
	draw_text(dc, "Reset defaults", layout.reset.left, layout.reset.top,
		layout.reset.right - layout.reset.left, layout.reset.bottom - layout.reset.top,
		app.fonts.small, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)

	divider := win.RECT{layout.outer.left + dip(24), layout.outer.top + dip(70),
		layout.outer.right - dip(24), layout.outer.top + dip(71)}
	_ = win.FillRect(dc, &divider, app.brushes.line)

	draw_text(dc, "MODULES", layout.modules.left, layout.modules.top, layout.modules.right - layout.modules.left, dip(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	draw_text(dc, "COLORS", layout.colors.left, layout.colors.top, layout.colors.right - layout.colors.left, dip(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)
	draw_text(dc, "APPEARANCE", layout.appearance.left, layout.appearance.top, layout.appearance.right - layout.appearance.left, dip(16),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	sep1 := win.RECT{layout.modules.right + dip(12), layout.body_top, layout.modules.right + dip(13), layout.body_bottom}
	sep2 := win.RECT{layout.colors.right + dip(12), layout.body_top, layout.colors.right + dip(13), layout.body_bottom}
	_ = win.FillRect(dc, &sep1, app.brushes.line)
	_ = win.FillRect(dc, &sep2, app.brushes.line)

	for i in 0..<7 {
		id := Module_Id(i)
		row := settings_module_row(layout, i)
		disabled := id == .cores && !settings.modules.cpu
		label_color := COL_TEXT
		if disabled {
			label_color = COL_MUTED
		}
		draw_text(dc, module_label(id), row.left, row.top, row.right - row.left - dip(70), row.bottom - row.top,
			app.fonts.small, label_color, DT_LEFT | DT_VCENTER | DT_SINGLELINE)

		switch_rect := win.RECT{row.right - dip(56), row.top + (row.bottom - row.top - dip(20))/2,
			row.right - dip(16), row.top + (row.bottom - row.top - dip(20))/2 + dip(20)}
		draw_switch(dc, switch_rect, module_enabled(id) && !disabled, !disabled)
	}

	cores_label_y := settings_cores_label_y(layout)
	draw_text(dc, "CORES PER PAGE", layout.modules.left, cores_label_y,
		layout.modules.right - layout.modules.left, dip(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	options := CORE_PAGE_OPTIONS
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
			selected = settings.cores_per_page == option && !settings.cores_custom_mode
			label = fmt.bprintf(label_buf[:], "%d", option)
		}

		brush := app.brushes.badge
		text_color := COL_TEXT
		if selected {
			brush = app.brushes.accent
			text_color = COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, app.pens.border, dip(7))

		draw_text(dc, label, chip.left, chip.top,
			chip.right - chip.left, chip.bottom - chip.top, app.fonts.tiny, text_color,
			DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS)
	}

	if is_core_page_custom() {
		row_y := settings_custom_row_y(layout)
		draw_text(dc, "CUSTOM", layout.modules.left, row_y + dip(5), dip(76), dip(14),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

		current := core_page_per_core()
		minus := settings_custom_minus_rect(layout)
		plus := settings_custom_plus_rect(layout)
		draw_page_button(dc, minus, "-", current > 1)
		draw_page_button(dc, plus, "+", current < max(app.cores, 1))

		value_buf: [16]u8
		draw_text(dc, fmt.bprintf(value_buf[:], "%d", current),
			minus.right, minus.top, plus.left - minus.right, plus.bottom - minus.top,
			app.fonts.small, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	}

	roles := [3]string{"ACCENT", "MEMORY", "GPU"}
	for role in 0..<3 {
		label_y := settings_color_label_y(layout, role)
		draw_text(dc, roles[role], layout.colors.left, label_y - dip(17),
			layout.colors.right - layout.colors.left, dip(14),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

		current := color_for_role(role)

		chip := win.RECT{layout.colors.left + dip(72), label_y - dip(18),
			layout.colors.left + dip(88), label_y - dip(2)}
		fill_color_rect(dc, chip, current, dip(3))

		palette := palette_for_role(role)
		for i in 0..<len(palette) {
			swatch := settings_swatch_rect(layout, role, i)
			fill_color_rect(dc, swatch, palette[i], dip(6))
			if palette[i] == current {
				draw_text(dc, "✓", swatch.left, swatch.top, swatch.right - swatch.left, swatch.bottom - swatch.top,
					app.fonts.badge, COL_BADGE_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
			}
		}

		custom := settings_custom_rect(layout, role)
		fill_round(dc, custom, app.brushes.badge, app.pens.border, dip(8))
		draw_text(dc, "Custom…", custom.left, custom.top, custom.right - custom.left, custom.bottom - custom.top,
			app.fonts.tiny, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	}

	dock_label_y := settings_dock_label_y(layout)
	draw_text(dc, "POSITION", layout.colors.left, dock_label_y,
		layout.colors.right - layout.colors.left, dip(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	dock_modes := [2]Dock_Mode{.top, .bottom}
	dock_labels := DOCK_LABELS
	for i in 0..<len(dock_modes) {
		chip := settings_dock_chip_rect(layout, i)
		selected := settings.dock == dock_modes[i]

		brush := app.brushes.badge
		text_color := COL_TEXT
		if selected {
			brush = app.brushes.accent
			text_color = COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, app.pens.border, dip(7))

		draw_text(dc, dock_labels[i], chip.left, chip.top,
			chip.right - chip.left, chip.bottom - chip.top, app.fonts.tiny, text_color,
			DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS)
	}

	dock_hints := DOCK_HINTS
	first_chip := settings_dock_chip_rect(layout, 0)
	draw_text(dc, dock_hints[int(settings.dock)], layout.colors.left, first_chip.bottom + dip(10),
		layout.colors.right - layout.colors.left, dip(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS)

	for i in 0..<len(THEMES) {
		preview := settings_theme_rect(layout, i)
		theme := THEMES[i]

		fill_color_rect(dc, preview, theme.bg, dip(8))
		top_strip := win.RECT{preview.left + dip(2), preview.top + dip(2), preview.right - dip(2), preview.top + dip(26)}
		fill_color_rect(dc, top_strip, theme.sidebar, dip(6))

		card_rect := win.RECT{preview.left + dip(16), preview.top + dip(38), preview.right - dip(16), preview.bottom - dip(16)}
		fill_color_rect(dc, card_rect, theme.card, dip(5))

		dot := win.RECT{preview.left + dip(14), preview.top + dip(10), preview.left + dip(22), preview.top + dip(18)}
		fill_color_rect(dc, dot, settings.accent, dip(4))

		draw_text(dc, theme.name, preview.left + dip(28), preview.bottom - dip(40),
			preview.right - preview.left - dip(80), dip(20),
			app.fonts.small, COL_TEXT, DT_LEFT | DT_VCENTER | DT_SINGLELINE)

		if settings.theme == i {
			stripe := win.RECT{preview.left, preview.top + dip(10), preview.left + dip(3), preview.bottom - dip(10)}
			_ = win.FillRect(dc, &stripe, app.brushes.accent)
			draw_text(dc, "✓", preview.right - dip(40), preview.bottom - dip(40), dip(20), dip(20),
				app.fonts.small, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
		}
	}

	refresh_y := settings_refresh_label_y(layout)
	draw_text(dc, "REFRESH", layout.appearance.left, refresh_y,
		layout.appearance.right - layout.appearance.left, dip(14),
		app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

	history_buf: [32]u8
	draw_text(dc, refresh_history_label(history_buf[:], settings.refresh_ms),
		layout.appearance.left, refresh_y, layout.appearance.right - layout.appearance.left, dip(14),
		app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)

	refresh_options := REFRESH_OPTIONS
	for i in 0..<len(refresh_options) {
		option := refresh_options[i]
		chip := settings_refresh_chip_rect(layout, i)
		selected := false
		label := ""
		label_buf: [16]u8
		if option < 0 {
			selected = is_refresh_custom()
			label = "CUSTOM"
		} else {
			selected = settings.refresh_ms == option && !is_refresh_custom()
			label = refresh_label(label_buf[:], option)
		}

		brush := app.brushes.badge
		text_color := COL_TEXT
		if selected {
			brush = app.brushes.accent
			text_color = COL_BADGE_TEXT
		}
		fill_round(dc, chip, brush, app.pens.border, dip(7))

		draw_text(dc, label, chip.left, chip.top,
			chip.right - chip.left, chip.bottom - chip.top, app.fonts.tiny, text_color,
			DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS)
	}

	if is_refresh_custom() {
		row_y := settings_refresh_row_y(layout)
		draw_text(dc, "CUSTOM", layout.appearance.left, row_y + dip(5), dip(66), dip(14),
			app.fonts.tiny, COL_MUTED, DT_LEFT | DT_SINGLELINE)

		minus := settings_refresh_minus_rect(layout)
		plus := settings_refresh_plus_rect(layout)
		value_rect := settings_refresh_value_rect(layout)
		draw_page_button(dc, minus, "-", settings.refresh_ms > REFRESH_MIN_MS)
		draw_page_button(dc, plus, "+", settings.refresh_ms < REFRESH_MAX_MS)

		fill_round(dc, value_rect, app.brushes.badge, app.pens.border, dip(7))

		text_buf: [16]u8
		text := ""
		if app.refresh_edit {
			text = fmt.bprintf(text_buf[:], "%s|", string(app.refresh_edit_buf[:app.refresh_edit_len]))
			underline := win.RECT{value_rect.left + dip(6), value_rect.bottom - dip(3),
				value_rect.right - dip(6), value_rect.bottom - dip(1)}
			_ = win.FillRect(dc, &underline, app.brushes.accent)
		} else {
			text = fmt.bprintf(text_buf[:], "%d ms", settings.refresh_ms)
		}

		draw_text(dc, text, value_rect.left, value_rect.top,
			value_rect.right - value_rect.left, value_rect.bottom - value_rect.top,
			app.fonts.small, COL_TEXT, DT_CENTER | DT_VCENTER | DT_SINGLELINE)
	}

	draw_text(dc, "Changes are saved automatically", layout.outer.right - dip(244), layout.outer.bottom - dip(30),
		dip(220), dip(14), app.fonts.tiny, COL_MUTED, DT_RIGHT | DT_SINGLELINE)
}

draw_switch :: proc(dc: win.HDC, rect: win.RECT, on: bool, enabled: bool) {
	track := app.brushes.track
	if on && enabled {
		track = app.brushes.accent
	}
	fill_round(dc, rect, track, app.pens.null, (rect.bottom - rect.top)/2)

	knob_size := dip(14)
	knob_y := rect.top + (rect.bottom - rect.top - knob_size)/2
	knob_x := rect.left + dip(3)
	if on {
		knob_x = rect.right - knob_size - dip(3)
	}
	knob_color := app.brushes.muted
	if on && enabled {
		knob_color = app.brushes.light
	}
	knob := win.RECT{knob_x, knob_y, knob_x + knob_size, knob_y + knob_size}
	fill_round(dc, knob, knob_color, app.pens.null, knob_size/2)
}
