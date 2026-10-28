package services

import win "core:sys/windows"
import "../core"
import "../platform"

// Icons are cached by executable name because every row (a process or an
// application group) is keyed by that name. The list is rebuilt on every
// process refresh, so name is the stable identity across enumerations.
MAX_ICON_CACHE :: 512
EXE_PATH_CHARS :: 1024

Icon_State :: enum {
	unknown,
	loaded,
	failed,
}

Icon_Cache_Entry :: struct {
	name:  [core.MAX_NAME_U16]u16,
	icon:  win.HICON,
	pid:   u32,
	state: Icon_State,
}

icon_cache: [MAX_ICON_CACHE]Icon_Cache_Entry
icon_cache_count: int

find_icon_entry :: proc(name: [core.MAX_NAME_U16]u16) -> (entry: ^Icon_Cache_Entry, found: bool) {
	for i in 0..<icon_cache_count {
		if same_task_name(icon_cache[i].name, name) {
			return &icon_cache[i], true
		}
	}
	return nil, false
}

pid_for_task_name :: proc(name: [core.MAX_NAME_U16]u16) -> (pid: u32, found: bool) {
	for i in 0..<core.app.process_count {
		if same_task_name(core.app.processes[i].name, name) {
			return core.app.processes[i].pid, true
		}
	}
	return 0, false
}

// Resolve the executable behind a pid and ask the shell for the same icon
// Explorer would show for it.
load_process_icon :: proc(pid: u32) -> win.HICON {
	handle := win.OpenProcess(win.PROCESS_QUERY_LIMITED_INFORMATION, win.FALSE, pid)
	if handle == nil {
		return nil
	}
	defer _ = win.CloseHandle(handle)

	path: [EXE_PATH_CHARS]u16
	size := u32(len(path))
	if platform.QueryFullProcessImageNameW(handle, 0, raw_data(path[:]), &size) == win.FALSE {
		return nil
	}
	if size >= u32(len(path)) {
		size = u32(len(path)) - 1
	}
	path[size] = 0

	info: platform.SHFILEINFOW
	result := platform.SHGetFileInfoW(
		win.wstring(raw_data(path[:])),
		0,
		&info,
		u32(size_of(platform.SHFILEINFOW)),
		platform.SHGFI_ICON | platform.SHGFI_LARGEICON,
	)
	if result == 0 || info.hIcon == nil {
		return nil
	}
	return info.hIcon
}

// Lazily fetch and cache the icon for a task name. Callers fall back to the
// letter badge when this returns nil (protected processes, missing icons).
icon_for_task_name :: proc(name: [core.MAX_NAME_U16]u16) -> win.HICON {
	pid, has_pid := pid_for_task_name(name)

	entry: ^Icon_Cache_Entry
	if cached, found := find_icon_entry(name); found {
		switch cached.state {
		case .loaded:
			return cached.icon
		case .failed:
			// A process with the same executable name may have restarted since
			// the failed lookup; only retry when the owning pid changed.
			if !has_pid || pid == cached.pid {
				return nil
			}
		case .unknown:
		}
		entry = cached
	} else {
		if icon_cache_count >= len(icon_cache) {
			return nil
		}
		entry = &icon_cache[icon_cache_count]
		entry.name = name
		icon_cache_count += 1
	}

	if !has_pid {
		return nil
	}

	icon := load_process_icon(pid)
	entry.icon = icon
	entry.pid = pid
	entry.state = icon != nil ? .loaded : .failed
	return icon
}

destroy_icon_cache :: proc() {
	for i in 0..<icon_cache_count {
		if icon_cache[i].icon != nil {
			_ = win.DestroyIcon(icon_cache[i].icon)
			icon_cache[i].icon = nil
		}
	}
	icon_cache_count = 0
}
