#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <notify.h>
#include <pwd.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t * __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t * __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t * __restrict, uid_t);

static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.nightknight.antilagshield.plist";
static NSString *const kStatePlistPath = @"/var/mobile/Library/Caches/com.nightknight.antilagshield.state.plist";
static NSString *const kLegacyStatePath = @"/var/mobile/Library/Caches/shield_state.txt";
static NSString *const kDefaultGitHubURL = @"https://github.com/NightKnight24";
static const char *const kStateChangedNotify = "com.nightknight.antilagshield.statechanged";

static volatile sig_atomic_t gStopRequested = 0;

static void handle_sigint(int sig) {
    (void)sig;
    gStopRequested = 1;
}

static NSString *jb_prefix(void) {
    return (access("/var/jb", F_OK) == 0) ? @"/var/jb" : @"";
}

static NSString *launch_daemon_plist_path(void) {
    if (access("/var/jb", F_OK) == 0) {
        return @"/var/jb/Library/LaunchDaemons/com.nightknight.antilagshield.plist";
    }
    return @"/Library/LaunchDaemons/com.nightknight.antilagshield.plist";
}

static const char *resolve_tool(const char *rel1, const char *rel2, const char *sys_fallback) {
    static char buf[256];
    if (rel1 && access(rel1, X_OK) == 0) return rel1;
    if (rel2 && access(rel2, X_OK) == 0) return rel2;
    if (sys_fallback && access(sys_fallback, X_OK) == 0) return sys_fallback;
    buf[0] = '\0';
    return NULL;
}

/*
 * Elevate to root (UID 0).
 * On rootful jailbreaks SUID (4755) handles this via setuid(0).
 * On rootless jailbreaks (/private/preboot mounted nosuid), we re-spawn once
 * into the system root persona via com.apple.private.persona-mgmt.
 */
static bool ensure_root(char *argv[]) {
    if (geteuid() == 0) {
        setuid(0);
        setgid(0);
        return true;
    }

    if (setuid(0) == 0 && geteuid() == 0) {
        setgid(0);
        return true;
    }

    if (getenv("SHIELD_PERSONA_ELEVATED") != NULL) {
        return false;
    }

    const char *self_path = "/var/jb/usr/bin/shield_ctl";
    if (access(self_path, X_OK) != 0) {
        self_path = "/usr/bin/shield_ctl";
    }
    if (access(self_path, X_OK) != 0) {
        self_path = argv[0];
    }

    posix_spawnattr_t attr;
    if (posix_spawnattr_init(&attr) != 0) {
        return false;
    }

    int r = posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    if (r == 0) {
        posix_spawnattr_set_persona_uid_np(&attr, 0);
        posix_spawnattr_set_persona_gid_np(&attr, 0);
    }

    setenv("SHIELD_PERSONA_ELEVATED", "1", 1);

    pid_t pid = 0;
    int spawn_err = posix_spawn(&pid, self_path, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);

    if (spawn_err != 0) {
        return false;
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        exit(EXIT_FAILURE);
    }
    if (WIFEXITED(status)) {
        exit(WEXITSTATUS(status));
    }
    exit(EXIT_FAILURE);
}

static NSString *run_exec_capture(const char *bin, NSArray<NSString *> *args, int *outExitCode) {
    if (!bin || access(bin, X_OK) != 0) {
        if (outExitCode) *outExitCode = 127;
        return @"";
    }

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        if (outExitCode) *outExitCode = -1;
        return @"";
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    size_t argc = args.count + 1;
    char **argv = calloc(argc + 1, sizeof(char *));
    argv[0] = strdup(bin);
    for (size_t i = 0; i < args.count; i++) {
        argv[i + 1] = strdup(args[i].UTF8String);
    }
    argv[argc] = NULL;

    pid_t pid = 0;
    int err = posix_spawn(&pid, bin, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);

    for (size_t i = 0; i < argc; i++) {
        free(argv[i]);
    }
    free(argv);

    if (err != 0) {
        close(pipefd[0]);
        if (outExitCode) *outExitCode = err;
        return @"";
    }

    NSMutableData *data = [NSMutableData data];
    char buf[1024];
    ssize_t n;
    while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) {
        [data appendBytes:buf length:(NSUInteger)n];
    }
    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);
    if (outExitCode) {
        *outExitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    }

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static void fix_mobile_ownership(NSString *path) {
    if (geteuid() == 0) {
        chown(path.UTF8String, 501, 501);
        chmod(path.UTF8String, 0644);
    }
}

static NSMutableDictionary *load_prefs(void) {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
    }
    if (!dict[@"GatewayIP"]) dict[@"GatewayIP"] = @"auto";
    if (!dict[@"GatewayMAC"]) dict[@"GatewayMAC"] = @"auto";
    if (!dict[@"GitHubURL"]) dict[@"GitHubURL"] = kDefaultGitHubURL;
    if (!dict[@"LastMode"]) dict[@"LastMode"] = @"streaming";
    return dict;
}

static bool save_prefs(NSDictionary *dict) {
    NSString *dir = [kPrefsPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL ok = [dict writeToFile:kPrefsPath atomically:YES];
    if (ok) {
        fix_mobile_ownership(kPrefsPath);
    }
    return ok;
}

static NSString *normalize_mac(NSString *rawMac) {
    if (!rawMac || rawMac.length == 0) return nil;
    NSArray<NSString *> *parts = [[rawMac lowercaseString] componentsSeparatedByString:@":"];
    if (parts.count != 6) return nil;

    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:6];
    for (NSString *part in parts) {
        if (part.length < 1 || part.length > 2) return nil;
        for (NSUInteger i = 0; i < part.length; i++) {
            unichar c = [part characterAtIndex:i];
            if (!isxdigit((int)c)) return nil;
        }
        [out addObject:(part.length == 1) ? [@"0" stringByAppendingString:part] : part];
    }
    return [out componentsJoinedByString:@":"];
}

static bool is_valid_ipv4(NSString *ip) {
    if (!ip || ip.length == 0) return false;
    struct in_addr addr;
    return inet_pton(AF_INET, ip.UTF8String, &addr) == 1;
}

typedef struct {
    char iface[32];
    char router_ip[64];
    char router_mac[32];
    bool arp_permanent;
} GatewayInfo;

static void query_arp_table(const char *ip, char *outMac, size_t macCap, bool *outPermanent) {
    outMac[0] = '\0';
    if (outPermanent) *outPermanent = false;
    if (!ip || ip[0] == '\0') return;

    const char *arp_bin = resolve_tool("/var/jb/usr/sbin/arp", "/usr/sbin/arp", "/sbin/arp");
    if (!arp_bin) return;

    int code = 0;
    NSString *out = run_exec_capture(arp_bin, @[@"-n", [NSString stringWithUTF8String:ip]], &code);
    if (out.length == 0) return;

    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        NSRange atRange = [line rangeOfString:@" at "];
        if (atRange.location == NSNotFound) continue;
        NSString *rest = [line substringFromIndex:atRange.location + 4];
        NSArray<NSString *> *tokens = [rest componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (tokens.count > 0) {
            NSString *norm = normalize_mac(tokens[0]);
            if (norm) {
                strlcpy(outMac, norm.UTF8String, macCap);
                if (outPermanent && [line containsString:@"permanent"]) {
                    *outPermanent = true;
                }
                return;
            }
        }
    }
}

static GatewayInfo resolve_gateway(void) {
    GatewayInfo info;
    memset(&info, 0, sizeof(info));
    strlcpy(info.iface, "en0", sizeof(info.iface));

    NSDictionary *prefs = load_prefs();
    NSString *cfgIP = prefs[@"GatewayIP"] ?: @"auto";
    NSString *cfgMAC = prefs[@"GatewayMAC"] ?: @"auto";

    const char *route_bin = resolve_tool("/var/jb/sbin/route", "/sbin/route", "/usr/sbin/route");
    if (route_bin) {
        int code = 0;
        NSString *routeOut = run_exec_capture(route_bin, @[@"-n", @"get", @"default"], &code);
        for (NSString *line in [routeOut componentsSeparatedByString:@"\n"]) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmed hasPrefix:@"interface:"]) {
                NSString *v = [[trimmed substringFromIndex:10] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (v.length > 0) strlcpy(info.iface, v.UTF8String, sizeof(info.iface));
            } else if ([trimmed hasPrefix:@"gateway:"]) {
                NSString *v = [[trimmed substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (is_valid_ipv4(v)) strlcpy(info.router_ip, v.UTF8String, sizeof(info.router_ip));
            }
        }
    }

    if (![cfgIP isEqualToString:@"auto"] && is_valid_ipv4(cfgIP)) {
        strlcpy(info.router_ip, cfgIP.UTF8String, sizeof(info.router_ip));
    }

    if (info.router_ip[0] != '\0') {
        bool perm = false;
        char detected_mac[32] = {0};
        query_arp_table(info.router_ip, detected_mac, sizeof(detected_mac), &perm);

        if (detected_mac[0] == '\0') {
            const char *ping_bin = resolve_tool("/var/jb/sbin/ping", "/sbin/ping", "/usr/sbin/ping");
            if (ping_bin) {
                int pcode = 0;
                run_exec_capture(ping_bin, @[@"-c", @"1", @"-W", @"250", [NSString stringWithUTF8String:info.router_ip]], &pcode);
                query_arp_table(info.router_ip, detected_mac, sizeof(detected_mac), &perm);
            }
        }

        if (![cfgMAC isEqualToString:@"auto"]) {
            NSString *norm = normalize_mac(cfgMAC);
            if (norm) {
                strlcpy(info.router_mac, norm.UTF8String, sizeof(info.router_mac));
            }
        } else if (detected_mac[0] != '\0') {
            strlcpy(info.router_mac, detected_mac, sizeof(info.router_mac));
        }
        info.arp_permanent = perm;
    }

    return info;
}

static bool set_sysctl_int(const char *name, int value) {
    if (sysctlbyname(name, NULL, NULL, &value, sizeof(value)) != 0) {
        return false;
    }
    int verify = 0;
    size_t len = sizeof(verify);
    if (sysctlbyname(name, &verify, &len, NULL, 0) != 0) {
        return false;
    }
    return (verify == value);
}

typedef struct {
    const char *name;
    int value;
} SysctlPair;

static void adjust_process_priorities(bool active) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size == 0) {
        return;
    }

    size += sizeof(struct kinfo_proc) * 32;
    struct kinfo_proc *procs = malloc(size);
    if (!procs) return;

    if (sysctl(mib, 3, procs, &size, NULL, 0) != 0) {
        free(procs);
        return;
    }

    static const char *const kVipNames[] = {
        "mediaserverd", "coreaudiod", "avconferenced", "gamecontrollerd",
        "WebKit", "Stremio", "NodeMobile", "ffmpeg",
        "YouTube", "Netflix", "Dominguez", "PrimeVideo", "Argo", "Disney",
        "Max", "Twitch", "Infuse", "VLC", "Outplayer", "Kodi", "Plex",
        "Roblox", "Minecraft", "PojavLauncher", "Delta", "RetroArch",
        "PPSSPP", "Moonlight", "SteamLink"
    };

    static const char *const kHogNames[] = {
        "nsurlsessiond", "cloudd", "appstored",
        "analyticsd", "triald", "photoanalysisd"
    };

    size_t count = size / sizeof(struct kinfo_proc);
    for (size_t i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1) continue;
        const char *comm = procs[i].kp_proc.p_comm;
        if (!comm || comm[0] == '\0') continue;

        for (size_t v = 0; v < sizeof(kVipNames) / sizeof(kVipNames[0]); v++) {
            if (strcasestr(comm, kVipNames[v]) != NULL) {
                setpriority(PRIO_PROCESS, (id_t)pid, active ? -10 : 0);
                break;
            }
        }

        for (size_t h = 0; h < sizeof(kHogNames) / sizeof(kHogNames[0]); h++) {
            if (strcasecmp(comm, kHogNames[h]) == 0) {
                setpriority(PRIO_PROCESS, (id_t)pid, active ? 10 : 0);
                break;
            }
        }
    }

    free(procs);
}

static bool set_awdl_up(bool up) {
    const char *ifconfig_bin = resolve_tool("/var/jb/sbin/ifconfig", "/sbin/ifconfig", "/usr/sbin/ifconfig");
    if (!ifconfig_bin) return false;
    int check_code = 0;
    run_exec_capture(ifconfig_bin, @[@"awdl0"], &check_code);
    if (check_code != 0) return false;

    int set_code = 0;
    run_exec_capture(ifconfig_bin, @[@"awdl0", up ? @"up" : @"down"], &set_code);
    return (set_code == 0);
}

static bool apply_optimizations(NSString *mode, int *outApplied, int *outTotal, GatewayInfo *outGw) {
    GatewayInfo gw = resolve_gateway();

    /* Lock static ARP entry if gateway IP and MAC were resolved */
    const char *arp_bin = resolve_tool("/var/jb/usr/sbin/arp", "/usr/sbin/arp", "/sbin/arp");
    if (arp_bin && gw.router_ip[0] != '\0' && gw.router_mac[0] != '\0') {
        int code = 0;
        NSString *ipStr = [NSString stringWithUTF8String:gw.router_ip];
        NSString *macStr = [NSString stringWithUTF8String:gw.router_mac];
        NSString *ifStr = [NSString stringWithUTF8String:gw.iface];
        run_exec_capture(arp_bin, @[@"-s", ipStr, macStr, @"ifscope", ifStr], &code);
        bool perm = false;
        char verifyMac[32] = {0};
        query_arp_table(gw.router_ip, verifyMac, sizeof(verifyMac), &perm);
        gw.arp_permanent = perm;
    }

    bool isGaming = [mode isEqualToString:@"gaming"];

    const SysctlPair commonPairs[] = {
        {"net.inet.tcp.blackhole", 2},
        {"net.inet.udp.blackhole", 1},
        {"net.inet.icmp.drop_redirect", 1},
        {"net.inet.ip.redirect", 0},
        {"net.inet6.icmp6.rediraccept", 0},
        {"net.inet.tcp.drop_synfin", 1},
        {"net.qos.policy.wifi_enabled", 0},
        {"net.qos.policy.capable_enabled", 0},
        {"net.qos.reset_dscp_to_wifi_ac_map", 0},
        {"kern.memorystatus_purge_on_warning", 0},
        {"net.inet.tcp.always_keepalive", 1},
        {"net.inet.tcp.keepidle", 30000},
        {"kern.ipc.somaxconn", 512},
    };

    const SysctlPair gamingPairs[] = {
        {"net.inet.tcp.tso", 0},
        {"net.inet.tcp.delayed_ack", 0},
        {"net.inet.tcp.sendspace", 131072},
        {"net.inet.tcp.recvspace", 131072},
        {"net.inet.tcp.autorcvbufmax", 2097152},
        {"net.inet.tcp.autosndbufmax", 2097152},
        {"net.inet.udp.recvspace", 1048576},
        {"net.inet.udp.maxdgram", 65535},
    };

    const SysctlPair streamingPairs[] = {
        {"net.inet.tcp.tso", 1},
        {"net.inet.tcp.delayed_ack", 3},
        {"net.inet.tcp.sendspace", 262144},
        {"net.inet.tcp.recvspace", 524288},
        {"net.inet.tcp.autorcvbufmax", 4194304},
        {"net.inet.tcp.autosndbufmax", 4194304},
        {"net.inet.udp.recvspace", 2097152},
        {"net.inet.udp.maxdgram", 65535},
    };

    int okCount = 0;
    int totalCount = 0;

    for (size_t i = 0; i < sizeof(commonPairs) / sizeof(commonPairs[0]); i++) {
        totalCount++;
        if (set_sysctl_int(commonPairs[i].name, commonPairs[i].value)) {
            okCount++;
        }
    }

    const SysctlPair *modePairs = isGaming ? gamingPairs : streamingPairs;
    size_t modePairCount = sizeof(gamingPairs) / sizeof(gamingPairs[0]);
    bool criticalOk = true;

    for (size_t i = 0; i < modePairCount; i++) {
        totalCount++;
        if (set_sysctl_int(modePairs[i].name, modePairs[i].value)) {
            okCount++;
        } else if (strcmp(modePairs[i].name, "net.inet.tcp.delayed_ack") == 0 ||
                   strcmp(modePairs[i].name, "net.inet.tcp.autorcvbufmax") == 0) {
            criticalOk = false;
        }
    }

    adjust_process_priorities(true);
    set_awdl_up(false);

    if (outApplied) *outApplied = okCount;
    if (outTotal) *outTotal = totalCount;
    if (outGw) *outGw = gw;

    return criticalOk && (okCount > 0);
}

static bool revert_optimizations(void) {
    set_awdl_up(true);

    GatewayInfo gw = resolve_gateway();
    const char *arp_bin = resolve_tool("/var/jb/usr/sbin/arp", "/usr/sbin/arp", "/sbin/arp");
    if (arp_bin && gw.router_ip[0] != '\0' && gw.arp_permanent) {
        int code = 0;
        run_exec_capture(arp_bin, @[
            @"-d",
            [NSString stringWithUTF8String:gw.router_ip],
            @"ifscope",
            [NSString stringWithUTF8String:gw.iface]
        ], &code);
    }

    const SysctlPair stockPairs[] = {
        {"net.inet.tcp.blackhole", 0},
        {"net.inet.udp.blackhole", 0},
        {"net.inet.icmp.drop_redirect", 0},
        {"net.inet.ip.redirect", 1},
        {"net.inet6.icmp6.rediraccept", 1},
        {"net.inet.tcp.drop_synfin", 0},
        {"net.inet.tcp.tso", 1},
        {"net.inet.tcp.delayed_ack", 3},
        {"net.inet.tcp.sendspace", 131072},
        {"net.inet.tcp.recvspace", 131072},
        {"net.inet.tcp.autorcvbufmax", 2097152},
        {"net.inet.tcp.autosndbufmax", 2097152},
        {"net.inet.udp.recvspace", 786896},
        {"kern.ipc.somaxconn", 128},
        {"kern.memorystatus_purge_on_warning", 1},
    };

    int okCount = 0;
    for (size_t i = 0; i < sizeof(stockPairs) / sizeof(stockPairs[0]); i++) {
        if (set_sysctl_int(stockPairs[i].name, stockPairs[i].value)) {
            okCount++;
        }
    }

    adjust_process_priorities(false);
    return (okCount > 0);
}

static void write_state(bool active, NSString *mode) {
    NSString *cacheDir = [kStatePlistPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *state = @{
        @"Active": @(active),
        @"Mode": active ? (mode ?: @"streaming") : @"off",
        @"UpdatedAt": @([[NSDate date] timeIntervalSince1970])
    };
    [state writeToFile:kStatePlistPath atomically:YES];
    fix_mobile_ownership(kStatePlistPath);

    if (active) {
        NSString *txt = [NSString stringWithFormat:@"ACTIVE:%@\n", mode];
        [txt writeToFile:kLegacyStatePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        fix_mobile_ownership(kLegacyStatePath);

        NSMutableDictionary *prefs = load_prefs();
        prefs[@"LastMode"] = mode;
        save_prefs(prefs);
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:kLegacyStatePath error:nil];
    }

    notify_post(kStateChangedNotify);
}

static NSString *read_active_mode(bool *outActive) {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:kStatePlistPath];
    if (state) {
        bool active = [state[@"Active"] boolValue];
        if (outActive) *outActive = active;
        return active ? (state[@"Mode"] ?: @"streaming") : @"off";
    }

    NSString *legacy = [NSString stringWithContentsOfFile:kLegacyStatePath encoding:NSUTF8StringEncoding error:nil];
    if (legacy && [legacy hasPrefix:@"ACTIVE:"]) {
        if (outActive) *outActive = true;
        NSString *m = [[legacy substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return ([m isEqualToString:@"gaming"]) ? @"gaming" : @"streaming";
    }

    if (outActive) *outActive = false;
    return @"off";
}

static int cmd_clean(void) {
    NSArray<NSString *> *targetDirs = @[
        @"/var/mobile/Library/Logs/CrashReporter",
        @"/var/mobile/Library/Logs/DiagnosticReports",
        @"/var/mobile/Library/Caches/com.apple.Safari.SafeBrowsing",
        @"/var/mobile/Library/Caches/com.apple.QuickLook.thumbnailcache",
        @"/var/mobile/Library/Caches/com.apple.parsecd",
        @"/var/mobile/Library/Caches/com.apple.tipsd",
        @"/var/mobile/Library/Caches/com.apple.rtcreporting",
        @"/var/mobile/Library/Caches/com.apple.AppleMediaServices",
        @"/var/log/asl"
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    unsigned long long freedBytes = 0;
    NSUInteger removedFiles = 0;

    for (NSString *dir in targetDirs) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
            continue;
        }
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:dir];
        NSString *relPath = nil;
        BOOL isCacheDir = [dir hasPrefix:@"/var/mobile/Library/Caches/"];
        while ((relPath = [enumerator nextObject]) != nil) {
            NSString *lower = relPath.lowercaseString;
            if (isCacheDir && ([lower hasSuffix:@".db"] ||
                               [lower hasSuffix:@".db-wal"] ||
                               [lower hasSuffix:@".db-shm"] ||
                               [lower hasSuffix:@".db-journal"] ||
                               [lower hasSuffix:@".sqlite"] ||
                               [lower hasSuffix:@".sqlite-wal"] ||
                               [lower hasSuffix:@".sqlite-shm"])) {
                continue;
            }
            NSString *fullPath = [dir stringByAppendingPathComponent:relPath];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            if (!attrs) continue;
            if (![attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
                continue;
            }
            unsigned long long fileSize = [attrs[NSFileSize] unsignedLongLongValue];
            if ([fm removeItemAtPath:fullPath error:nil]) {
                freedBytes += fileSize;
                removedFiles++;
            }
        }
    }

    double mb = (double)freedBytes / (1024.0 * 1024.0);
    printf("CLEANED:%lu:%llu:%.2fMB\n", (unsigned long)removedFiles, freedBytes, mb);
    return 0;
}

static int cmd_turbo(NSString *sub) {
    /*
     * Accessibility preferences live in mobile's user domain (UID 501).
     * Drop effective UID to mobile if invoked as root so SpringBoard sees the update.
     */
    if (geteuid() == 0) {
        setegid(501);
        seteuid(501);
    }

    void *handle = dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_LAZY);
    if (!handle) {
        fprintf(stderr, "ERROR:AccessibilityUtilities unavailable\n");
        return 1;
    }

    typedef void (*AXSetBoolFn)(BOOL);
    typedef BOOL (*AXGetBoolFn)(void);

    AXSetBoolFn setMotion = (AXSetBoolFn)dlsym(handle, "_AXSSetReduceMotionEnabled");
    AXSetBoolFn setContrast = (AXSetBoolFn)dlsym(handle, "_AXSSetEnhanceBackgroundContrastEnabled");
    AXGetBoolFn getMotion = (AXGetBoolFn)dlsym(handle, "_AXSReduceMotionEnabled");
    AXGetBoolFn getContrast = (AXGetBoolFn)dlsym(handle, "_AXSEnhanceBackgroundContrastEnabled");

    if (!setMotion || !getMotion) {
        dlclose(handle);
        fprintf(stderr, "ERROR:Accessibility symbols missing\n");
        return 1;
    }

    if ([sub isEqualToString:@"enable"] || [sub isEqualToString:@"on"] || [sub isEqualToString:@"1"]) {
        setMotion(YES);
        if (setContrast) setContrast(YES);
        BOOL verified = getMotion();
        dlclose(handle);
        if (!verified) {
            fprintf(stderr, "ERROR:Reduce Motion could not be enabled\n");
            return 1;
        }
        printf("TURBO_ENABLED\n");
        return 0;
    } else if ([sub isEqualToString:@"disable"] || [sub isEqualToString:@"off"] || [sub isEqualToString:@"0"]) {
        setMotion(NO);
        if (setContrast) setContrast(NO);
        dlclose(handle);
        printf("TURBO_DISABLED\n");
        return 0;
    } else {
        BOOL motion = getMotion();
        BOOL contrast = getContrast ? getContrast() : motion;
        dlclose(handle);
        printf("%s\n", (motion && contrast) ? "TURBO_ACTIVE" : "TURBO_INACTIVE");
        return 0;
    }
}

static bool get_iface_counters(const char *iface, uint64_t *rx, uint64_t *tx) {
    *rx = 0;
    *tx = 0;
    struct ifaddrs *ifap = NULL;
    if (getifaddrs(&ifap) != 0) return false;

    bool found = false;
    for (struct ifaddrs *ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_name || !ifa->ifa_addr || !ifa->ifa_data) continue;
        if (ifa->ifa_addr->sa_family == AF_LINK && strcmp(ifa->ifa_name, iface) == 0) {
            struct if_data *ifd = (struct if_data *)ifa->ifa_data;
            *rx = ifd->ifi_ibytes;
            *tx = ifd->ifi_obytes;
            found = true;
            break;
        }
    }
    freeifaddrs(ifap);
    return found;
}

static double ping_once_ms(const char *host, int timeout_ms) {
    if (!host || host[0] == '\0') return -1.0;
    const char *ping_bin = resolve_tool("/var/jb/sbin/ping", "/sbin/ping", "/usr/sbin/ping");
    if (!ping_bin) return -1.0;

    int code = 0;
    NSString *out = run_exec_capture(ping_bin, @[
        @"-c", @"1",
        @"-W", [NSString stringWithFormat:@"%d", timeout_ms],
        [NSString stringWithUTF8String:host]
    ], &code);
    if (code != 0 || out.length == 0) return -1.0;

    NSRange r = [out rangeOfString:@"time="];
    if (r.location == NSNotFound) return -1.0;
    NSString *sub = [out substringFromIndex:r.location + 5];
    return [sub doubleValue];
}

static void format_rate(double bps, char *buf, size_t cap) {
    if (bps >= 1048576.0) {
        snprintf(buf, cap, "%.1f MB/s", bps / 1048576.0);
    } else if (bps >= 1024.0) {
        snprintf(buf, cap, "%.1f KB/s", bps / 1024.0);
    } else {
        snprintf(buf, cap, "%.0f B/s", bps);
    }
}

static int cmd_run_hud(NSString *mode) {
    int applied = 0, total = 0;
    GatewayInfo gw;
    if (!apply_optimizations(mode, &applied, &total, &gw)) {
        fprintf(stderr, "ERROR:Failed to apply kernel sysctls\n");
        return 1;
    }
    write_state(true, mode);

    signal(SIGINT, handle_sigint);
    signal(SIGTERM, handle_sigint);
    signal(SIGHUP, handle_sigint);

    printf("Anti-Lag Shield active [%s] on %s (%d/%d sysctls applied). Press Ctrl+C to stop.\n",
           mode.UTF8String, gw.iface, applied, total);

    uint64_t lastRx = 0, lastTx = 0;
    get_iface_counters(gw.iface, &lastRx, &lastTx);

    while (!gStopRequested) {
        sleep(1);
        if (gStopRequested) break;

        uint64_t curRx = 0, curTx = 0;
        get_iface_counters(gw.iface, &curRx, &curTx);
        double downBps = (curRx >= lastRx) ? (double)(curRx - lastRx) : 0.0;
        double upBps = (curTx >= lastTx) ? (double)(curTx - lastTx) : 0.0;
        lastRx = curRx;
        lastTx = curTx;

        char downStr[32], upStr[32];
        format_rate(downBps, downStr, sizeof(downStr));
        format_rate(upBps, upStr, sizeof(upStr));

        double rMs = ping_once_ms(gw.router_ip, 300);
        double iMs = ping_once_ms("1.1.1.1", 400);

        time_t now = time(NULL);
        struct tm tmv;
        localtime_r(&now, &tmv);
        char ts[16];
        strftime(ts, sizeof(ts), "%H:%M:%S", &tmv);

        char rBuf[24], iBuf[24];
        if (rMs >= 0.0) snprintf(rBuf, sizeof(rBuf), "%.1f ms", rMs);
        else strlcpy(rBuf, "timeout", sizeof(rBuf));

        if (iMs >= 0.0) snprintf(iBuf, sizeof(iBuf), "%.1f ms", iMs);
        else strlcpy(iBuf, "timeout", sizeof(iBuf));

        printf("[%s] %-9s | %s | GW: %-9s | 1.1.1.1: %-9s | RX: %-10s | TX: %-10s\n",
               ts, mode.UTF8String, gw.iface, rBuf, iBuf, downStr, upStr);
        fflush(stdout);
    }

    revert_optimizations();
    write_state(false, @"off");
    printf("\nDefaults restored.\n");
    return 0;
}

static int cmd_daemon(NSString *sub, NSString *modeArg) {
    NSString *plistPath = launch_daemon_plist_path();
    NSFileManager *fm = [NSFileManager defaultManager];

    if ([sub isEqualToString:@"status"] || sub.length == 0) {
        BOOL exists = [fm fileExistsAtPath:plistPath];
        printf("%s\n", exists ? "DAEMON_ACTIVE" : "DAEMON_INACTIVE");
        return 0;
    }

    if ([sub isEqualToString:@"enable"]) {
        NSString *mode = ([modeArg isEqualToString:@"gaming"]) ? @"gaming" : @"streaming";
        NSString *ctlPath = [jb_prefix() stringByAppendingString:@"/usr/bin/shield_ctl"];
        if (![fm fileExistsAtPath:ctlPath]) {
            ctlPath = @"/usr/bin/shield_ctl";
        }

        NSString *dir = [plistPath stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

        NSDictionary *daemonPlist = @{
            @"Label": @"com.nightknight.antilagshield",
            @"ProgramArguments": @[ctlPath, @"start", mode],
            @"RunAtLoad": @YES,
            @"KeepAlive": @NO,
            @"StandardOutPath": @"/dev/null",
            @"StandardErrorPath": @"/dev/null"
        };

        if (![daemonPlist writeToFile:plistPath atomically:YES]) {
            fprintf(stderr, "ERROR:Unable to write LaunchDaemon plist at %s\n", plistPath.UTF8String);
            return 1;
        }
        chown(plistPath.UTF8String, 0, 0);
        chmod(plistPath.UTF8String, 0644);

        const char *launchctl_bin = resolve_tool("/var/jb/bin/launchctl", "/var/jb/usr/bin/launchctl", "/bin/launchctl");
        if (launchctl_bin) {
            int code = 0;
            run_exec_capture(launchctl_bin, @[@"unload", plistPath], &code);
            run_exec_capture(launchctl_bin, @[@"load", @"-w", plistPath], &code);
        }

        int applied = 0, total = 0;
        if (!apply_optimizations(mode, &applied, &total, NULL)) {
            fprintf(stderr, "ERROR:Failed to apply kernel sysctls\n");
            return 1;
        }
        write_state(true, mode);
        printf("DAEMON_ENABLED:%s\n", mode.UTF8String);
        return 0;
    }

    if ([sub isEqualToString:@"disable"]) {
        const char *launchctl_bin = resolve_tool("/var/jb/bin/launchctl", "/var/jb/usr/bin/launchctl", "/bin/launchctl");
        if (launchctl_bin && [fm fileExistsAtPath:plistPath]) {
            int code = 0;
            run_exec_capture(launchctl_bin, @[@"unload", @"-w", plistPath], &code);
        }
        [fm removeItemAtPath:plistPath error:nil];
        notify_post(kStateChangedNotify);
        printf("DAEMON_DISABLED\n");
        return 0;
    }

    fprintf(stderr, "Usage: shield_ctl daemon {enable [streaming|gaming]|disable|status}\n");
    return 1;
}

static int cmd_config(int argc, char *argv[]) {
    NSString *sub = (argc >= 3) ? [NSString stringWithUTF8String:argv[2]] : @"show";
    NSMutableDictionary *prefs = load_prefs();

    if ([sub isEqualToString:@"set"]) {
        if (argc < 5) {
            fprintf(stderr, "Usage: shield_ctl config set <gateway_ip> <gateway_mac>\n");
            return 1;
        }
        NSString *ip = [NSString stringWithUTF8String:argv[3]];
        NSString *mac = normalize_mac([NSString stringWithUTF8String:argv[4]]);
        if (!is_valid_ipv4(ip) || !mac) {
            fprintf(stderr, "ERROR:Invalid IPv4 or MAC address format\n");
            return 1;
        }
        prefs[@"GatewayIP"] = ip;
        prefs[@"GatewayMAC"] = mac;
        if (!save_prefs(prefs)) {
            fprintf(stderr, "ERROR:Failed to save preferences\n");
            return 1;
        }
        printf("CONFIG_SAVED:IP=%s:MAC=%s\n", ip.UTF8String, mac.UTF8String);
        return 0;
    }

    if ([sub isEqualToString:@"set-github"]) {
        if (argc < 4) {
            fprintf(stderr, "Usage: shield_ctl config set-github <url>\n");
            return 1;
        }
        NSString *url = [[NSString stringWithUTF8String:argv[3]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (url.length == 0) {
            fprintf(stderr, "ERROR:Empty URL\n");
            return 1;
        }
        prefs[@"GitHubURL"] = url;
        if (!save_prefs(prefs)) {
            fprintf(stderr, "ERROR:Failed to save preferences\n");
            return 1;
        }
        printf("CONFIG_SAVED:GITHUB_URL=%s\n", url.UTF8String);
        return 0;
    }

    if ([sub isEqualToString:@"auto"]) {
        prefs[@"GatewayIP"] = @"auto";
        prefs[@"GatewayMAC"] = @"auto";
        save_prefs(prefs);
        GatewayInfo gw = resolve_gateway();
        printf("CONFIG_AUTO_RESET:IP=%s:MAC=%s\n", gw.router_ip, gw.router_mac);
        return 0;
    }

    GatewayInfo gw = resolve_gateway();
    printf("MODE=%s\n", [prefs[@"GatewayIP"] UTF8String]);
    printf("INTERFACE=%s\n", gw.iface);
    printf("ROUTER_IP=%s\n", gw.router_ip);
    printf("ROUTER_MAC=%s\n", gw.router_mac);
    printf("ARP_PERMANENT=%d\n", gw.arp_permanent ? 1 : 0);
    printf("LAST_MODE=%s\n", [prefs[@"LastMode"] UTF8String]);
    printf("GITHUB_URL=%s\n", [prefs[@"GitHubURL"] UTF8String]);
    return 0;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "Usage: %s {start [streaming|gaming]|stop|status|purge|clean|turbo [enable|disable|status]|config [show|set <ip> <mac>|set-github <url>|auto]|daemon [enable|disable|status]|run [streaming|gaming]}\n", argv[0]);
            return 1;
        }

        NSString *action = [NSString stringWithUTF8String:argv[1]];
        NSString *arg2 = (argc >= 3) ? [NSString stringWithUTF8String:argv[2]] : nil;

        /* Unprivileged / mobile-scoped commands */
        if ([action isEqualToString:@"turbo"]) {
            return cmd_turbo(arg2 ?: @"status");
        }

        if ([action isEqualToString:@"status"]) {
            bool active = false;
            NSString *mode = read_active_mode(&active);
            if ([arg2 isEqualToString:@"--detail"]) {
                GatewayInfo gw = resolve_gateway();
                BOOL bootDaemon = [[NSFileManager defaultManager] fileExistsAtPath:launch_daemon_plist_path()];
                NSDictionary *prefs = load_prefs();
                printf("STATE=%s\n", active ? [NSString stringWithFormat:@"ACTIVE:%@", mode].UTF8String : "INACTIVE");
                printf("MODE=%s\n", mode.UTF8String);
                printf("LAST_MODE=%s\n", [prefs[@"LastMode"] UTF8String]);
                printf("INTERFACE=%s\n", gw.iface);
                printf("ROUTER_IP=%s\n", gw.router_ip);
                printf("ROUTER_MAC=%s\n", gw.router_mac);
                printf("ARP_PERMANENT=%d\n", gw.arp_permanent ? 1 : 0);
                printf("BOOT_DAEMON=%d\n", bootDaemon ? 1 : 0);
                printf("GITHUB_URL=%s\n", [prefs[@"GitHubURL"] UTF8String]);
            } else {
                if (active) {
                    printf("ACTIVE:%s\n", mode.UTF8String);
                } else {
                    printf("INACTIVE\n");
                }
            }
            return 0;
        }

        if ([action isEqualToString:@"config"]) {
            if (arg2 && ([arg2 isEqualToString:@"set"] || [arg2 isEqualToString:@"set-github"] || [arg2 isEqualToString:@"auto"])) {
                /* Allow mobile or root to update preferences */
            }
            return cmd_config(argc, argv);
        }

        if ([action isEqualToString:@"daemon"] && (!arg2 || [arg2 isEqualToString:@"status"])) {
            return cmd_daemon(@"status", nil);
        }

        /* Privileged commands require UID 0 */
        if (!ensure_root(argv)) {
            fprintf(stderr, "ERROR:Unable to acquire root privileges (euid=%u)\n", (unsigned)geteuid());
            return 1;
        }

        if ([action isEqualToString:@"start"] || [action isEqualToString:@"start_daemon"]) {
            NSString *mode = ([arg2 isEqualToString:@"gaming"]) ? @"gaming" : @"streaming";
            int applied = 0, total = 0;
            GatewayInfo gw;
            if (!apply_optimizations(mode, &applied, &total, &gw)) {
                fprintf(stderr, "ERROR:Kernel sysctl tuning failed (%d/%d applied)\n", applied, total);
                return 1;
            }
            write_state(true, mode);
            printf("SHIELD_STARTED:%s:%d/%d:ARP=%d\n", mode.UTF8String, applied, total, gw.arp_permanent ? 1 : 0);
            return 0;
        }

        if ([action isEqualToString:@"stop"]) {
            if (!revert_optimizations()) {
                fprintf(stderr, "ERROR:Failed to restore kernel sysctls\n");
                return 1;
            }
            write_state(false, @"off");
            printf("SHIELD_STOPPED\n");
            return 0;
        }

        if ([action isEqualToString:@"purge"]) {
            const char *purge_bin = resolve_tool("/var/jb/usr/bin/purge", "/usr/sbin/purge", "/usr/bin/purge");
            if (!purge_bin) {
                fprintf(stderr, "ERROR:purge binary not installed\n");
                return 1;
            }
            int code = 0;
            run_exec_capture(purge_bin, @[], &code);
            if (code != 0) {
                fprintf(stderr, "ERROR:purge exited with status %d\n", code);
                return 1;
            }
            printf("RAM_PURGED\n");
            return 0;
        }

        if ([action isEqualToString:@"clean"] || [action isEqualToString:@"deepclean"]) {
            return cmd_clean();
        }

        if ([action isEqualToString:@"daemon"]) {
            NSString *arg3 = (argc >= 4) ? [NSString stringWithUTF8String:argv[3]] : nil;
            return cmd_daemon(arg2, arg3);
        }

        if ([action isEqualToString:@"run"] || [action isEqualToString:@"hud"] || [action isEqualToString:@"interactive"]) {
            NSString *mode = ([arg2 isEqualToString:@"gaming"]) ? @"gaming" : @"streaming";
            return cmd_run_hud(mode);
        }

        fprintf(stderr, "Unknown command: %s\n", action.UTF8String);
        return 1;
    }
}
