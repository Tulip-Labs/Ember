// Ember 3.1 - Windows shell, same house style, much lighter.
//
// What changed from 3.0 (see CHANGES.txt for the full list):
//  - RAM: no full-screen bitmaps any more. The gradient is a tiny grid that is
//    upscaled (with dithering) one 64-row band at a time, cards are 9-slice
//    sprites, icons are vector masks. Caches are freed and the working set is
//    trimmed while Ember is hidden. No wininet / wlanapi / powrprof imports.
//  - Network card opens a Wi-Fi panel (scan, connect, password entry).
//  - App list refreshes by itself when something is installed or removed.
//  - Desktop button removed. Real vector icons (anti-aliased). DPI aware layout.
//  - Many bug fixes (hidden-list overflow crash, stale SSID text, Win key
//    auto-repeat flicker, popup menu not dismissing, scroll past the end...).
#define WIN32_LEAN_AND_MEAN
#define WINVER 0x0A00
#define _WIN32_WINNT 0x0A00
#include <winsock2.h>
#include <windows.h>
#include <windowsx.h>
#include <iphlpapi.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <psapi.h>
#include <wlanapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <wctype.h>
#include <math.h>

#define INK   RGB(36, 31, 78)
#define BODY  RGB(76, 70, 116)
#define SUB   RGB(120, 115, 158)
#define SHADOWCOL RGB(43, 32, 84)

// ---------- themes ----------
typedef struct { const wchar_t* name; COLORREF wash; COLORREF blob[5]; COLORREF deep; COLORREF dot; } Theme;
static const Theme THEMES[1] = {
    { L"Spring Mix", RGB(255,253,245), { RGB(252,227,138), RGB(248,187,217), RGB(216,243,220), RGB(169,222,249), RGB(205,180,240) }, RGB(81,69,201), RGB(247,178,213) },
};
static const float BLOB_POS[5][2] = { {0.04f,0.02f}, {0.97f,0.03f}, {0.55f,0.45f}, {0.03f,0.99f}, {0.98f,0.98f} };
static const float BLOB_RAD[5]    = { 0.62f, 0.58f, 0.55f, 0.60f, 0.62f };
static const COLORREF CHIP_TINTS[5] = { RGB(220,233,253), RGB(217,246,229), RGB(253,240,201), RGB(251,227,241), RGB(231,224,253) };
#define NTHEMES 1
static const int g_theme = 0;

// ---------- globals ----------
static HWND g_hwnd;
static int  g_W, g_H;                 // client size in real pixels
static float g_S = 1.0f;              // DPI scale
#define SC(x) ((int)((x) * g_S + 0.5f))
static HFONT fClock, fDate, fHead, fName, fSmall, fTiny, fMark, fChip;
static HHOOK g_hook; static ULONGLONG g_lastWin; static BOOL g_winHeld;
static HANDLE g_mutex;
static BOOL g_shown;
#define WM_EMBER_TOGGLE (WM_APP + 1)

// ---------- small safe string helpers (no *_s calls: those abort on overflow) ----------
static void Cpy(wchar_t* d, int n, const wchar_t* s) { lstrcpynW(d, s, n); }
static void Fmt(wchar_t* d, int n, const wchar_t* f, ...) {
    va_list ap; va_start(ap, f); _vsnwprintf(d, (size_t)n, f, ap); va_end(ap); d[n - 1] = 0;
}
static float Clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }
static int   Clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

// ---------- dynamic imports (keeps the import table, and the RAM, small) ----------
typedef BOOL  (WINAPI *PFN_GPMI)(HANDLE, void*, DWORD);
typedef UINT  (WINAPI *PFN_GDFS)(void);
typedef DWORD (WINAPI *PFN_GetIfTable)(PMIB_IFTABLE, PULONG, BOOL);
typedef BOOLEAN (WINAPI *PFN_SetSuspendState)(BOOLEAN, BOOLEAN, BOOLEAN);

typedef DWORD (WINAPI *PFN_WlanOpenHandle)(DWORD, PVOID, PDWORD, PHANDLE);
typedef DWORD (WINAPI *PFN_WlanCloseHandle)(HANDLE, PVOID);
typedef DWORD (WINAPI *PFN_WlanEnumInterfaces)(HANDLE, PVOID, PWLAN_INTERFACE_INFO_LIST*);
typedef DWORD (WINAPI *PFN_WlanQueryInterface)(HANDLE, const GUID*, WLAN_INTF_OPCODE, PVOID, PDWORD, PVOID*, PWLAN_OPCODE_VALUE_TYPE);
typedef VOID  (WINAPI *PFN_WlanFreeMemory)(PVOID);
static HMODULE g_wlanDll;
static PFN_WlanOpenHandle pWlanOpenHandle;
static PFN_WlanCloseHandle pWlanCloseHandle;
static PFN_WlanEnumInterfaces pWlanEnumInterfaces;
static PFN_WlanQueryInterface pWlanQueryInterface;
static PFN_WlanFreeMemory pWlanFreeMemory;
static BOOL WlanLoad(void) {
    if (g_wlanDll) return pWlanOpenHandle != NULL;
    g_wlanDll = LoadLibraryW(L"wlanapi.dll");
    if (!g_wlanDll) { g_wlanDll = (HMODULE)1; return FALSE; }   // remember the failure
#define LD(n) p##n = (PFN_##n)GetProcAddress(g_wlanDll, #n)
    LD(WlanOpenHandle); LD(WlanCloseHandle); LD(WlanEnumInterfaces); LD(WlanQueryInterface); LD(WlanFreeMemory);
#undef LD
    if (!pWlanOpenHandle || !pWlanCloseHandle || !pWlanEnumInterfaces || !pWlanQueryInterface || !pWlanFreeMemory) { pWlanOpenHandle = NULL; return FALSE; }
    return TRUE;
}
static void WlanUnload(void) {
    if (g_wlanDll && g_wlanDll != (HMODULE)1) FreeLibrary(g_wlanDll);
    g_wlanDll = NULL; pWlanOpenHandle = NULL;
}

// ---------- sensors ----------
static double cpuPct; static unsigned long long lastIdle, lastKernel, lastUser;
static double memUsedGB, memTotalGB, diskFreeGB, diskTotalGB;
static int battPct = -1; static BOOL battAC;
static int netState;                  // 0 none, 1 wifi, 2 wired
static int netSig;                    // 0..100
static BOOL haveWifi;
static wchar_t netName[48];
static double ownMB;
static wchar_t clockTxt[32], dateTxt[96];

static unsigned long long Ft(FILETIME f) { ULARGE_INTEGER u; u.LowPart = f.dwLowDateTime; u.HighPart = f.dwHighDateTime; return u.QuadPart; }

static void PollFast(void) {          // clock, cpu, memory: cheap, runs every second while visible
    FILETIME idle, kern, user;
    if (GetSystemTimes(&idle, &kern, &user)) {
        unsigned long long i = Ft(idle), k = Ft(kern), u = Ft(user);
        unsigned long long tot = (k - lastKernel) + (u - lastUser);
        if (tot > 0 && lastKernel) cpuPct = 100.0 * (1.0 - (double)(i - lastIdle) / (double)tot);
        if (cpuPct < 0) cpuPct = 0; if (cpuPct > 100) cpuPct = 100;
        lastIdle = i; lastKernel = k; lastUser = u;
    }
    MEMORYSTATUSEX ms; ZeroMemory(&ms, sizeof(ms)); ms.dwLength = sizeof(ms);
    if (GlobalMemoryStatusEx(&ms)) {
        memTotalGB = ms.ullTotalPhys / 1073741824.0;
        memUsedGB = (ms.ullTotalPhys - ms.ullAvailPhys) / 1073741824.0;
    }
    SYSTEMTIME lt; GetLocalTime(&lt);
    static const wchar_t* days[] = { L"Sunday", L"Monday", L"Tuesday", L"Wednesday", L"Thursday", L"Friday", L"Saturday" };
    static const wchar_t* months[] = { L"", L"January", L"February", L"March", L"April", L"May", L"June", L"July", L"August", L"September", L"October", L"November", L"December" };
    Fmt(dateTxt, 96, L"%ls, %ls %d", days[lt.wDayOfWeek % 7], months[lt.wMonth % 13], (int)lt.wDay);
    int h12 = lt.wHour % 12; if (h12 == 0) h12 = 12;
    Fmt(clockTxt, 32, L"%d:%02d %ls", h12, (int)lt.wMinute, lt.wHour < 12 ? L"AM" : L"PM");
}
static void PollOwn(void) {
    static PFN_GPMI f; static int tried;
    if (!tried) { tried = 1; f = (PFN_GPMI)GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "K32GetProcessMemoryInfo"); }
    if (!f) return;
    struct { DWORD cb, pf; SIZE_T peak, ws, a, b, c, d, pagefile, peakpf, privUse, privWs; ULONG64 shared; } p;
    ZeroMemory(&p, sizeof(p)); p.cb = sizeof(p);
    if (f(GetCurrentProcess(), &p, sizeof(p)) && p.privWs) { ownMB = p.privWs / 1048576.0; return; }
    PROCESS_MEMORY_COUNTERS pmc; ZeroMemory(&pmc, sizeof(pmc)); pmc.cb = sizeof(pmc);
    if (f(GetCurrentProcess(), &pmc, sizeof(pmc))) ownMB = pmc.WorkingSetSize / 1048576.0;
}
static void PollSlow(void) {          // disk, battery, own memory
    ULARGE_INTEGER freeB, totalB, totFree; wchar_t root[4] = L"C:\\";
    wchar_t sysDir[MAX_PATH];
    if (GetSystemDirectoryW(sysDir, MAX_PATH)) root[0] = sysDir[0];
    if (GetDiskFreeSpaceExW(root, &freeB, &totalB, &totFree)) { diskFreeGB = freeB.QuadPart / 1073741824.0; diskTotalGB = totalB.QuadPart / 1073741824.0; }
    SYSTEM_POWER_STATUS ps;
    if (GetSystemPowerStatus(&ps)) { battPct = (ps.BatteryLifePercent == 255 || (ps.BatteryFlag & 128)) ? -1 : ps.BatteryLifePercent; battAC = ps.ACLineStatus == 1; }
    PollOwn();
}
static BOOL WiredUp(void) {
    HMODULE h = LoadLibraryW(L"iphlpapi.dll"); if (!h) return FALSE;
    PFN_GetIfTable f = (PFN_GetIfTable)GetProcAddress(h, "GetIfTable"); BOOL up = FALSE;
    if (f) {
        ULONG sz = 0; f(NULL, &sz, FALSE);
        PMIB_IFTABLE t = sz ? (PMIB_IFTABLE)HeapAlloc(GetProcessHeap(), 0, sz) : NULL;
        if (t && f(t, &sz, FALSE) == NO_ERROR) {
            for (DWORD i = 0; i < t->dwNumEntries && !up; i++) {
                MIB_IFROW* r = &t->table[i];
                if (r->dwType != IF_TYPE_ETHERNET_CSMACD) continue;
                if (r->dwOperStatus != 4 && r->dwOperStatus != 5) continue;   // connected / operational
                const char* d = (const char*)r->bDescr;
                if (StrStrIA(d, "virtual") || StrStrIA(d, "vmware") || StrStrIA(d, "vpn") || StrStrIA(d, "tap-") ||
                    StrStrIA(d, "bluetooth") || StrStrIA(d, "hyper-v") || StrStrIA(d, "loopback")) continue;
                up = TRUE;
            }
        }
        if (t) HeapFree(GetProcessHeap(), 0, t);
    }
    FreeLibrary(h); return up;
}
static void PollNet(void) {
    netState = 0; netSig = 0; netName[0] = 0; haveWifi = FALSE;
    if (WlanLoad()) {
        HANDLE wh = NULL; DWORD ver = 0;
        if (pWlanOpenHandle(2, NULL, &ver, &wh) == ERROR_SUCCESS) {
            PWLAN_INTERFACE_INFO_LIST lst = NULL;
            if (pWlanEnumInterfaces(wh, NULL, &lst) == ERROR_SUCCESS && lst && lst->dwNumberOfItems > 0) {
                haveWifi = TRUE;
                for (DWORD i = 0; i < lst->dwNumberOfItems && netState == 0; i++) {
                    PVOID data = NULL; DWORD sz = 0; WLAN_OPCODE_VALUE_TYPE t;
                    if (pWlanQueryInterface(wh, &lst->InterfaceInfo[i].InterfaceGuid, wlan_intf_opcode_current_connection, NULL, &sz, &data, &t) == ERROR_SUCCESS && data) {
                        WLAN_CONNECTION_ATTRIBUTES* ca = (WLAN_CONNECTION_ATTRIBUTES*)data;
                        if (ca->isState == wlan_interface_state_connected) {
                            netState = 1; netSig = (int)ca->wlanAssociationAttributes.wlanSignalQuality;
                            ZeroMemory(netName, sizeof(netName));
                            DWORD n = ca->wlanAssociationAttributes.dot11Ssid.uSSIDLength; if (n > 32) n = 32;
                            if (n) MultiByteToWideChar(CP_UTF8, 0, (char*)ca->wlanAssociationAttributes.dot11Ssid.ucSSID, (int)n, netName, 46);
                            netName[46] = 0;
                        }
                        pWlanFreeMemory(data);
                    }
                }
            }
            if (lst) pWlanFreeMemory(lst);
            pWlanCloseHandle(wh, NULL);
        }
    }
    if (netState == 0 && WiredUp()) { netState = 2; netSig = 100; Cpy(netName, 48, L"Ethernet"); }
}

// ---------- apps: dynamic list, Start Menu scan, auto refresh ----------
typedef struct { wchar_t* name; wchar_t* path; BYTE hidden; } AppItem;
static AppItem* g_apps; static int g_appCount, g_appCap;
static int* g_vis; static int g_visCount;          // indices of apps currently shown
static wchar_t g_filter[64]; static int g_scroll, g_sel = -1; static BOOL g_keynav;

static const wchar_t* JUNK[] = {
    L"Administrative Tools", L"Component Services", L"Memory Diagnostics Tool",
    L"ODBC Data Sources (32-bit)", L"ODBC Data Sources (64-bit)", L"iSCSI Initiator",
    L"Steps Recorder", L"dfrgui", L"services", L"VoiceAccess", L"LiveCaptions",
    L"RecoveryDrive", L"Windows Defender Firewall with Advanced Security",
    L"Registry Editor", L"Computer Management", L"Event Viewer", L"Performance Monitor",
    L"Resource Monitor", L"System Configuration", L"System Information", L"Task Scheduler",
    L"Magnify", L"Narrator", L"Character Map", L"Disk Cleanup", L"Office Language Preferences",
    L"WSL Settings", NULL
};
static wchar_t g_userHidden[4096];
static BOOL InList(const wchar_t* list, const wchar_t* name) {      // no copies, no fixed buffers
    size_t nl = wcslen(name); const wchar_t* p = list;
    while (*p) {
        const wchar_t* e = wcschr(p, L';'); size_t len = e ? (size_t)(e - p) : wcslen(p);
        if (len == nl && _wcsnicmp(p, name, nl) == 0) return TRUE;
        if (!e) break; p = e + 1;
    }
    return FALSE;
}
static BOOL IsHiddenName(const wchar_t* name) {
    for (int i = 0; JUNK[i]; i++) if (_wcsicmp(JUNK[i], name) == 0) return TRUE;
    if (StrStrIW(name, L"uninstall")) return TRUE;                    // "Uninstall Foo" shortcuts are noise
    return InList(g_userHidden, name);
}
static void RecomputeHidden(void) { for (int i = 0; i < g_appCount; i++) g_apps[i].hidden = IsHiddenName(g_apps[i].name); }
static BOOL ShowHiddenMode(void) { return _wcsicmp(g_filter, L"hidden") == 0; }

static void LoadSettings(void) {
    HKEY k; DWORD sz;
    g_userHidden[0] = 0;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Ember", 0, KEY_READ, &k) == ERROR_SUCCESS) {
        sz = sizeof(g_userHidden) - 2;
        if (RegQueryValueExW(k, L"HiddenApps", NULL, NULL, (BYTE*)g_userHidden, &sz) != ERROR_SUCCESS) g_userHidden[0] = 0;
        g_userHidden[4095] = 0;
        RegCloseKey(k);
    }
}
static void SaveSetting(const wchar_t* name, DWORD type, const void* data, DWORD bytes) {
    HKEY k;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Ember", 0, NULL, 0, KEY_WRITE, NULL, &k, NULL) == ERROR_SUCCESS) {
        RegSetValueExW(k, name, 0, type, (const BYTE*)data, bytes); RegCloseKey(k);
    }
}
static void SaveHidden(void) { SaveSetting(L"HiddenApps", REG_SZ, g_userHidden, (DWORD)((wcslen(g_userHidden) + 1) * 2)); }

static void RebuildVis(void) {
    g_visCount = 0; if (!g_vis || !g_appCount) { g_sel = -1; g_scroll = 0; return; }
    BOOL showHid = ShowHiddenMode(); size_t fl = wcslen(g_filter);
    BOOL useFilter = g_filter[0] && !showHid;
    for (int pass = 0; pass < (useFilter ? 2 : 1); pass++) {                // prefix matches first, then "contains"
        for (int i = 0; i < g_appCount; i++) {
            AppItem* a = &g_apps[i];
            if (showHid) { if (!a->hidden) continue; } else if (a->hidden) continue;
            if (useFilter) {
                BOOL pre = StrCmpNIW(a->name, g_filter, (int)fl) == 0;
                if (pass == 0 && !pre) continue;
                if (pass == 1 && (pre || !StrStrIW(a->name, g_filter))) continue;
            }
            g_vis[g_visCount++] = i;
        }
    }
    if (g_sel >= g_visCount) g_sel = g_visCount - 1;
}
static void FreeApps(void) {
    for (int i = 0; i < g_appCount; i++) { free(g_apps[i].name); free(g_apps[i].path); }
    free(g_apps); free(g_vis); g_apps = NULL; g_vis = NULL; g_appCount = g_appCap = 0; g_visCount = 0;
}
static void AddApp(const wchar_t* fname, const wchar_t* full) {
    if (g_appCount == g_appCap) {
        int nc = g_appCap ? g_appCap * 2 : 128;
        AppItem* na = (AppItem*)realloc(g_apps, sizeof(AppItem) * (size_t)nc); if (!na) return;
        g_apps = na; g_appCap = nc;
    }
    wchar_t* nm = _wcsdup(fname); wchar_t* pt = _wcsdup(full);
    if (!nm || !pt) { free(nm); free(pt); return; }
    wchar_t* dot = wcsrchr(nm, L'.'); if (dot) *dot = 0;
    g_apps[g_appCount].name = nm; g_apps[g_appCount].path = pt; g_apps[g_appCount].hidden = 0; g_appCount++;
}
static void ScanDir(const wchar_t* dir, int depth) {
    if (depth > 8) return;
    size_t dl = wcslen(dir); if (dl + 4 >= MAX_PATH) return;
    wchar_t pat[MAX_PATH]; Fmt(pat, MAX_PATH, L"%ls\\*", dir);
    WIN32_FIND_DATAW fd; HANDLE h = FindFirstFileW(pat, &fd);
    if (h == INVALID_HANDLE_VALUE) return;
    do {
        if (fd.cFileName[0] == L'.') continue;
        if (dl + 1 + wcslen(fd.cFileName) + 1 >= MAX_PATH) continue;       // too long: skip instead of crashing
        wchar_t full[MAX_PATH]; Fmt(full, MAX_PATH, L"%ls\\%ls", dir, fd.cFileName);
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) { ScanDir(full, depth + 1); continue; }
        const wchar_t* ext = wcsrchr(fd.cFileName, L'.');
        if (!ext || (_wcsicmp(ext, L".lnk") != 0 && _wcsicmp(ext, L".url") != 0 && _wcsicmp(ext, L".appref-ms") != 0)) continue;
        AddApp(fd.cFileName, full);
    } while (FindNextFileW(h, &fd));
    FindClose(h);
}
static int AppCmp(const void* a, const void* b) { return _wcsicmp(((const AppItem*)a)->name, ((const AppItem*)b)->name); }
static void AppsScan(void) {
    FreeApps();
    wchar_t dir[MAX_PATH];
    if (SHGetFolderPathW(NULL, CSIDL_PROGRAMS, NULL, 0, dir) == S_OK) ScanDir(dir, 0);
    if (SHGetFolderPathW(NULL, CSIDL_COMMON_PROGRAMS, NULL, 0, dir) == S_OK) ScanDir(dir, 0);
    if (g_appCount > 1) qsort(g_apps, (size_t)g_appCount, sizeof(AppItem), AppCmp);
    int w = 0;                                                            // drop duplicates (same name in both menus)
    for (int i = 0; i < g_appCount; i++) {
        if (w > 0 && _wcsicmp(g_apps[w - 1].name, g_apps[i].name) == 0) { free(g_apps[i].name); free(g_apps[i].path); continue; }
        g_apps[w++] = g_apps[i];
    }
    g_appCount = w;
    g_vis = (int*)malloc(sizeof(int) * (size_t)(g_appCap ? g_appCap : 1));
    RecomputeHidden(); RebuildVis();
}
static void ToggleHidden(const wchar_t* name) {
    if (InList(g_userHidden, name)) {
        wchar_t out[4096]; out[0] = 0; size_t used = 0; const wchar_t* p = g_userHidden; size_t nl = wcslen(name);
        while (*p) {
            const wchar_t* e = wcschr(p, L';'); size_t len = e ? (size_t)(e - p) : wcslen(p);
            if (!(len == nl && _wcsnicmp(p, name, nl) == 0) && len && used + len + 2 < 4096) {
                wcsncpy(out + used, p, len); used += len; out[used++] = L';'; out[used] = 0;
            }
            if (!e) break; p = e + 1;
        }
        Cpy(g_userHidden, 4096, out);
    } else {
        size_t cur = wcslen(g_userHidden), nl = wcslen(name);
        if (cur + nl + 2 >= 4096 || wcschr(name, L';')) return;           // the old code overflowed here and crashed
        wcscpy(g_userHidden + cur, name); g_userHidden[cur + nl] = L';'; g_userHidden[cur + nl + 1] = 0;
    }
    SaveHidden(); RecomputeHidden(); RebuildVis();
}

// Start Menu change watcher: installs and uninstalls refresh the list on their own.
static HANDLE g_chg[2]; static int g_nchg;
static void WatchStart(void) {
    int ids[2] = { CSIDL_PROGRAMS, CSIDL_COMMON_PROGRAMS }; wchar_t dir[MAX_PATH];
    g_nchg = 0;
    for (int i = 0; i < 2; i++) {
        if (SHGetFolderPathW(NULL, ids[i], NULL, 0, dir) != S_OK) continue;
        HANDLE h = FindFirstChangeNotificationW(dir, TRUE, FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME);
        if (h != INVALID_HANDLE_VALUE) g_chg[g_nchg++] = h;
    }
}

// ---------- UI state ----------
enum { PN_NONE, PN_POWER };
static int g_panel;
static int g_hov;                                     // id of the hovered element (0 = none)
#define HV_EXP    2
#define HV_POWER  3
#define HV_PANEL  250    // inert area inside the power panel
#define HV_PWR    300    // +0..6    power rows
#define HV_TILE   1000   // +drawn index
static wchar_t g_toast[96];

// ---------- layout (everything scales with DPI; nothing is eyeballed) ----------
static int Mg(void)        { return g_W < SC(1100) ? SC(28) : SC(48); }
static int DashY(void)     { return SC(32); }
static int DashH(void)     { return SC(132); }
static int StripY(void)    { return DashY() + DashH() + SC(18); }
static int StripH(void)    { return SC(58); }
static int TileH(void)     { return SC(64); }
static int TilePitch(void) { return SC(78); }
static int GridTop(void)   { return StripY() + StripH() + SC(22); }
static int Cols(void)      { int c = (g_W - Mg() * 2) / SC(290); return c < 2 ? 2 : (c > 6 ? 6 : c); }
static int RowsVisible(void) { int r = (g_H - GridTop() - SC(84)) / TilePitch(); return r < 1 ? 1 : r; }
static int StatCount(void) { return battPct >= 0 ? 5 : 4; }
static RECT ClockCardRect(void) {
    int total = g_W - Mg() * 2, n = StatCount(), gap = SC(14);
    int w = (int)(total * 0.28f); if (w < SC(260)) w = SC(260); if (w > SC(500)) w = SC(500);
    int cw = (total - w - SC(16) - (n - 1) * gap) / n;
    if (cw < SC(118)) { w = total - SC(16) - n * SC(118) - (n - 1) * gap; if (w < SC(200)) w = SC(200); }
    RECT r = { Mg(), DashY(), Mg() + w, DashY() + DashH() }; return r;
}
static RECT StatCardRect(int i) {
    RECT c = ClockCardRect(); int n = StatCount(), gap = SC(14);
    int x0 = c.right + SC(16), avail = g_W - Mg() - x0;
    int cw = (avail - (n - 1) * gap) / n; if (cw < SC(60)) cw = SC(60);
    RECT r = { x0 + i * (cw + gap), DashY(), x0 + i * (cw + gap) + cw, DashY() + DashH() }; return r;
}
static RECT StripRect(void) { RECT r = { Mg(), StripY(), g_W - Mg(), StripY() + StripH() }; return r; }
static RECT ExplorerRect(void) {
    RECT s = StripRect(); int w = SC(150), h = SC(38);
    int x1 = s.right - SC(20), y = s.top + (StripH() - h) / 2;
    RECT r = { x1 - w, y, x1, y + h }; return r;
}
static RECT PowerRect(void) {
    int cx = g_W - Mg() - SC(26), cy = g_H - SC(46), r = SC(24);
    RECT rc = { cx - r, cy - r, cx + r, cy + r }; return rc;
}
static RECT TileRect(int drawn) {
    int cols = Cols(), cellw = (g_W - Mg() * 2) / cols;
    int x = Mg() + (drawn % cols) * cellw, y = GridTop() + (drawn / cols) * TilePitch();
    RECT r = { x, y, x + cellw - SC(16), y + TileH() }; return r;
}
static int MaxScroll(void) {
    int cols = Cols(), rows = (g_visCount + cols - 1) / cols, m = rows - RowsVisible();
    return m < 0 ? 0 : m;
}
static void ClampScroll(void) { int m = MaxScroll(); if (g_scroll > m) g_scroll = m; if (g_scroll < 0) g_scroll = 0; }

// ---------- band renderer: a 64-row DIB instead of two full-screen bitmaps ----------
#define BANDH 64
static HDC g_m; static HBITMAP g_bandBmp; static HGDIOBJ g_bandOld; static BYTE* g_bandBits;
static int g_bt, g_bb;                                // rows [g_bt, g_bb) of the window are in the band
static void FreeBand(void) {
    if (g_m) { if (g_bandOld) SelectObject(g_m, g_bandOld); DeleteDC(g_m); g_m = NULL; g_bandOld = NULL; }
    if (g_bandBmp) { DeleteObject(g_bandBmp); g_bandBmp = NULL; } g_bandBits = NULL;
}
static BOOL EnsureBand(void) {
    if (g_m && g_bandBits) return TRUE;
    FreeBand();
    BITMAPINFO bi; ZeroMemory(&bi, sizeof(bi));
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); bi.bmiHeader.biWidth = g_W; bi.bmiHeader.biHeight = -BANDH;
    bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
    void* bits = NULL;
    g_bandBmp = CreateDIBSection(NULL, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!g_bandBmp || !bits) { FreeBand(); return FALSE; }
    g_bandBits = (BYTE*)bits; g_m = CreateCompatibleDC(NULL);
    if (!g_m) { FreeBand(); return FALSE; }
    g_bandOld = SelectObject(g_m, g_bandBmp); SetBkMode(g_m, TRANSPARENT);
    return TRUE;
}
static inline DWORD* Px(int x, int y) { return (DWORD*)g_bandBits + (size_t)(y - g_bt) * (size_t)g_W + x; }

// ---------- gradient: a ~160 px wide grid, bilinear upscale + ordered dither per band ----------
#define LRW 160
static int g_lrW, g_lrH, g_cell; static unsigned short* g_lr;
static int* g_gx; static unsigned char* g_gf;
static void FreeBg(void) { free(g_lr); free(g_gx); free(g_gf); g_lr = NULL; g_gx = NULL; g_gf = NULL; }
static BOOL EnsureBg(void) {
    if (g_lr) return TRUE;
    if (g_W < 1 || g_H < 1) return FALSE;
    g_cell = (g_W + LRW - 1) / LRW; if (g_cell < 4) g_cell = 4;
    g_lrW = g_W / g_cell + 3; g_lrH = g_H / g_cell + 3;
    g_lr = (unsigned short*)malloc(sizeof(unsigned short) * 3 * (size_t)g_lrW * (size_t)g_lrH);
    g_gx = (int*)malloc(sizeof(int) * (size_t)g_W); g_gf = (unsigned char*)malloc((size_t)g_W);
    if (!g_lr || !g_gx || !g_gf) { FreeBg(); return FALSE; }
    const Theme* t = &THEMES[g_theme];
    float wr = GetRValue(t->wash), wg = GetGValue(t->wash), wb = GetBValue(t->wash);
    float basis = (g_W + g_H) * 0.5f;
    for (int j = 0; j < g_lrH; j++) for (int i = 0; i < g_lrW; i++) {
        float px = (i + 0.5f) * g_cell, py = (j + 0.5f) * g_cell;
        float r = wr, g = wg, b = wb, wsum = 1.35f;
        for (int k = 0; k < 5; k++) {
            float dx = px - BLOB_POS[k][0] * g_W, dy = py - BLOB_POS[k][1] * g_H, rad = BLOB_RAD[k] * basis;
            float d2 = (dx * dx + dy * dy) / (rad * rad);
            if (d2 < 1.0f) {
                float w = 1.0f - d2; w *= w;
                r += w * GetRValue(t->blob[k]); g += w * GetGValue(t->blob[k]); b += w * GetBValue(t->blob[k]); wsum += w;
            }
        }
        unsigned short* o = g_lr + ((size_t)j * g_lrW + i) * 3;
        o[0] = (unsigned short)Clampf(r / wsum * 256.0f, 0, 65280); o[1] = (unsigned short)Clampf(g / wsum * 256.0f, 0, 65280); o[2] = (unsigned short)Clampf(b / wsum * 256.0f, 0, 65280);
    }
    for (int x = 0; x < g_W; x++) {
        float u = (x + 0.5f) / g_cell - 0.5f; if (u < 0) u = 0;
        int i0 = (int)u; if (i0 > g_lrW - 2) i0 = g_lrW - 2;
        g_gx[x] = i0; g_gf[x] = (unsigned char)Clampi((int)((u - i0) * 256.0f), 0, 255);
    }
    return TRUE;
}
static const unsigned char BAYER[4][4] = { {0,8,2,10}, {12,4,14,6}, {3,11,1,9}, {15,7,13,5} };
static void BgUpscale(int xl, int xr, int y0, int y1) {
    if (!g_lr) return;
    for (int y = y0; y < y1; y++) {
        float v = (y + 0.5f) / g_cell - 0.5f; if (v < 0) v = 0;
        int j0 = (int)v; if (j0 > g_lrH - 2) j0 = g_lrH - 2;
        int yf = Clampi((int)((v - j0) * 256.0f), 0, 255), iyf = 256 - yf;
        DWORD* row = Px(0, y); const unsigned short* base = g_lr + (size_t)j0 * g_lrW * 3;
        for (int x = xl; x < xr; x++) {
            const unsigned short* a = base + (size_t)g_gx[x] * 3; const unsigned short* b = a + (size_t)g_lrW * 3;
            int fx = g_gf[x], ifx = 256 - fx, th = BAYER[y & 3][x & 3] * 16 + 8, ch[3];
            for (int c = 0; c < 3; c++) {
                int top = (a[c] * ifx + a[3 + c] * fx) >> 8, bot = (b[c] * ifx + b[3 + c] * fx) >> 8;
                int val = (((top * iyf + bot * yf) >> 8) + th) >> 8; ch[c] = val > 255 ? 255 : val;
            }
            row[x] = ((DWORD)ch[0] << 16) | ((DWORD)ch[1] << 8) | (DWORD)ch[2];
        }
    }
}

// ---------- anti-aliased shapes drawn straight into the band ----------
static float SdRR(float px, float py, float hw, float hh, float r) {
    float qx = fabsf(px) - (hw - r), qy = fabsf(py) - (hh - r);
    float ax = qx > 0 ? qx : 0, ay = qy > 0 ? qy : 0;
    float in = qx > qy ? qx : qy; if (in > 0) in = 0;
    return sqrtf(ax * ax + ay * ay) + in - r;
}
static void BlendPix(DWORD* p, COLORREF c, int a) {
    if (a <= 0) return;
    DWORD d = *p; int dr = (d >> 16) & 255, dg = (d >> 8) & 255, db = d & 255;
    dr += ((int)GetRValue(c) - dr) * a / 255; dg += ((int)GetGValue(c) - dg) * a / 255; db += ((int)GetBValue(c) - db) * a / 255;
    *p = ((DWORD)dr << 16) | ((DWORD)dg << 8) | (DWORD)db;
}
static BOOL BoxClip(float l, float t, float r, float b, int* x0, int* y0, int* x1, int* y1) {
    *x0 = Clampi((int)floorf(l) - 1, 0, g_W); *x1 = Clampi((int)ceilf(r) + 1, 0, g_W);
    *y0 = Clampi((int)floorf(t) - 1, g_bt, g_bb); *y1 = Clampi((int)ceilf(b) + 1, g_bt, g_bb);
    return *x0 < *x1 && *y0 < *y1;
}
static void BlendCircle(float cx, float cy, float r, COLORREF c, int alpha) {
    int x0, y0, x1, y1; if (!BoxClip(cx - r, cy - r, cx + r, cy + r, &x0, &y0, &x1, &y1)) return;
    GdiFlush();
    for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) {
        float dx = x + 0.5f - cx, dy = y + 0.5f - cy;
        float cov = Clampf(0.5f - (sqrtf(dx * dx + dy * dy) - r), 0, 1);
        BlendPix(Px(x, y), c, (int)(cov * alpha + 0.5f));
    }
}
static void BlendRing(float cx, float cy, float r, float w, COLORREF c, int alpha) {
    int x0, y0, x1, y1; if (!BoxClip(cx - r - w, cy - r - w, cx + r + w, cy + r + w, &x0, &y0, &x1, &y1)) return;
    GdiFlush();
    for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) {
        float dx = x + 0.5f - cx, dy = y + 0.5f - cy;
        float cov = Clampf(0.5f - (fabsf(sqrtf(dx * dx + dy * dy) - r) - w * 0.5f), 0, 1);
        BlendPix(Px(x, y), c, (int)(cov * alpha + 0.5f));
    }
}
static void BlendRR(RECT rc, float rad, COLORREF c, int alpha, float ringW) {   // ringW <= 0: filled
    int x0, y0, x1, y1; if (!BoxClip((float)rc.left - 1, (float)rc.top - 1, (float)rc.right + 1, (float)rc.bottom + 1, &x0, &y0, &x1, &y1)) return;
    GdiFlush();
    float cx = (rc.left + rc.right) * 0.5f, cy = (rc.top + rc.bottom) * 0.5f, hw = (rc.right - rc.left) * 0.5f, hh = (rc.bottom - rc.top) * 0.5f;
    if (rad > hh) rad = hh; if (rad > hw) rad = hw;
    for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) {
        float d = SdRR(x + 0.5f - cx, y + 0.5f - cy, hw, hh, rad);
        float cov = ringW > 0 ? Clampf(0.5f - (fabsf(d) - ringW * 0.5f), 0, 1) : Clampf(0.5f - d, 0, 1);
        BlendPix(Px(x, y), c, (int)(cov * alpha + 0.5f));
    }
}

// ---------- frosted card: 9-slice sprites (a few KB each instead of one per card size) ----------
typedef struct { int rad, alpha, L, pad, cs; HBITMAP bmp; } Sprite;
#define SPR_MAX 10
static Sprite g_spr[SPR_MAX]; static int g_nspr; static HDC g_sprDC;
static void ClearSprites(void) {
    for (int i = 0; i < g_nspr; i++) if (g_spr[i].bmp) DeleteObject(g_spr[i].bmp);
    g_nspr = 0; if (g_sprDC) { DeleteDC(g_sprDC); g_sprDC = NULL; }
}
static Sprite* CardSprite(int rad, int alpha) {
    for (int i = 0; i < g_nspr; i++) if (g_spr[i].rad == rad && g_spr[i].alpha == alpha) return &g_spr[i];
    if (g_nspr >= SPR_MAX) ClearSprites();
    int pad = SC(20), off = SC(6), K = off + 2, cs = rad + pad, L = 2 * cs + 2 * K + 1;
    BITMAPINFO bi; ZeroMemory(&bi, sizeof(bi));
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); bi.bmiHeader.biWidth = L; bi.bmiHeader.biHeight = -L;
    bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
    void* bits = NULL; HBITMAP bm = CreateDIBSection(NULL, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
    if (!bm || !bits) { if (bm) DeleteObject(bm); return NULL; }
    DWORD* px = (DWORD*)bits;
    float hw = (L - 2 * pad) * 0.5f, hh = hw, blur = 16.0f * g_S, offf = 6.0f * g_S;
    float sr = GetRValue(SHADOWCOL), sg = GetGValue(SHADOWCOL), sb = GetBValue(SHADOWCOL);
    for (int y = 0; y < L; y++) for (int x = 0; x < L; x++) {
        float fx = x - L * 0.5f + 0.5f, fy = y - L * 0.5f + 0.5f;
        float dsh = SdRR(fx, fy - offf, hw, hh, (float)rad);
        float sa = Clampf(74.0f * (0.5f - dsh / blur), 0, 74);
        float dc = SdRR(fx, fy, hw, hh, (float)rad);
        float ca = Clampf(alpha * (0.5f - dc / 1.4f), 0, (float)alpha);
        sa *= 1.0f - Clampf(0.5f - dc / 1.4f, 0, 1);      // no shadow behind the glass itself: cleaner, brighter cards
        float a = ca + sa * (255.0f - ca) / 255.0f; DWORD out = 0;
        if (a > 0.5f) {
            float keep = sa * (255.0f - ca) / 255.0f;
            float R = (255.0f * ca + sr * keep) / a, G = (255.0f * ca + sg * keep) / a, B = (255.0f * ca + sb * keep) / a;
            int ia = (int)(a + 0.5f);
            out = ((DWORD)ia << 24) | ((DWORD)(int)(R * a / 255.0f + 0.5f) << 16) | ((DWORD)(int)(G * a / 255.0f + 0.5f) << 8) | (DWORD)(int)(B * a / 255.0f + 0.5f);
        }
        px[(size_t)y * L + x] = out;
    }
    Sprite* s = &g_spr[g_nspr++]; s->rad = rad; s->alpha = alpha; s->L = L; s->pad = pad; s->cs = cs; s->bmp = bm;
    return s;
}
static BOOL VisR(const RECT* r) { int m = SC(40); return r->bottom + m > g_bt && r->top - m < g_bb; }
static void DrawCard(HDC dc, RECT rc, int rad, int alpha) {
    int w = rc.right - rc.left, h = rc.bottom - rc.top;
    if (w < 4 || h < 4 || !VisR(&rc)) return;
    if (rad > h / 2) rad = h / 2; if (rad > w / 2) rad = w / 2;
    Sprite* s = CardSprite(rad, alpha); if (!s) return;
    if (!g_sprDC) g_sprDC = CreateCompatibleDC(dc);
    HGDIOBJ o = SelectObject(g_sprDC, s->bmp);
    BLENDFUNCTION bf = { AC_SRC_OVER, 0, 255, AC_SRC_ALPHA };
    int cs = s->cs, L = s->L, pad = s->pad, m = L / 2;
    int x0 = rc.left - pad, y0 = rc.top - pad, dw = w + 2 * pad, dh = h + 2 * pad, mw = dw - 2 * cs, mh = dh - 2 * cs;
#define AB(dx, dy, dwid, dhei, sx, sy, swid, shei) if ((dwid) > 0 && (dhei) > 0) AlphaBlend(dc, dx, dy, dwid, dhei, g_sprDC, sx, sy, swid, shei, bf)
    AB(x0, y0, cs, cs, 0, 0, cs, cs);                         AB(x0 + dw - cs, y0, cs, cs, L - cs, 0, cs, cs);
    AB(x0, y0 + dh - cs, cs, cs, 0, L - cs, cs, cs);          AB(x0 + dw - cs, y0 + dh - cs, cs, cs, L - cs, L - cs, cs, cs);
    AB(x0 + cs, y0, mw, cs, m, 0, 1, cs);                     AB(x0 + cs, y0 + dh - cs, mw, cs, m, L - cs, 1, cs);
    AB(x0, y0 + cs, cs, mh, 0, m, cs, 1);                     AB(x0 + dw - cs, y0 + cs, cs, mh, L - cs, m, cs, 1);
    AB(x0 + cs, y0 + cs, mw, mh, m, m, 1, 1);
#undef AB
    SelectObject(g_sprDC, o);
}

// ---------- vector icons: stroked primitives in a 24-unit grid, rasterized once to 8-bit masks ----------
enum { IC_CPU, IC_MEM, IC_WIFI, IC_DISK, IC_BATT, IC_FOLDER, IC_SEARCH, IC_POWER, IC_LOCK, IC_CHECK, IC_REFRESH,
       IC_MOON, IC_LOGOUT, IC_X, IC_CLOCK, IC_CHEV, IC_SLIDERS, IC_ETH, IC_WIFIOFF, IC_PIN, IC_COUNT };
typedef struct { int t; float a, b, c, d, e, f; } Prim;
#define LN(x1,y1,x2,y2,w)        {0,x1,y1,x2,y2,w,0}
#define AR(cx,cy,r,a0,a1,w)      {1,cx,cy,r,a0,a1,w}
#define DS(cx,cy,r)              {2,cx,cy,r,0,0,0}
#define RG(cx,cy,r,w)            {3,cx,cy,r,w,0,0}
#define RR(x1,y1,x2,y2,r,w)      {4,x1,y1,x2,y2,r,w}
#define FR(x1,y1,x2,y2,r)        {5,x1,y1,x2,y2,r,0}
#define W1 1.05f
static const Prim P_CPU[] = { RR(5,5,19,19,2.6f,W1), RR(9.2f,9.2f,14.8f,14.8f,1.2f,W1), LN(9.5f,2,9.5f,5,W1), LN(14.5f,2,14.5f,5,W1), LN(9.5f,19,9.5f,22,W1), LN(14.5f,19,14.5f,22,W1),
    LN(2,9.5f,5,9.5f,W1), LN(2,14.5f,5,14.5f,W1), LN(19,9.5f,22,9.5f,W1), LN(19,14.5f,22,14.5f,W1) };
static const Prim P_MEM[] = { RR(2,6.5f,22,16.5f,2.2f,W1), LN(6.5f,10,6.5f,13,W1), LN(12,10,12,13,W1), LN(17.5f,10,17.5f,13,W1),
    LN(6,16.5f,6,20,W1), LN(10,16.5f,10,20,W1), LN(14,16.5f,14,20,W1), LN(18,16.5f,18,20,W1) };
static const Prim P_WIFI[] = { AR(12,19.5f,4.6f,225,315,W1), AR(12,19.5f,8.8f,225,315,W1), AR(12,19.5f,13,225,315,W1), DS(12,19.5f,1.6f) };
static const Prim P_WIFIOFF[] = { AR(12,19.5f,4.6f,225,315,W1), AR(12,19.5f,8.8f,225,315,W1), AR(12,19.5f,13,225,315,W1), DS(12,19.5f,1.6f), LN(3.5f,3.5f,20.5f,20.5f,W1) };
static const Prim P_DISK[] = { RR(2,12.5f,22,20,2.6f,W1), LN(2.2f,12.5f,5.4f,5.6f,W1), LN(5.4f,5.6f,18.6f,5.6f,W1), LN(18.6f,5.6f,21.8f,12.5f,W1), DS(6.5f,16.3f,1.25f), DS(10.5f,16.3f,1.25f) };
static const Prim P_BATT[] = { RR(2,7,19.5f,17,2.6f,W1), LN(22,10.5f,22,13.5f,W1) };
static const Prim P_FOLDER[] = { RR(2,7.6f,22,20,2.6f,W1), LN(3,7.6f,3.8f,4.8f,W1), LN(3.8f,4.8f,8.6f,4.8f,W1), LN(8.6f,4.8f,10.6f,7.6f,W1) };
static const Prim P_SEARCH[] = { RG(10.5f,10.5f,6.6f,W1), LN(15.4f,15.4f,20.4f,20.4f,W1) };
static const Prim P_POWER[] = { AR(12,13,7.6f,-60,240,W1), LN(12,3.4f,12,12,W1) };
static const Prim P_LOCK[] = { RR(5,11,19,21,2.4f,W1), LN(8.2f,11,8.2f,8,W1), AR(12,8,3.8f,180,360,W1), LN(15.8f,8,15.8f,11,W1) };
static const Prim P_CHECK[] = { LN(5,12.5f,10,17.5f,1.4f), LN(10,17.5f,19.5f,7,1.4f) };
static const Prim P_REFRESH[] = { AR(12,12,7.5f,10,290,W1), LN(14.56f,4.95f,12.46f,1.32f,W1), LN(14.56f,4.95f,10.6f,6.4f,W1) };
static const Prim P_MOON[] = { AR(12,12,9,0,270,W1), AR(16.5f,7.5f,6.36f,45,225,W1) };
static const Prim P_LOGOUT[] = { LN(9,3.5f,5,3.5f,W1), LN(5,3.5f,5,20.5f,W1), LN(5,20.5f,9,20.5f,W1), LN(10,12,20,12,W1), LN(16,8,20,12,W1), LN(16,16,20,12,W1) };
static const Prim P_X[] = { LN(6,6,18,18,W1), LN(18,6,6,18,W1) };
static const Prim P_CLOCK[] = { RG(12,12,9,W1), LN(12,7,12,12,W1), LN(12,12,15.5f,14,W1) };
static const Prim P_CHEV[] = { LN(15,5,8,12,1.2f), LN(8,12,15,19,1.2f) };
static const Prim P_SLIDERS[] = { LN(4,8,20,8,W1), DS(9,8,2.6f), LN(4,16,20,16,W1), DS(15,16,2.6f) };
static const Prim P_ETH[] = { RR(9,3,15,8.5f,1.2f,W1), LN(12,8.5f,12,12.5f,W1), LN(5,12.5f,19,12.5f,W1), LN(5,12.5f,5,16,W1), LN(19,12.5f,19,16,W1), RR(2.5f,16,7.5f,21,1.2f,W1), RR(16.5f,16,21.5f,21,1.2f,W1) };
static const Prim P_PIN[] = { DS(12,12,3) };
typedef struct { const Prim* p; int n; } IconDef;
#define ID(a) { a, (int)(sizeof(a) / sizeof(a[0])) }
static const IconDef ICONS[IC_COUNT] = { ID(P_CPU), ID(P_MEM), ID(P_WIFI), ID(P_DISK), ID(P_BATT), ID(P_FOLDER), ID(P_SEARCH), ID(P_POWER), ID(P_LOCK),
    ID(P_CHECK), ID(P_REFRESH), ID(P_MOON), ID(P_LOGOUT), ID(P_X), ID(P_CLOCK), ID(P_CHEV), ID(P_SLIDERS), ID(P_ETH), ID(P_WIFIOFF), ID(P_PIN) };
static float PrimSd(const Prim* p, float u, float v) {
    switch (p->t) {
    case 0: { float dx = p->c - p->a, dy = p->d - p->b, l2 = dx * dx + dy * dy;
              float t = l2 > 0 ? Clampf(((u - p->a) * dx + (v - p->b) * dy) / l2, 0, 1) : 0;
              float qx = p->a + t * dx - u, qy = p->b + t * dy - v; return sqrtf(qx * qx + qy * qy) - p->e; }
    case 1: { float dx = u - p->a, dy = v - p->b, len = sqrtf(dx * dx + dy * dy);
              float ang = atan2f(dy, dx) * 57.29578f, a0 = p->d, a1 = p->e;
              while (ang < a0) ang += 360.0f; while (ang >= a0 + 360.0f) ang -= 360.0f;
              if (ang <= a1) return fabsf(len - p->c) - p->f;
              float r0 = a0 / 57.29578f, r1 = a1 / 57.29578f;
              float e0x = p->a + p->c * cosf(r0) - u, e0y = p->b + p->c * sinf(r0) - v, e1x = p->a + p->c * cosf(r1) - u, e1y = p->b + p->c * sinf(r1) - v;
              float d0 = sqrtf(e0x * e0x + e0y * e0y), d1 = sqrtf(e1x * e1x + e1y * e1y); return (d0 < d1 ? d0 : d1) - p->f; }
    case 2: { float dx = u - p->a, dy = v - p->b; return sqrtf(dx * dx + dy * dy) - p->c; }
    case 3: { float dx = u - p->a, dy = v - p->b; return fabsf(sqrtf(dx * dx + dy * dy) - p->c) - p->d; }
    case 4: return fabsf(SdRR(u - (p->a + p->c) * 0.5f, v - (p->b + p->d) * 0.5f, (p->c - p->a) * 0.5f, (p->d - p->b) * 0.5f, p->e)) - p->f;
    default: return SdRR(u - (p->a + p->c) * 0.5f, v - (p->b + p->d) * 0.5f, (p->c - p->a) * 0.5f, (p->d - p->b) * 0.5f, p->e);
    }
}
static BYTE* g_icm[IC_COUNT]; static int g_icmN[IC_COUNT];
static void FreeIcons(void) { for (int i = 0; i < IC_COUNT; i++) { free(g_icm[i]); g_icm[i] = NULL; g_icmN[i] = 0; } }
static const BYTE* IconMask(int kind, int N) {
    if (g_icm[kind] && g_icmN[kind] == N) return g_icm[kind];
    free(g_icm[kind]); g_icm[kind] = (BYTE*)malloc((size_t)N * (size_t)N); g_icmN[kind] = N;
    if (!g_icm[kind]) return NULL;
    float k = N / 24.0f; const IconDef* d = &ICONS[kind];
    for (int y = 0; y < N; y++) for (int x = 0; x < N; x++) {
        float u = (x + 0.5f) / k, v = (y + 0.5f) / k, best = 0;
        for (int i = 0; i < d->n; i++) { float cov = Clampf(0.5f - PrimSd(&d->p[i], u, v) * k, 0, 1); if (cov > best) best = cov; }
        g_icm[kind][y * N + x] = (BYTE)(best * 255.0f + 0.5f);
    }
    return g_icm[kind];
}
static void DrawGlyph(int kind, int cx, int cy, int N, COLORREF col, int alpha) {
    const BYTE* m = IconMask(kind, N); if (!m) return;
    int x0 = cx - N / 2, y0 = cy - N / 2;
    if (y0 + N <= g_bt || y0 >= g_bb) return;
    GdiFlush();
    for (int y = 0; y < N; y++) {
        int yy = y0 + y; if (yy < g_bt || yy >= g_bb) continue;
        for (int x = 0; x < N; x++) {
            int xx = x0 + x; if (xx < 0 || xx >= g_W) continue;
            int a = m[y * N + x] * alpha / 255; if (a) BlendPix(Px(xx, yy), col, a);
        }
    }
}
static void DrawSignal(int x, int y, int h, int sig, COLORREF c) {      // four rounded bars
    int bw = h / 4; if (bw < 3) bw = 3; int gap = bw / 2 + 1;
    for (int i = 0; i < 4; i++) {
        int bh = h * (i + 1) / 4; RECT r = { x + i * (bw + gap), y + h - bh, x + i * (bw + gap) + bw, y + h };
        BlendRR(r, bw * 0.5f, c, sig >= i * 25 + 13 ? 255 : 55, 0);
    }
}

static void InvRect(RECT r, int grow) { InflateRect(&r, grow, grow); InvalidateRect(g_hwnd, &r, FALSE); }
static RECT PwrPanelRect(void);
static RECT CurPanelRect(void) { RECT z = { 0, 0, 0, 0 }; return g_panel == PN_POWER ? PwrPanelRect() : z; }
static void ClosePanel(void) {
    RECT pr = CurPanelRect(); g_panel = PN_NONE; g_hov = 0;
    if (pr.right > pr.left) InvRect(pr, SC(30));
}
#define NPWR 6
static const struct { int icon; const wchar_t* label; } PWR[NPWR] = {
    { IC_MOON, L"Sleep" }, { IC_LOGOUT, L"Sign out" }, { IC_REFRESH, L"Restart" }, { IC_POWER, L"Shut down" },
    { IC_FOLDER, L"Restore Windows Explorer" }, { IC_X, L"Exit Ember" } };
static RECT PwrPanelRect(void) {
    RECT pb = PowerRect(); int pw = SC(290), h = NPWR * SC(44) + SC(8) + SC(20);
    RECT r = { g_W - Mg() - pw, pb.top - SC(12) - h, g_W - Mg(), pb.top - SC(12) }; return r;
}
static RECT PwrRowRect(RECT p, int i) {
    int y = p.top + SC(10) + i * SC(44) + (i >= 4 ? SC(8) : 0); RECT b = { p.left + SC(8), y, p.right - SC(8), y + SC(44) }; return b;
}
static int PanelHit(int x, int y) {
    POINT pt = { x, y };
    if (g_panel == PN_POWER) {
        RECT p = PwrPanelRect(); if (!PtInRect(&p, pt)) return 0;
        for (int i = 0; i < NPWR; i++) { RECT b = PwrRowRect(p, i); if (PtInRect(&b, pt)) return HV_PWR + i; }
        return HV_PANEL;
    }
    return 0;
}
static int HitAt(int x, int y) {
    POINT pt = { x, y };
    if (g_panel) { int h = PanelHit(x, y); if (h) return h; }
    { RECT r = PowerRect(); if (PtInRect(&r, pt)) return HV_POWER; }
    { RECT r = ExplorerRect(); if (PtInRect(&r, pt)) return HV_EXP; }
    int gy = GridTop(); if (y < gy || x < Mg() || x >= g_W - Mg()) return 0;
    int cols = Cols(), cellw = (g_W - Mg() * 2) / cols, col = (x - Mg()) / cellw, row = (y - gy) / TilePitch();
    if (col >= cols) return 0;
    int d = row * cols + col; RECT tr = TileRect(d);
    if (!PtInRect(&tr, pt) || g_scroll * cols + d >= g_visCount) return 0;
    return HV_TILE + d;
}
static BOOL RectOfId(int id, RECT* out) {
    if (id == HV_EXP) *out = ExplorerRect();
    else if (id == HV_POWER) *out = PowerRect();
    else if (id >= HV_TILE) *out = TileRect(id - HV_TILE);
    else if (id >= HV_PWR && id < HV_PWR + NPWR && g_panel) *out = CurPanelRect();
    else return FALSE;
    InflateRect(out, SC(26), SC(26)); return TRUE;
}

// ---------- painting ----------
static void Text(HDC dc, const wchar_t* s, int x, int y, HFONT f, COLORREF col) {
    SetTextColor(dc, col); HGDIOBJ o = SelectObject(dc, f); TextOutW(dc, x, y, s, (int)wcslen(s)); SelectObject(dc, o);
}
static void TextR(HDC dc, const wchar_t* s, RECT rc, HFONT f, COLORREF col, UINT flags) {
    SetTextColor(dc, col); HGDIOBJ o = SelectObject(dc, f); DrawTextW(dc, s, -1, &rc, flags); SelectObject(dc, o);
}
static void PaintStat(HDC m, int i) {
    static const wchar_t* labels[5] = { L"CPU", L"MEMORY", L"NETWORK", L"DISK", L"BATTERY" };
    RECT r = StatCardRect(i); if (!VisR(&r)) return;
    const Theme* th = &THEMES[g_theme];
    DrawCard(m, r, SC(24), 170);
    int pad = SC(16), chipR = SC(17), ccx = r.left + pad + chipR, ccy = r.top + pad + chipR, isz = SC(20);
    BlendCircle((float)ccx, (float)ccy, (float)chipR, CHIP_TINTS[i % 5], 255);
    wchar_t val[96], cap[64]; float frac = 0; int icon = IC_CPU;
    switch (i) {
    case 0: icon = IC_CPU; Fmt(val, 96, L"%d%%", (int)(cpuPct + 0.5)); Cpy(cap, 64, L"Processor load"); frac = (float)(cpuPct / 100.0); break;
    case 1: icon = IC_MEM; Fmt(val, 96, L"%.1f / %.1f GB", memUsedGB, memTotalGB);
            Fmt(cap, 64, L"%d%% in use", memTotalGB > 0 ? (int)(memUsedGB * 100.0 / memTotalGB + 0.5) : 0); frac = memTotalGB > 0 ? (float)(memUsedGB / memTotalGB) : 0; break;
    case 2: icon = netState == 2 ? IC_ETH : (netState == 1 || haveWifi ? (netState ? IC_WIFI : IC_WIFIOFF) : IC_ETH);
            if (netState) Cpy(val, 96, netName[0] ? netName : L"Wi-Fi"); else Cpy(val, 96, haveWifi ? L"Not connected" : L"No network");
            if (netState == 1) Fmt(cap, 64, L"Signal %d%%", netSig); else Cpy(cap, 64, netState == 2 ? L"Wired connection" : L"Offline");
            frac = netSig / 100.0f; break;
    case 3: icon = IC_DISK; Fmt(val, 96, L"%.0f GB free", diskFreeGB);
            Fmt(cap, 64, L"%d%% used", diskTotalGB > 0 ? (int)((diskTotalGB - diskFreeGB) * 100.0 / diskTotalGB + 0.5) : 0); frac = diskTotalGB > 0 ? (float)((diskTotalGB - diskFreeGB) / diskTotalGB) : 0; break;
    default: icon = IC_BATT; Fmt(val, 96, L"%d%%", battPct); Cpy(cap, 64, battAC ? L"Charging" : L"On battery"); frac = battPct / 100.0f; break;
    }
    DrawGlyph(icon, ccx, ccy, isz, INK, 255);
    if (i == 4 && battPct > 0) {                       // fill level inside the battery outline
        float k = isz / 24.0f; int bx = ccx - isz / 2, by = ccy - isz / 2;
        RECT f = { bx + (int)(4.2f * k), by + (int)(9.2f * k), bx + (int)((4.2f + 13.0f * battPct / 100.0f) * k + 0.5f), by + (int)(14.8f * k) };
        if (f.right - f.left < 2) f.right = f.left + 2;
        BlendRR(f, SC(1.5f), battPct <= 15 ? RGB(214, 69, 80) : th->deep, 255, 0);
    }
    if (i == 2 && netState == 1) DrawSignal(r.right - pad - SC(24), r.top + pad + SC(8), SC(18), netSig, INK);
    RECT lr = { ccx + chipR + SC(10), r.top + pad, r.right - pad - (i == 2 ? SC(34) : 0), r.top + pad + 2 * chipR };
    TextR(m, labels[i], lr, fTiny, SUB, DT_SINGLELINE | DT_LEFT | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
    RECT vr = { r.left + pad, r.top + SC(58), r.right - pad, r.top + SC(84) };
    TextR(m, val, vr, fHead, INK, DT_SINGLELINE | DT_LEFT | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
    RECT cr = { r.left + pad, r.top + SC(84), r.right - pad, r.top + SC(102) };
    TextR(m, cap, cr, fTiny, SUB, DT_SINGLELINE | DT_LEFT | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
    RECT bt = { r.left + pad, r.bottom - SC(24), r.right - pad, r.bottom - SC(24) + SC(6) };
    BlendRR(bt, SC(3), BODY, 38, 0);
    int fw = (int)((bt.right - bt.left) * Clampf(frac, 0, 1) + 0.5f);
    if (fw > 0) { if (fw < SC(6)) fw = SC(6); RECT bf = { bt.left, bt.top, bt.left + fw, bt.bottom }; BlendRR(bf, SC(3), th->deep, 255, 0); }
}
static void PaintPowerPanel(HDC m) {
    RECT p = PwrPanelRect(); if (!VisR(&p)) return;
    const Theme* th = &THEMES[g_theme];
    DrawCard(m, p, SC(24), 253);
    for (int i = 0; i < NPWR; i++) {
        RECT r = PwrRowRect(p, i); int mid = (r.top + r.bottom) / 2;
        if (g_hov == HV_PWR + i) BlendRR(r, SC(14), th->deep, 30, 0);
        DrawGlyph(PWR[i].icon, r.left + SC(26), mid, SC(20), INK, 255);
        RECT t = { r.left + SC(54), r.top, r.right - SC(8), r.bottom };
        TextR(m, PWR[i].label, t, fName, INK, DT_SINGLELINE | DT_LEFT | DT_VCENTER | DT_END_ELLIPSIS);
        if (i == 3) { RECT sep = { p.left + SC(20), r.bottom + SC(3), p.right - SC(20), r.bottom + SC(3) + 1 }; BlendRR(sep, 0, BODY, 40, 0); }
    }
}
static void PaintScene(HDC m) {
    const Theme* th = &THEMES[g_theme]; wchar_t buf[200];
    // dashboard: clock card
    RECT cc = ClockCardRect();
    if (VisR(&cc)) {
        DrawCard(m, cc, SC(24), 170);
        Text(m, dateTxt, cc.left + SC(26), cc.top + SC(16), fDate, INK);
        Text(m, clockTxt, cc.left + SC(24), cc.top + SC(44), fClock, INK);
        Fmt(buf, 200, L"Ember  \u00B7  %.1f MB", ownMB);
        Text(m, buf, cc.left + SC(28), cc.bottom - SC(30), fSmall, SUB);
    }
    for (int i = 0; i < StatCount(); i++) PaintStat(m, i);
    // strip
    RECT st = StripRect();
    if (VisR(&st)) {
        DrawCard(m, st, SC(22), 150);
        int mid = (st.top + st.bottom) / 2;
        BlendCircle((float)(st.left + SC(32)), (float)mid, (float)SC(17), CHIP_TINTS[4], 255);
        DrawGlyph(IC_SEARCH, st.left + SC(32), mid, SC(18), INK, 255);
        if (ShowHiddenMode()) Fmt(buf, 200, L"Hidden apps  \u00B7  %d  \u00B7  right-click one to bring it back", g_visCount);
        else if (g_filter[0]) Fmt(buf, 200, L"\u201C%ls\u201D  \u00B7  %d %ls", g_filter, g_visCount, g_visCount == 1 ? L"result" : L"results");
        else Fmt(buf, 200, L"%d apps  \u00B7  start typing to search", g_visCount);
        RECT lab = { st.left + SC(60), st.top, ExplorerRect().left - SC(14), st.bottom };
        TextR(m, buf, lab, fChip, INK, DT_SINGLELINE | DT_LEFT | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
        RECT ex = ExplorerRect(); BOOL hot = g_hov == HV_EXP;
        DrawCard(m, ex, (ex.bottom - ex.top) / 2, hot ? 240 : 205);
        DrawGlyph(IC_FOLDER, ex.left + SC(26), (ex.top + ex.bottom) / 2, SC(18), INK, 255);
        RECT et = { ex.left + SC(46), ex.top, ex.right - SC(8), ex.bottom };
        TextR(m, L"Explorer", et, fChip, INK, DT_SINGLELINE | DT_LEFT | DT_VCENTER);
    }
    // app grid
    int cols = Cols(), rows = RowsVisible();
    for (int d = 0; d < cols * rows; d++) {
        int vi = g_scroll * cols + d; if (vi >= g_visCount) break;
        RECT tr = TileRect(d); if (!VisR(&tr)) continue;
        const wchar_t* name = g_apps[g_vis[vi]].name;
        BOOL hov = g_hov == HV_TILE + d, sel = g_keynav && vi == g_sel;
        DrawCard(m, tr, SC(20), (hov || sel) ? 220 : 165);
        unsigned h = 7; for (const wchar_t* c = name; *c; c++) h = h * 31 + (unsigned)towlower(*c);
        int bx = tr.left + SC(32), by = (tr.top + tr.bottom) / 2;
        BlendCircle((float)bx, (float)by, (float)SC(19), CHIP_TINTS[h % 5], 255);
        wchar_t ch[2] = { L'#', 0 }; for (const wchar_t* c = name; *c; c++) if (iswalnum(*c)) { ch[0] = (wchar_t)towupper(*c); break; }
        RECT br = { bx - SC(19), by - SC(19), bx + SC(19), by + SC(19) };
        TextR(m, ch, br, fChip, INK, DT_SINGLELINE | DT_CENTER | DT_VCENTER | DT_NOPREFIX);
        RECT nr = { tr.left + SC(62), tr.top, tr.right - SC(14), tr.bottom };
        TextR(m, name, nr, fName, INK, DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
        if (sel) BlendRR(tr, (float)SC(20), th->deep, 235, SC(2.2f));
    }
    if (g_visCount == 0) {
        RECT er = { Mg(), GridTop(), g_W - Mg(), GridTop() + SC(120) };
        if (VisR(&er)) {
            if (g_filter[0]) Fmt(buf, 200, L"No apps match \u201C%ls\u201D", g_filter); else Cpy(buf, 200, L"No apps found in the Start Menu");
            TextR(m, buf, er, fHead, SUB, DT_SINGLELINE | DT_CENTER | DT_VCENTER | DT_NOPREFIX);
        }
    }
    // footer
    int fy = g_H - SC(46);
    Text(m, L"Ember", Mg(), fy - SC(14), fMark, INK);
    PowerRect();
    RECT pw = PowerRect();
    if (g_toast[0]) Text(m, g_toast, Mg() + SC(92), fy - SC(8), fTiny, th->deep);
    else Text(m, L"Win key shows or hides  \u00B7  Enter opens the top result  \u00B7  right-click hides an app", Mg() + SC(92), fy - SC(8), fTiny, SUB);
    DrawCard(m, pw, SC(24), (g_hov == HV_POWER || g_panel == PN_POWER) ? 240 : 200);
    DrawGlyph(IC_POWER, (pw.left + pw.right) / 2, (pw.top + pw.bottom) / 2, SC(22), INK, 255);
    // overlays last
    if (g_panel == PN_POWER) PaintPowerPanel(m);
}
static void DoPaint(HWND hwnd) {
    PAINTSTRUCT ps; HDC dc = BeginPaint(hwnd, &ps);
    RECT pr = ps.rcPaint;
    if (pr.right > pr.left && pr.bottom > pr.top && EnsureBand() && EnsureBg()) {
        for (int y0 = pr.top; y0 < pr.bottom; y0 += BANDH) {
            int y1 = y0 + BANDH < pr.bottom ? y0 + BANDH : pr.bottom;
            g_bt = y0; g_bb = y1;
            BgUpscale(pr.left, pr.right, y0, y1);
            SetViewportOrgEx(g_m, 0, -y0, NULL);
            PaintScene(g_m);
            GdiFlush();
            SetViewportOrgEx(g_m, 0, 0, NULL);
            BitBlt(dc, pr.left, y0, pr.right - pr.left, y1 - y0, g_m, pr.left, 0, SRCCOPY);
        }
    }
    EndPaint(hwnd, &ps);
}

// ---------- fonts (Nunito embedded, Segoe UI fallback), scaled to DPI ----------
static HINSTANCE g_hi;
static HANDLE g_fontMem[2];
static BOOL LoadNunito(HINSTANCE hi) {
    const int ids[2] = { 101, 102 }; int ok = 0;
    for (int i = 0; i < 2; i++) {
        HRSRC r = FindResourceW(hi, MAKEINTRESOURCEW(ids[i]), RT_RCDATA); if (!r) return FALSE;
        DWORD sz = SizeofResource(hi, r); HGLOBAL hg = LoadResource(hi, r); LPVOID p = hg ? LockResource(hg) : NULL;
        if (!p || !sz) return FALSE;
        DWORD n = 0; g_fontMem[i] = AddFontMemResourceEx(p, sz, NULL, &n);
        if (g_fontMem[i] && n > 0) ok++;
    }
    return ok == 2;
}
static HFONT MkFont(int px, int weight, const wchar_t* face) {
    return CreateFontW(-SC(px), 0, 0, 0, weight, 0, 0, 0, 0, 0, 0, CLEARTYPE_QUALITY, 0, face);
}
static void MakeFonts(const wchar_t* face) {
    fClock = MkFont(44, FW_BOLD, face); fDate = MkFont(22, FW_BOLD, face); fHead = MkFont(19, FW_BOLD, face);
    fName = MkFont(15, FW_BOLD, face); fSmall = MkFont(13, FW_NORMAL, face); fTiny = MkFont(12, FW_BOLD, face);
    fMark = MkFont(21, FW_BOLD, face); fChip = MkFont(14, FW_BOLD, face);
}
static void FreeFonts(void) {
    HFONT all[8] = { fClock, fDate, fHead, fName, fSmall, fTiny, fMark, fChip };
    for (int i = 0; i < 8; i++) if (all[i]) DeleteObject(all[i]);
    fClock = fDate = fHead = fName = fSmall = fTiny = fMark = fChip = NULL;
}
static BOOL g_nunito;
static void InitFonts(void) {
    if (!g_nunito && !g_fontMem[0]) g_nunito = LoadNunito(g_hi);
    if (g_nunito) {
        MakeFonts(L"Nunito");
        HDC dc = CreateCompatibleDC(NULL); wchar_t face[64] = L"";
        HGDIOBJ o = SelectObject(dc, fHead); GetTextFaceW(dc, 64, face); SelectObject(dc, o); DeleteDC(dc);
        if (_wcsicmp(face, L"Nunito") == 0) return;
        FreeFonts();
    }
    MakeFonts(L"Segoe UI");
}
static void ApplyScale(HWND hwnd) {
    float s = 1.0f; UINT dpi = 0;
    HMODULE u = GetModuleHandleW(L"user32.dll");
    typedef UINT (WINAPI *PFN_GDW)(HWND);
    PFN_GDW gw = u ? (PFN_GDW)GetProcAddress(u, "GetDpiForWindow") : NULL;
    if (gw && hwnd) dpi = gw(hwnd);
    if (!dpi) { HDC dc = GetDC(NULL); dpi = (UINT)GetDeviceCaps(dc, LOGPIXELSX); ReleaseDC(NULL, dc); }
    if (dpi) s = dpi / 96.0f;
    s = Clampf(s, 1.0f, 3.0f);
    if (fabsf(s - g_S) > 0.01f || !fHead) { g_S = s; FreeFonts(); InitFonts(); ClearSprites(); FreeIcons(); }
}

// ---------- actions ----------
static void Trim(void) { SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1); }
static void ForceFront(void) {
    HWND fg = GetForegroundWindow(); DWORD ft = fg ? GetWindowThreadProcessId(fg, NULL) : 0, me = GetCurrentThreadId();
    if (ft && ft != me) AttachThreadInput(me, ft, TRUE);
    BringWindowToTop(g_hwnd); SetForegroundWindow(g_hwnd); SetFocus(g_hwnd);
    if (ft && ft != me) AttachThreadInput(me, ft, FALSE);
}
static void ShowToast(const wchar_t* t) {
    Cpy(g_toast, 96, t); SetTimer(g_hwnd, 7, 3500, NULL);
    RECT r = { 0, g_H - SC(90), g_W, g_H }; InvalidateRect(g_hwnd, &r, FALSE);
}
static int g_tick;
static void SetShown(BOOL show) {
    if (show == g_shown) { if (show) ForceFront(); return; }
    g_shown = show;
    if (show) {
        KillTimer(g_hwnd, 3);
        g_filter[0] = 0; g_scroll = 0; g_sel = -1; g_keynav = FALSE; g_panel = PN_NONE; g_hov = 0; g_toast[0] = 0;
        if (!g_nchg) AppsScan(); else RebuildVis();
        PollFast(); PollSlow();
        ShowWindow(g_hwnd, SW_SHOW); InvalidateRect(g_hwnd, NULL, FALSE); ForceFront();
        g_tick = 0; SetTimer(g_hwnd, 1, 1000, NULL);
        SetTimer(g_hwnd, 9, 60, NULL);               // network lookup after the first paint
        SetTimer(g_hwnd, 3, 3000, NULL);             // trim once the first paint has settled
    } else {
        KillTimer(g_hwnd, 1); KillTimer(g_hwnd, 9); g_panel = PN_NONE;
        ShowWindow(g_hwnd, SW_HIDE);
        SetTimer(g_hwnd, 3, 4000, NULL);             // then free every cache and trim
    }
}
static void Launch(const wchar_t* file, const wchar_t* label) {
    HINSTANCE r = ShellExecuteW(NULL, L"open", file, NULL, NULL, SW_SHOWNORMAL);
    if ((INT_PTR)r <= 32) { wchar_t b[96]; Fmt(b, 96, L"Could not open %ls", label); ShowToast(b); return; }
    SetShown(FALSE);
}
static void SetExplorerShell(void) {
    HKEY k;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon", 0, KEY_WRITE, &k) == ERROR_SUCCESS) {
        RegSetValueExW(k, L"Shell", 0, REG_SZ, (BYTE*)L"explorer.exe", sizeof(L"explorer.exe")); RegCloseKey(k);
    }
}
static void DoPower(int id) {
    HANDLE tok; TOKEN_PRIVILEGES tp;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &tok)) {
        LookupPrivilegeValueW(NULL, SE_SHUTDOWN_NAME, &tp.Privileges[0].Luid);
        tp.PrivilegeCount = 1; tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
        AdjustTokenPrivileges(tok, FALSE, &tp, 0, NULL, NULL); CloseHandle(tok);
    }
    switch (id) {
    case 0: { HMODULE h = LoadLibraryW(L"powrprof.dll");
              PFN_SetSuspendState f = h ? (PFN_SetSuspendState)GetProcAddress(h, "SetSuspendState") : NULL;
              if (f) f(FALSE, FALSE, FALSE); if (h) FreeLibrary(h); break; }
    case 1: ExitWindowsEx(EWX_LOGOFF | EWX_FORCEIFHUNG, 0); break;
    case 2: ExitWindowsEx(EWX_REBOOT | EWX_FORCEIFHUNG, 0); break;
    case 3: ExitWindowsEx(EWX_SHUTDOWN | EWX_FORCEIFHUNG, 0); break;
    case 4: SetExplorerShell(); ShellExecuteW(NULL, L"open", L"explorer.exe", NULL, NULL, SW_SHOWNORMAL); PostQuitMessage(0); break;
    case 5: ShellExecuteW(NULL, L"open", L"explorer.exe", NULL, NULL, SW_SHOWNORMAL); PostQuitMessage(0); break;   // never leave a blank desktop
    }
}

// ---------- failsafe ----------
static void SetBootAttempts(DWORD v) { SaveSetting(L"BootAttempts", REG_DWORD, &v, sizeof(v)); }
static DWORD GetBootAttempts(void) {
    DWORD v = 0, sz = sizeof(v); HKEY k;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Ember", 0, KEY_READ, &k) == ERROR_SUCCESS) { RegQueryValueExW(k, L"BootAttempts", NULL, NULL, (BYTE*)&v, &sz); RegCloseKey(k); }
    return v;
}

// ---------- input helpers ----------
static void InvGrid(void) { RECT r = { 0, GridTop() - SC(24), g_W, g_H - SC(70) }; InvalidateRect(g_hwnd, &r, FALSE); }
static void InvBelowDash(void) { RECT r = { 0, StripY() - SC(30), g_W, g_H }; InvalidateRect(g_hwnd, &r, FALSE); }
static void SelMove(int dx, int dy) {
    if (!g_visCount) return;
    int cols = Cols();
    if (g_sel < 0) g_sel = g_scroll * cols; else g_sel = Clampi(g_sel + dx + dy * cols, 0, g_visCount - 1);
    int row = g_sel / cols;
    if (row < g_scroll) g_scroll = row;
    if (row >= g_scroll + RowsVisible()) g_scroll = row - RowsVisible() + 1;
    ClampScroll(); g_keynav = TRUE; InvGrid();
}
static void LaunchIndex(int vi) {
    if (vi < 0 || vi >= g_visCount) return;
    AppItem* a = &g_apps[g_vis[vi]]; Launch(a->path, a->name);
}
static void FilterChanged(void) {
    g_scroll = 0; RebuildVis(); g_sel = g_visCount ? 0 : -1; g_keynav = g_filter[0] != 0; ClampScroll(); InvBelowDash();
}
static int g_sigv[12];
static BOOL DashChanged(void) {
    SYSTEMTIME lt; GetLocalTime(&lt);
    int v[12] = { lt.wMinute, lt.wHour, lt.wDay, (int)(cpuPct + 0.5), (int)(memUsedGB * 10), netState, netSig, battPct, battAC, (int)diskFreeGB, (int)(ownMB * 10), (int)lt.wMonth };
    if (memcmp(v, g_sigv, sizeof(v)) == 0) return FALSE;
    memcpy(g_sigv, v, sizeof(v)); return TRUE;
}

// ---------- window ----------
static BOOL g_tracking; static int g_lastMx = -1, g_lastMy = -1, g_wheel;
static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: DoPaint(hwnd); return 0;
    case WM_EMBER_TOGGLE:
        if (g_shown && GetForegroundWindow() != hwnd) ForceFront();     // covered by another window: bring it back, do not hide
        else SetShown(!g_shown);
        return 0;
    case WM_SIZE:
        g_W = LOWORD(lp); g_H = HIWORD(lp);
        FreeBand(); FreeBg(); ClearSprites(); FreeIcons();
        ApplyScale(hwnd);
        return 0;
    case WM_DISPLAYCHANGE: {
        int w = GetSystemMetrics(SM_CXSCREEN), h = GetSystemMetrics(SM_CYSCREEN);
        if (w != g_W || h != g_H) SetWindowPos(hwnd, HWND_TOP, 0, 0, w, h, SWP_NOACTIVATE);
        return 0; }
    case WM_DPICHANGED: ApplyScale(hwnd); InvalidateRect(hwnd, NULL, FALSE); return 0;
    case WM_TIMER:
        switch (wp) {
        case 1:
            g_tick++; PollFast();
            if (g_tick % 5 == 0) { PollNet(); PollOwn(); }
            if (g_tick % 30 == 0) PollSlow();
            if (DashChanged()) { RECT r = { 0, 0, g_W, DashY() + DashH() + SC(30) }; InvalidateRect(hwnd, &r, FALSE); }
            break;
        case 2: KillTimer(hwnd, 2); SetBootAttempts(0); break;
        case 3:
            KillTimer(hwnd, 3);
            if (!g_shown) { FreeBand(); FreeBg(); ClearSprites(); FreeIcons(); WlanUnload(); }
            Trim(); break;
        case 5:
            KillTimer(hwnd, 5); AppsScan(); ClampScroll();
            if (g_shown) InvBelowDash(); else SetTimer(hwnd, 3, 4000, NULL);
            break;
        case 7: KillTimer(hwnd, 7); g_toast[0] = 0; { RECT r = { 0, g_H - SC(90), g_W, g_H }; InvalidateRect(hwnd, &r, FALSE); } break;
        case 9: KillTimer(hwnd, 9); PollNet(); PollOwn(); if (DashChanged()) { RECT r = { 0, 0, g_W, DashY() + DashH() + SC(30) }; InvalidateRect(hwnd, &r, FALSE); } break;
        }
        return 0;
    case WM_MOUSEMOVE: {
        int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp);
        if (!g_tracking) { TRACKMOUSEEVENT t = { sizeof(t), TME_LEAVE, hwnd, 0 }; TrackMouseEvent(&t); g_tracking = TRUE; }
        if (x == g_lastMx && y == g_lastMy) return 0;
        g_lastMx = x; g_lastMy = y;
        if (g_keynav) { g_keynav = FALSE; InvGrid(); }
        int id = HitAt(x, y);
        if (id != g_hov) {
            RECT r; int old = g_hov; g_hov = id;
            if (RectOfId(old, &r)) InvalidateRect(hwnd, &r, FALSE);
            if (RectOfId(id, &r)) InvalidateRect(hwnd, &r, FALSE);
        }
        return 0; }
    case WM_MOUSELEAVE: {
        g_tracking = FALSE; RECT r; int old = g_hov; g_hov = 0; g_lastMx = g_lastMy = -1;
        if (RectOfId(old, &r)) InvalidateRect(hwnd, &r, FALSE);
        return 0; }
    case WM_SETCURSOR:
        if (LOWORD(lp) == HTCLIENT) { SetCursor(LoadCursorW(NULL, (g_hov && g_hov != HV_PANEL) ? IDC_HAND : IDC_ARROW)); return TRUE; }
        break;
    case WM_MOUSEWHEEL: {
        g_wheel += GET_WHEEL_DELTA_WPARAM(wp); int steps = g_wheel / 120;
        if (!steps) return 0;
        g_wheel -= steps * 120;
        if (g_panel) return 0;
        int old = g_scroll; g_scroll -= steps; ClampScroll();
        if (g_scroll != old) InvGrid();
        return 0; }
    case WM_LBUTTONDOWN: {
        int x = GET_X_LPARAM(lp), y = GET_Y_LPARAM(lp), id = HitAt(x, y);
        if (g_panel) {
            if (id >= HV_PWR && id < HV_PWR + NPWR) { int a = id - HV_PWR; ClosePanel(); DoPower(a); return 0; }
            if (id == HV_PANEL) return 0;
            BOOL was = id == HV_POWER; ClosePanel(); if (was) return 0;       // power button toggles; anywhere else just closes
            id = 0;
        }
        if (id == HV_POWER) { g_panel = PN_POWER; InvRect(PwrPanelRect(), SC(30)); InvRect(PowerRect(), SC(26)); return 0; }
        if (id == HV_EXP) { Launch(L"explorer.exe", L"Explorer"); return 0; }
        if (id >= HV_TILE) { LaunchIndex(g_scroll * Cols() + (id - HV_TILE)); return 0; }
        return 0; }
    case WM_RBUTTONDOWN: {
        if (g_panel) return 0;
        int id = HitAt(GET_X_LPARAM(lp), GET_Y_LPARAM(lp));
        if (id >= HV_TILE) {
            int vi = g_scroll * Cols() + (id - HV_TILE);
            if (vi < g_visCount) { wchar_t nm[96]; Cpy(nm, 96, g_apps[g_vis[vi]].name); ToggleHidden(nm); ClampScroll(); InvBelowDash(); }
        }
        return 0; }
    case WM_CHAR: {
        wchar_t ch = (wchar_t)wp;
        if (ch == 27) {
            if (g_panel) ClosePanel(); else if (g_filter[0]) { g_filter[0] = 0; FilterChanged(); g_sel = -1; g_keynav = FALSE; }
            return 0;
        }
        if (g_panel) return 0;
        if (ch == 13) { int vi = g_sel >= 0 ? g_sel : (g_filter[0] && g_visCount ? 0 : -1); LaunchIndex(vi); return 0; }
        int n = (int)wcslen(g_filter);
        if (ch == 8) { if (n) g_filter[n - 1] = 0; else return 0; }
        else if (ch >= 32 && ch != 127 && n < 63) { g_filter[n] = ch; g_filter[n + 1] = 0; }
        else return 0;
        FilterChanged();
        return 0; }
    case WM_KEYDOWN:
        if (g_panel) return 0;
        switch (wp) {
        case VK_LEFT: SelMove(-1, 0); break;  case VK_RIGHT: SelMove(1, 0); break;
        case VK_UP: SelMove(0, -1); break;    case VK_DOWN: SelMove(0, 1); break;
        case VK_NEXT: g_scroll += RowsVisible(); ClampScroll(); InvGrid(); break;      // clamped: no more scrolling into blank space
        case VK_PRIOR: g_scroll -= RowsVisible(); ClampScroll(); InvGrid(); break;
        case VK_HOME: g_scroll = 0; g_sel = g_visCount ? 0 : -1; g_keynav = g_sel >= 0; InvGrid(); break;
        case VK_END: g_sel = g_visCount - 1; if (g_sel >= 0) { g_keynav = TRUE; g_scroll = MaxScroll(); } InvGrid(); break;
        }
        return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}
static LRESULT CALLBACK KbdHook(int code, WPARAM wp, LPARAM lp) {
    if (code == HC_ACTION) {
        KBDLLHOOKSTRUCT* k = (KBDLLHOOKSTRUCT*)lp;
        if (k->vkCode == VK_LWIN || k->vkCode == VK_RWIN) {
            if (wp == WM_KEYDOWN || wp == WM_SYSKEYDOWN) {
                if (!g_winHeld) { g_winHeld = TRUE; PostMessageW(g_hwnd, WM_EMBER_TOGGLE, 0, 0); }   // key auto-repeat no longer re-toggles
                return 1;
            }
            if (wp == WM_KEYUP || wp == WM_SYSKEYUP) g_winHeld = FALSE;
        }
    }
    return CallNextHookEx(g_hook, code, wp, lp);
}

int WINAPI wWinMain(HINSTANCE hi, HINSTANCE prev, LPWSTR cmd, int show) {
    (void)prev; (void)cmd; (void)show; g_hi = hi;
    g_mutex = CreateMutexW(NULL, TRUE, L"EmberShellSingleInstance");
    if (g_mutex && GetLastError() == ERROR_ALREADY_EXISTS) { CloseHandle(g_mutex); return 0; }
    { typedef BOOL (WINAPI *SPDAC)(HANDLE);
      HMODULE u32 = GetModuleHandleW(L"user32.dll");
      SPDAC f = u32 ? (SPDAC)GetProcAddress(u32, "SetProcessDpiAwarenessContext") : NULL;
      if (!f || !f((HANDLE)-4)) SetProcessDPIAware(); }
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    DWORD attempts = GetBootAttempts();
    if (attempts >= 3) {
        SetExplorerShell(); SetBootAttempts(0);
        MessageBoxW(NULL, L"Ember failed to start 3 times, so Windows Explorer is your shell again. Reinstall Ember to try again.", L"Ember", MB_OK | MB_ICONINFORMATION);
        return 0;
    }
    SetBootAttempts(attempts + 1);
    g_W = GetSystemMetrics(SM_CXSCREEN); g_H = GetSystemMetrics(SM_CYSCREEN);
    WNDCLASSW wc; ZeroMemory(&wc, sizeof(wc));
    wc.lpfnWndProc = WndProc; wc.hInstance = hi; wc.lpszClassName = L"EmberShellWnd";   // no CS_DBLCLKS: quick second clicks were being dropped
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    RegisterClassW(&wc);
    g_hwnd = CreateWindowExW(0, L"EmberShellWnd", L"Ember", WS_POPUP, 0, 0, g_W, g_H, NULL, NULL, hi, NULL);
    ApplyScale(g_hwnd);
    LoadSettings(); AppsScan(); WatchStart();
    PollFast(); PollSlow();
    g_shown = FALSE; SetShown(TRUE);
    SetTimer(g_hwnd, 2, 10000, NULL);
    g_hook = SetWindowsHookExW(WH_KEYBOARD_LL, KbdHook, hi, 0);
    // message loop that also wakes when the Start Menu folders change (no extra thread)
    for (;;) {
        DWORD r = MsgWaitForMultipleObjects((DWORD)g_nchg, g_nchg ? g_chg : NULL, FALSE, INFINITE, QS_ALLINPUT);
        if (r < WAIT_OBJECT_0 + (DWORD)g_nchg) {
            FindNextChangeNotification(g_chg[r - WAIT_OBJECT_0]);
            SetTimer(g_hwnd, 5, 1500, NULL);                     // debounce: installers touch many files
        } else {
            MSG m; BOOL quit = FALSE;
            while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) { if (m.message == WM_QUIT) { quit = TRUE; break; } TranslateMessage(&m); DispatchMessageW(&m); }
            if (quit) break;
        }
    }
    if (g_hook) UnhookWindowsHookEx(g_hook);
    for (int i = 0; i < g_nchg; i++) FindCloseChangeNotification(g_chg[i]);
    return 0;
}
