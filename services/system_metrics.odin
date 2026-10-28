package services

import "core:fmt"
import win "core:sys/windows"
import "../core"
import "../platform"

// 系统级指标采集：CPU、每核、内存、GPU、磁盘、网络。

get_core_count :: proc() {
	info: win.SYSTEM_INFO
	win.GetSystemInfo(&info)
	core.app.cores = min(int(info.dwNumberOfProcessors), core.MAX_CORES)
	if core.app.cores < 1 {
		core.app.cores = 1
	}
}

push_cpu_sample :: proc(v: f32) {
	for i in 1..<core.SAMPLE_COUNT {
		core.app.cpu_samples[i-1] = core.app.cpu_samples[i]
	}
	core.app.cpu_samples[core.SAMPLE_COUNT-1] = v
}

push_mem_sample :: proc(v: f32) {
	for i in 1..<core.SAMPLE_COUNT {
		core.app.mem_samples[i-1] = core.app.mem_samples[i]
	}
	core.app.mem_samples[core.SAMPLE_COUNT-1] = v
}

push_gpu_sample :: proc(v: f32) {
	for i in 1..<core.SAMPLE_COUNT {
		core.app.gpu_samples[i-1] = core.app.gpu_samples[i]
	}
	core.app.gpu_samples[core.SAMPLE_COUNT-1] = v
}

update_core_usage :: proc() {
	if core.app.cores <= 0 {
		return
	}

	times: [core.MAX_CORES]platform.Core_Times
	status := platform.NtQuerySystemInformation(
		platform.SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION,
		rawptr(&times[0]),
		u32(core.app.cores * size_of(platform.Core_Times)),
		nil,
	)
	if status != 0 {
		return
	}

	if core.app.have_core_prev {
		for i in 0..<core.app.cores {
			prev := core.app.core_prev[i]
			cur := times[i]
			delta_idle := cur.idle - prev.idle
			delta_total := (cur.kernel + cur.user) - (prev.kernel + prev.user)
			if delta_total > 0 {
				busy := delta_total - delta_idle
				if busy < 0 {
					busy = 0
				}
				pct := f32(f64(busy) / f64(delta_total) * 100.0)
				if pct < 0 {
					pct = 0
				}
				if pct > 100 {
					pct = 100
				}
				core.app.core_usage[i] = pct
			}
		}
	}

	for i in 0..<core.app.cores {
		core.app.core_prev[i] = times[i]
		push_sample(core.app.core_samples[i][:], core.app.core_usage[i])
	}
	core.app.have_core_prev = true
}

wide_has_ascii :: proc(text: [^]u16, needle: string) -> bool {
	if text == nil || len(needle) == 0 {
		return false
	}
	for i := 0; text[i] != 0; i += 1 {
		ok := true
		for j in 0..<len(needle) {
			c := text[i+j]
			if c == 0 {
				ok = false
				break
			}
			cc := c
			if cc >= 'A' && cc <= 'Z' {
				cc += 32
			}
			n := needle[j]
			if n >= 'A' && n <= 'Z' {
				n += 32
			}
			if u8(cc) != n {
				ok = false
				break
			}
		}
		if ok {
			return true
		}
	}
	return false
}

// GPU Engine instance names look like
// "pid_1234_luid_0x00000000_0x0000CEFE_phys_0_eng_0_engtype_3D"; the leading
// pid is the process the engine usage belongs to.
gpu_engine_pid :: proc(name: [^]u16) -> u32 {
	if name == nil {
		return 0
	}
	prefix := [?]u16{'p', 'i', 'd', '_'}
	for i in 0..<len(prefix) {
		if name[i] != prefix[i] {
			return 0
		}
	}
	pid: u32 = 0
	for i := len(prefix); name[i] >= '0' && name[i] <= '9'; i += 1 {
		pid = pid*10 + u32(name[i] - '0')
	}
	return pid
}

gpu_engine_group :: proc(name: [^]u16) -> int {
	if wide_has_ascii(name, "engtype_3d") {
		return 0
	}
	if wide_has_ascii(name, "engtype_copy") {
		return 1
	}
	if wide_has_ascii(name, "engtype_videodecode") {
		return 2
	}
	if wide_has_ascii(name, "engtype_videoencode") {
		return 3
	}
	if wide_has_ascii(name, "engtype_compute") {
		return 4
	}
	return 5
}

update_pdh_rates :: proc() {
	core.app.task.gpu = 0
	core.app.gpu_pid_count = 0
	if core.app.pdh_query == nil {
		core.app.disk_read_bps = 0
		core.app.disk_write_bps = 0
		return
	}
	if platform.PdhCollectQueryData(core.app.pdh_query) != 0 {
		core.app.disk_read_bps = 0
		core.app.disk_write_bps = 0
		return
	}

	if core.app.pdh_read != nil {
		value: platform.Pdh_Fmt_Counter_Value
		if platform.PdhGetFormattedCounterValue(core.app.pdh_read, platform.PDH_FMT_DOUBLE, nil, &value) == 0 && value.status <= 1 {
			core.app.disk_read_bps = max(value.double_value, 0.0)
		}

		value = {}
		if platform.PdhGetFormattedCounterValue(core.app.pdh_write, platform.PDH_FMT_DOUBLE, nil, &value) == 0 && value.status <= 1 {
			core.app.disk_write_bps = max(value.double_value, 0.0)
		}
	}

	if core.app.gpu_counter != nil {
		buffer_size := u32(size_of(core.app.pdh_buffer))
		item_count: u32
		status := platform.PdhGetFormattedCounterArrayW(
			core.app.gpu_counter,
			platform.PDH_FMT_DOUBLE,
			&buffer_size,
			&item_count,
			rawptr(&core.app.pdh_buffer[0]),
		)
		if status == 0 {
			sums: [core.GPU_ENGINE_COUNT]f64
			ptr := uintptr(&core.app.pdh_buffer[0])
			for _ in 0..<item_count {
				item := cast(^platform.Pdh_Fmt_Counter_Value_Item)ptr
				if item.value.status <= 1 {
					v := item.value.double_value
					if v > 0 {
						group := gpu_engine_group(cast([^]u16)item.name)
						sums[group] += v
						gpu_usage_add(gpu_engine_pid(cast([^]u16)item.name), f32(v))
					}
				}
				ptr += uintptr(size_of(platform.Pdh_Fmt_Counter_Value_Item))
			}

			overall: f64 = 0
			for i in 0..<core.GPU_ENGINE_COUNT {
				v := sums[i]
				if v > 100 {
					v = 100
				}
				if v > overall {
					overall = v
				}
			}
			core.app.gpu = f32(overall)
			core.app.gpu_ok = true
		}
	}

	if core.app.gpu_mem_counter != nil {
		buffer_size := u32(size_of(core.app.pdh_buffer))
		item_count: u32
		status := platform.PdhGetFormattedCounterArrayW(
			core.app.gpu_mem_counter,
			platform.PDH_FMT_DOUBLE,
			&buffer_size,
			&item_count,
			rawptr(&core.app.pdh_buffer[0]),
		)
		if status == 0 {
			max_bytes: f64 = 0
			ptr := uintptr(&core.app.pdh_buffer[0])
			for _ in 0..<item_count {
				item := cast(^platform.Pdh_Fmt_Counter_Value_Item)ptr
				if item.value.status <= 1 && item.value.double_value > max_bytes {
					max_bytes = item.value.double_value
				}
				ptr += uintptr(size_of(platform.Pdh_Fmt_Counter_Value_Item))
			}
			core.app.gpu_vram = f32(max_bytes / core.GIB)
			core.app.gpu_mem_ok = true
		}
	}
}

update_network_rates :: proc(now: u64) {
	size := u32(size_of(core.app.net_table))
	status := platform.GetIfTable(rawptr(&core.app.net_table), &size, win.FALSE)
	if status != 0 {
		core.app.net_ok = false
		core.app.net_online = false
		core.app.net_in_bps = 0
		core.app.net_out_bps = 0
		core.app.net_have_prev = false
		core.app.net_prev_count = 0
		return
	}
	core.app.net_ok = true

	next_prev: [core.MAX_NET_INTERFACES]core.If_Counter
	next_count := 0
	max_in: f64 = 0
	max_out: f64 = 0
	online := false
	has_prev := core.app.net_have_prev && now > core.app.net_last_ms
	seconds := f64(now - core.app.net_last_ms) / 1000.0

	count := min(int(core.app.net_table.count), len(core.app.net_table.rows))
	for i in 0..<count {
		row := &core.app.net_table.rows[i]
		if row.type_ != platform.IF_TYPE_ETHERNET_CSMACD && row.type_ != platform.IF_TYPE_IEEE80211 {
			continue
		}
		// Adapters without media (WAN Miniports, unplugged NICs) still show up as
		// connected but never report a link speed.
		if row.speed == 0 {
			continue
		}
		// Only adapters that are enabled and actually attached to a network can
		// move traffic. Disconnected adapters keep their last counters around,
		// so including them keeps reporting stale rates while offline.
		if row.admin_status != platform.IF_ADMIN_STATUS_UP {
			continue
		}
		if row.oper_status != platform.IF_OPER_STATUS_CONNECTED && row.oper_status != platform.IF_OPER_STATUS_OPERATIONAL {
			continue
		}
		descr_len := min(int(row.descr_len), len(row.descr))
		if core.is_virtual_adapter(row.descr[:descr_len]) {
			continue
		}
		online = true

		if has_prev && seconds > 0 {
			for j in 0..<core.app.net_prev_count {
				prev := core.app.net_prev_if[j]
				if prev.index != row.index {
					continue
				}
				delta_in := core.wrapped_delta_u32(row.in_octets, prev.bytes_in)
				delta_out := core.wrapped_delta_u32(row.out_octets, prev.bytes_out)
				limit := f64(row.speed) / 8.0 * seconds * 2.0 + 1_000_000.0
				if f64(delta_in) <= limit && f64(delta_out) <= limit {
					in_rate := f64(delta_in) / seconds
					out_rate := f64(delta_out) / seconds
					if in_rate > max_in {
						max_in = in_rate
					}
					if out_rate > max_out {
						max_out = out_rate
					}
				}
				break
			}
		}

		if next_count < core.MAX_NET_INTERFACES {
			next_prev[next_count] = core.If_Counter{index = row.index, bytes_in = row.in_octets, bytes_out = row.out_octets}
			next_count += 1
		}
	}

	for i in 0..<next_count {
		core.app.net_prev_if[i] = next_prev[i]
	}
	core.app.net_prev_count = next_count

	core.app.net_online = online
	if !online {
		core.app.net_in_bps = 0
		core.app.net_out_bps = 0
	} else if has_prev && seconds > 0 {
		core.app.net_in_bps = max(max_in, 0)
		core.app.net_out_bps = max(max_out, 0)
	}

	core.app.net_last_ms = now
	core.app.net_have_prev = true
}

update_metrics :: proc() {
	now := platform.GetTickCount64()

	idle, kernel, user: win.FILETIME
	platform.GetSystemTimes(&idle, &kernel, &user)

	idle_now := core.filetime_value(idle)
	kernel_now := core.filetime_value(kernel)
	user_now := core.filetime_value(user)

	if core.app.have_last {
		delta_idle := idle_now - core.app.last_idle
		delta_total := (kernel_now - core.app.last_kernel) + (user_now - core.app.last_user)
		if delta_total > 0 {
			busy := delta_total > delta_idle ? delta_total - delta_idle : 0
			pct := f32(busy) / f32(delta_total) * 100.0
			if pct < 0 {
				pct = 0
			}
			if pct > 100 {
				pct = 100
			}
			core.app.cpu = pct
		}
	}

	core.app.last_idle = idle_now
	core.app.last_kernel = kernel_now
	core.app.last_user = user_now
	core.app.have_last = true
	push_cpu_sample(core.app.cpu)

	update_core_usage()

	mem: win.MEMORYSTATUSEX
	mem.dwLength = u32(size_of(win.MEMORYSTATUSEX))
	if win.GlobalMemoryStatusEx(&mem) {
		total := f32(mem.ullTotalPhys)
		avail := f32(mem.ullAvailPhys)
		if total > 0 {
			used := total - avail
			core.app.mem_total = total / f32(core.GIB)
			core.app.mem_used = used / f32(core.GIB)
			core.app.mem_percent = used / total * 100.0
		}
	}

	push_mem_sample(core.app.mem_percent)

	update_pdh_rates()
	push_gpu_sample(core.app.gpu)

	update_network_rates(now)
	update_task_metrics()

	core.app.uptime_secs = now / 1000
}

format_uptime :: proc(buf: []u8) -> string {
	secs := core.app.uptime_secs
	days := secs / 86400
	hours := (secs % 86400) / 3600
	mins := (secs % 3600) / 60

	if days > 0 {
		return fmt.bprintf(buf, "%dd %dh %dm", days, hours, mins)
	}
	if hours > 0 {
		return fmt.bprintf(buf, "%dh %dm", hours, mins)
	}
	return fmt.bprintf(buf, "%dm", mins)
}

format_memory :: proc(buf: []u8, bytes: u64) -> string {
	if bytes == 0 {
		return "—"
	}
	mb := f64(bytes) / (1024.0*1024.0)
	if mb >= 1024.0 {
		return fmt.bprintf(buf, "%.1f GB", mb/1024.0)
	}
	return fmt.bprintf(buf, "%.0f MB", mb)
}

format_cpu_time :: proc(buf: []u8, ticks: u64) -> string {
	secs := ticks / 10_000_000
	hours := secs / 3600
	mins := (secs % 3600) / 60
	rem := secs % 60
	if hours > 0 {
		return fmt.bprintf(buf, "%dh %dm %ds", hours, mins, rem)
	}
	if mins > 0 {
		return fmt.bprintf(buf, "%dm %ds", mins, rem)
	}
	return fmt.bprintf(buf, "%ds", rem)
}

rate_scale :: proc(bps: f64) -> (factor: f64, suffix: string) {
	if bps >= 1e9 {
		return 1e9, "GB/s"
	}
	if bps >= 1e6 {
		return 1e6, "MB/s"
	}
	if bps >= 1e3 {
		return 1e3, "KB/s"
	}
	return 1.0, "B/s"
}

init_pdh_counters :: proc() {
	query: rawptr
	if platform.PdhOpenQueryW(nil, 0, &query) != 0 {
		return
	}

	any_counter := false

	read_path := win.utf8_to_wstring_alloc("\\PhysicalDisk(_Total)\\Disk Read Bytes/sec")
	write_path := win.utf8_to_wstring_alloc("\\PhysicalDisk(_Total)\\Disk Write Bytes/sec")

	read_counter, write_counter: rawptr
	read_ok := platform.PdhAddEnglishCounterW(query, read_path, 0, &read_counter) == 0
	write_ok := platform.PdhAddEnglishCounterW(query, write_path, 0, &write_counter) == 0
	if read_ok && write_ok {
		core.app.pdh_read = read_counter
		core.app.pdh_write = write_counter
		core.app.pdh_ok = true
		any_counter = true
	}

	gpu_path := win.utf8_to_wstring_alloc("\\GPU Engine(*)\\Utilization Percentage")
	gpu_counter: rawptr
	if platform.PdhAddEnglishCounterW(query, gpu_path, 0, &gpu_counter) == 0 {
		core.app.gpu_counter = gpu_counter
		any_counter = true
	}

	gpu_mem_path := win.utf8_to_wstring_alloc("\\GPU Adapter Memory(*)\\Dedicated Usage")
	gpu_mem_counter: rawptr
	if platform.PdhAddEnglishCounterW(query, gpu_mem_path, 0, &gpu_mem_counter) == 0 {
		core.app.gpu_mem_counter = gpu_mem_counter
		any_counter = true
	}

	if !any_counter {
		_ = platform.PdhCloseQuery(query)
		return
	}

	if platform.PdhCollectQueryData(query) != 0 {
		_ = platform.PdhCloseQuery(query)
		return
	}

	core.app.pdh_query = query
}
