package main

import win "core:sys/windows"

foreign import user32 "system:User32.lib"
foreign import gdi32 "system:Gdi32.lib"
foreign import kernel32 "system:Kernel32.lib"
foreign import ntdll "system:ntdll.lib"
foreign import psapi "system:Psapi.lib"
foreign import pdh "system:Pdh.lib"
foreign import iphlpapi "system:iphlpapi.lib"
foreign import comdlg32 "system:Comdlg32.lib"

CC_RGBINIT   :: 0x00000001
CC_FULLOPEN  :: 0x00000002
CC_ANYCOLOR  :: 0x00000100

CHOOSECOLORW :: struct {
	lStructSize:    win.DWORD,
	hwndOwner:      win.HWND,
	hInstance:      win.HWND,
	rgbResult:      win.COLORREF,
	lpCustColors:   ^win.COLORREF,
	Flags:          win.DWORD,
	lCustData:      win.LPARAM,
	lpfnHook:       rawptr,
	lpTemplateName: win.LPCWSTR,
}

#assert(size_of(CHOOSECOLORW) == 72)

@(default_calling_convention="system")
foreign comdlg32 {
	ChooseColorW :: proc(lpcc: ^CHOOSECOLORW) -> win.BOOL ---
}

@(default_calling_convention="system")
foreign user32 {
	DrawTextW :: proc(hdc: win.HDC, text: win.LPCWSTR, length: i32, rect: ^win.RECT, format: u32) -> i32 ---
}

@(default_calling_convention="system")
foreign gdi32 {
	Polyline :: proc(hdc: win.HDC, points: [^]win.POINT, count: i32) -> win.BOOL ---
}

@(default_calling_convention="system")
foreign kernel32 {
	GetSystemTimes :: proc(idle: ^win.FILETIME, kernel: ^win.FILETIME, user: ^win.FILETIME) -> win.BOOL ---
	GetTickCount64 :: proc() -> u64 ---
}

SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION :: 8

Core_Times :: struct {
	idle:            i64,
	kernel:          i64,
	user:            i64,
	dpc:             i64,
	interrupt:       i64,
	interrupt_count: u32,
}

#assert(size_of(Core_Times) == 48)

@(default_calling_convention="system")
foreign ntdll {
	NtQuerySystemInformation :: proc(
		info_class:    u32,
		info:          rawptr,
		length:        u32,
		return_length: ^u32,
	) -> i32 ---
}

Performance_Information :: struct {
	cb:                 u32,
	commit_total:       uint,
	commit_limit:       uint,
	commit_peak:        uint,
	physical_total:     uint,
	physical_available: uint,
	system_cache:       uint,
	kernel_total:       uint,
	kernel_paged:       uint,
	kernel_nonpaged:    uint,
	page_size:          uint,
	handle_count:       u32,
	process_count:      u32,
	thread_count:       u32,
}

#assert(size_of(Performance_Information) == 104)

Process_Memory_Counters :: struct {
	cb:                           u32,
	page_fault_count:             u32,
	peak_working_set_size:        uint,
	working_set_size:             uint,
	quota_peak_paged_pool_usage:  uint,
	quota_paged_pool_usage:       uint,
	quota_peak_nonpaged_pool_usage: uint,
	quota_nonpaged_pool_usage:    uint,
	pagefile_usage:               uint,
	peak_pagefile_usage:          uint,
}

#assert(size_of(Process_Memory_Counters) == 72)

@(default_calling_convention="system")
foreign psapi {
	GetPerformanceInfo :: proc(info: ^Performance_Information, size: u32) -> win.BOOL ---
	GetProcessMemoryInfo :: proc(process: win.HANDLE, counters: ^Process_Memory_Counters, size: u32) -> win.BOOL ---
}

PDH_FMT_DOUBLE :: 0x00000200

Pdh_Fmt_Counter_Value :: struct {
	status: u32,
	using _: struct #raw_union {
		double_value: f64,
		large_value:  i64,
		long_value:   i32,
		wide_value:   win.LPCWSTR,
		ansi_value:   cstring,
	},
}

#assert(size_of(Pdh_Fmt_Counter_Value) == 16)

Pdh_Fmt_Counter_Value_Item :: struct {
	name:  win.LPWSTR,
	value: Pdh_Fmt_Counter_Value,
}

#assert(size_of(Pdh_Fmt_Counter_Value_Item) == 24)

@(default_calling_convention="system")
foreign pdh {
	PdhOpenQueryW :: proc(data_source: win.LPCWSTR, user_data: uintptr, query: ^rawptr) -> i32 ---
	PdhAddEnglishCounterW :: proc(query: rawptr, path: win.LPCWSTR, user_data: uintptr, counter: ^rawptr) -> i32 ---
	PdhCollectQueryData :: proc(query: rawptr) -> i32 ---
	PdhGetFormattedCounterValue :: proc(counter: rawptr, format: u32, counter_type: ^u32, value: ^Pdh_Fmt_Counter_Value) -> i32 ---
	PdhGetFormattedCounterArrayW :: proc(counter: rawptr, format: u32, buffer_size: ^u32, item_count: ^u32, buffer: rawptr) -> i32 ---
	PdhCloseQuery :: proc(query: rawptr) -> i32 ---
}

IF_TYPE_ETHERNET_CSMACD :: 6
IF_TYPE_IEEE80211       :: 71
MAX_NET_ROWS            :: 150

Mib_If_Row :: struct {
	name:              [256]u16,
	index:             u32,
	type_:             u32,
	mtu:               u32,
	speed:             u32,
	phys_addr_len:     u32,
	phys_addr:         [8]u8,
	admin_status:      u32,
	oper_status:       u32,
	last_change:       u32,
	in_octets:         u32,
	in_ucast_pkts:     u32,
	in_nucast_pkts:    u32,
	in_discards:       u32,
	in_errors:         u32,
	in_unknown_protos: u32,
	out_octets:        u32,
	out_ucast_pkts:    u32,
	out_nucast_pkts:   u32,
	out_discards:      u32,
	out_errors:        u32,
	out_qlen:          u32,
	descr_len:         u32,
	descr:             [256]u8,
}

#assert(size_of(Mib_If_Row) == 860)

Mib_If_Table :: struct {
	count: u32,
	rows:  [MAX_NET_ROWS]Mib_If_Row,
}

@(default_calling_convention="system")
foreign iphlpapi {
	GetIfTable :: proc(table: rawptr, size: ^u32, order: win.BOOL) -> u32 ---
}

PROCESS_QUERY_INFORMATION         :: 0x0400
PROCESS_QUERY_LIMITED_INFORMATION :: 0x1000
PROCESS_VM_READ                   :: 0x0010

DT_LEFT         :: u32(0x00000000)
DT_CENTER       :: u32(0x00000001)
DT_RIGHT        :: u32(0x00000002)
DT_VCENTER      :: u32(0x00000004)
DT_SINGLELINE   :: u32(0x00000020)
DT_END_ELLIPSIS :: u32(0x00008000)
DT_NOPREFIX     :: u32(0x00000800)
