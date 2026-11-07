#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <net/if.h>
#include <notify.h>
#include <spawn.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static const char *const kStateChangedNotify = "com.nightknight.antilagshield.statechanged";
static const char *const kShowBannerNotify = "com.nightknight.antilagshield.showbanner";

typedef void (*AXSetBoolFn)(BOOL);
typedef BOOL (*AXGetBoolFn)(void);

static BOOL set_turbo_ui(BOOL enabled) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_LAZY);
    if (!handle) return NO;

    AXSetBoolFn setMotion = (AXSetBoolFn)dlsym(handle, "_AXSSetReduceMotionEnabled");
    AXSetBoolFn setContrast = (AXSetBoolFn)dlsym(handle, "_AXSSetEnhanceBackgroundContrastEnabled");
    AXGetBoolFn getMotion = (AXGetBoolFn)dlsym(handle, "_AXSReduceMotionEnabled");

    if (setMotion) setMotion(enabled);
    if (setContrast) setContrast(enabled);
    BOOL current = getMotion ? getMotion() : NO;
    dlclose(handle);
    return (current == enabled);
}

static BOOL get_turbo_ui_status(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_LAZY);
    if (!handle) return NO;

    AXGetBoolFn getMotion = (AXGetBoolFn)dlsym(handle, "_AXSReduceMotionEnabled");
    BOOL res = getMotion ? getMotion() : NO;
    dlclose(handle);
    return res;
}

static const char *shield_ctl_bin(void) {
    if (access("/var/jb/usr/bin/shield_ctl", X_OK) == 0) {
        return "/var/jb/usr/bin/shield_ctl";
    }
    return "/usr/bin/shield_ctl";
}

static const char *ping_bin(void) {
    if (access("/var/jb/sbin/ping", X_OK) == 0) return "/var/jb/sbin/ping";
    if (access("/sbin/ping", X_OK) == 0) return "/sbin/ping";
    return "/usr/sbin/ping";
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
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

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

static NSUInteger get_available_memory_mb(void) {
    mach_port_t host_port = mach_host_self();
    vm_size_t pagesize = 0;
    host_page_size(host_port, &pagesize);

    vm_statistics64_data_t vm_stat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(host_port, HOST_VM_INFO64, (host_info64_t)&vm_stat, &count);
    mach_port_deallocate(mach_task_self(), host_port);
    if (kr != KERN_SUCCESS) {
        return 0;
    }

    uint64_t freePages = (uint64_t)vm_stat.free_count + (uint64_t)vm_stat.speculative_count;
    uint64_t bytes = freePages * (uint64_t)pagesize;
    return (NSUInteger)(bytes / (1024ULL * 1024ULL));
}

static BOOL read_sysctl_int(const char *name, int *outVal) {
    int val = 0;
    size_t len = sizeof(val);
    if (sysctlbyname(name, &val, &len, NULL, 0) != 0) {
        return NO;
    }
    if (outVal) *outVal = val;
    return YES;
}

static BOOL is_interface_up(const char *ifname, BOOL *outExists) {
    struct ifaddrs *ifap = NULL;
    if (outExists) *outExists = NO;
    if (getifaddrs(&ifap) != 0) return NO;

    BOOL isUp = NO;
    for (struct ifaddrs *ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
        if (ifa->ifa_name && strcmp(ifa->ifa_name, ifname) == 0) {
            if (outExists) *outExists = YES;
            if (ifa->ifa_flags & IFF_UP) {
                isUp = YES;
                break;
            }
        }
    }
    freeifaddrs(ifap);
    return isUp;
}

static int query_iokit_battery_percent(BOOL *outCharging) {
    if (outCharging) *outCharging = NO;
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!iokit) return -1;

    typedef CFTypeRef (*IOPSCopyPowerSourcesInfoFn)(void);
    typedef CFArrayRef (*IOPSCopyPowerSourcesListFn)(CFTypeRef);
    typedef CFDictionaryRef (*IOPSGetPowerSourceDescriptionFn)(CFTypeRef, CFTypeRef);

    IOPSCopyPowerSourcesInfoFn copyInfo = (IOPSCopyPowerSourcesInfoFn)dlsym(iokit, "IOPSCopyPowerSourcesInfo");
    IOPSCopyPowerSourcesListFn copyList = (IOPSCopyPowerSourcesListFn)dlsym(iokit, "IOPSCopyPowerSourcesList");
    IOPSGetPowerSourceDescriptionFn getDesc = (IOPSGetPowerSourceDescriptionFn)dlsym(iokit, "IOPSGetPowerSourceDescription");

    int pct = -1;
    if (copyInfo && copyList && getDesc) {
        CFTypeRef blob = copyInfo();
        if (blob) {
            CFArrayRef list = copyList(blob);
            if (list) {
                if (CFArrayGetCount(list) > 0) {
                    CFTypeRef ps = CFArrayGetValueAtIndex(list, 0);
                    NSDictionary *desc = (__bridge NSDictionary *)getDesc(blob, ps);
                    NSNumber *cur = desc[@"Current Capacity"];
                    NSNumber *max = desc[@"Max Capacity"];
                    NSNumber *chg = desc[@"Is Charging"];
                    if (outCharging && chg) *outCharging = chg.boolValue;
                    if (cur && max && max.intValue > 0) {
                        pct = (int)lround(((double)cur.intValue / (double)max.intValue) * 100.0);
                    }
                }
                CFRelease(list);
            }
            CFRelease(blob);
        }
    }
    dlclose(iokit);
    return pct;
}

@interface ShieldViewController : UIViewController

@property (nonatomic, strong) UIScrollView *scrollView;

@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UISegmentedControl *modeControl;

@property (nonatomic, strong) UIView *telemetryCard;
@property (nonatomic, strong) UILabel *rTitle;
@property (nonatomic, strong) UILabel *routerPingLabel;
@property (nonatomic, strong) UILabel *iTitle;
@property (nonatomic, strong) UILabel *internetPingLabel;
@property (nonatomic, strong) UILabel *bTitle;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, strong) UILabel *mTitle;
@property (nonatomic, strong) UILabel *ramLabel;
@property (nonatomic, strong) UIButton *purgeButton;

@property (nonatomic, strong) UIView *revivalCard;
@property (nonatomic, strong) UILabel *revivalTitle;
@property (nonatomic, strong) UILabel *turboTitle;
@property (nonatomic, strong) UILabel *turboStatusLabel;
@property (nonatomic, strong) UISwitch *turboSwitch;
@property (nonatomic, strong) UIButton *cleanStorageButton;
@property (nonatomic, strong) UIView *jetsamRow;
@property (nonatomic, strong) UILabel *jIcon;
@property (nonatomic, strong) UILabel *jetsamStatusLabel;

@property (nonatomic, strong) UIView *defCard;
@property (nonatomic, strong) UIButton *cfgBtn;
@property (nonatomic, strong) NSMutableArray<UILabel *> *defTLabels;
@property (nonatomic, strong) NSMutableArray<UILabel *> *defVLabels;

@property (nonatomic, strong) UIView *vipCard;
@property (nonatomic, strong) UILabel *vipTitle;
@property (nonatomic, strong) UILabel *vipList;
@property (nonatomic, strong) UILabel *vipSub;

@property (nonatomic, strong) UIView *daemonCard;
@property (nonatomic, strong) UILabel *bannerTitle;
@property (nonatomic, strong) UILabel *bannerStatusLabel;
@property (nonatomic, strong) UISwitch *bannerSwitch;
@property (nonatomic, strong) UIView *daemonDivider;
@property (nonatomic, strong) UILabel *dTitle;
@property (nonatomic, strong) UILabel *daemonStatusLabel;
@property (nonatomic, strong) UISwitch *daemonSwitch;

@property (nonatomic, strong) UIView *gitCard;
@property (nonatomic, strong) UILabel *gitTitle;
@property (nonatomic, strong) UIButton *gitButton;
@property (nonatomic, strong) UILabel *ghIcon;
@property (nonatomic, strong) UILabel *githubNameLabel;
@property (nonatomic, strong) UILabel *githubSubLabel;
@property (nonatomic, strong) UILabel *arrowLabel;
@property (nonatomic, strong) NSString *githubURL;

@property (nonatomic, strong) UILabel *footerLabel;

@property (nonatomic, strong) NSTimer *telemetryTimer;
@property (nonatomic, copy) NSString *currentGatewayIP;
@property (nonatomic, assign) int notifyToken;

- (void)syncFromSystemState;

@end

@implementation ShieldViewController

- (void)dealloc {
    if (_notifyToken != 0) {
        notify_cancel(_notifyToken);
    }
    [_telemetryTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:1.0];

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    self.githubURL = @"https://github.com/NightKnight24";
    self.currentGatewayIP = @"";

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];

    __weak typeof(self) weakSelf = self;
    int token = 0;
    if (notify_register_dispatch(kStateChangedNotify, &token, dispatch_get_main_queue(), ^(int t) {
        (void)t;
        [weakSelf syncFromSystemState];
    }) == NOTIFY_STATUS_OK) {
        self.notifyToken = token;
    }

    // Header
    self.iconLabel = [[UILabel alloc] init];
    self.iconLabel.text = @"🛡️";
    self.iconLabel.font = [UIFont systemFontOfSize:44];
    self.iconLabel.textAlignment = NSTextAlignmentCenter;
    [self.scrollView addSubview:self.iconLabel];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"Anti-Lag Shield";
    self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.75;
    [self.scrollView addSubview:self.titleLabel];

    self.subLabel = [[UILabel alloc] init];
    self.subLabel.text = @"XNU Socket Buffer & Latency Controller • v1.0.0";
    self.subLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.subLabel.textColor = [UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:0.9];
    self.subLabel.textAlignment = NSTextAlignmentCenter;
    self.subLabel.adjustsFontSizeToFitWidth = YES;
    self.subLabel.minimumScaleFactor = 0.70;
    [self.scrollView addSubview:self.subLabel];

    self.statusBadge = [[UILabel alloc] init];
    self.statusBadge.text = @"●  CHECKING KERNEL STATE";
    self.statusBadge.font = [UIFont boldSystemFontOfSize:12];
    self.statusBadge.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.statusBadge.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.9];
    self.statusBadge.layer.cornerRadius = 16;
    self.statusBadge.clipsToBounds = YES;
    self.statusBadge.textAlignment = NSTextAlignmentCenter;
    self.statusBadge.adjustsFontSizeToFitWidth = YES;
    self.statusBadge.minimumScaleFactor = 0.8;
    [self.scrollView addSubview:self.statusBadge];

    NSArray *items = @[@"Streaming", @"Gaming", @"Normal"];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:items];
    self.modeControl.selectedSegmentIndex = 0;
    if (@available(iOS 13.0, *)) {
        self.modeControl.selectedSegmentTintColor = [UIColor colorWithRed:0.14 green:0.32 blue:0.46 alpha:1.0];
        [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.78 alpha:1.0],
                                                   NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}
                                        forState:UIControlStateNormal];
        [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor],
                                                   NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightBold]}
                                        forState:UIControlStateSelected];
    }
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:self.modeControl];

    // Card 1: Telemetry & RAM
    self.telemetryCard = [[UIView alloc] init];
    self.telemetryCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    self.telemetryCard.layer.cornerRadius = 16;
    self.telemetryCard.layer.borderWidth = 1.0;
    self.telemetryCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:self.telemetryCard];

    self.rTitle = [[UILabel alloc] init];
    self.rTitle.text = @"GATEWAY";
    self.rTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.rTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    self.rTitle.adjustsFontSizeToFitWidth = YES;
    self.rTitle.minimumScaleFactor = 0.7;
    [self.telemetryCard addSubview:self.rTitle];

    self.routerPingLabel = [[UILabel alloc] init];
    self.routerPingLabel.text = @"-- ms";
    self.routerPingLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
    self.routerPingLabel.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
    self.routerPingLabel.adjustsFontSizeToFitWidth = YES;
    self.routerPingLabel.minimumScaleFactor = 0.7;
    [self.telemetryCard addSubview:self.routerPingLabel];

    self.iTitle = [[UILabel alloc] init];
    self.iTitle.text = @"1.1.1.1 RTT";
    self.iTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.iTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    self.iTitle.adjustsFontSizeToFitWidth = YES;
    self.iTitle.minimumScaleFactor = 0.7;
    [self.telemetryCard addSubview:self.iTitle];

    self.internetPingLabel = [[UILabel alloc] init];
    self.internetPingLabel.text = @"-- ms";
    self.internetPingLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
    self.internetPingLabel.textColor = [UIColor colorWithRed:0.75 green:0.45 blue:1.0 alpha:1.0];
    self.internetPingLabel.adjustsFontSizeToFitWidth = YES;
    self.internetPingLabel.minimumScaleFactor = 0.7;
    [self.telemetryCard addSubview:self.internetPingLabel];

    self.bTitle = [[UILabel alloc] init];
    self.bTitle.text = @"BATTERY";
    self.bTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.bTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    self.bTitle.adjustsFontSizeToFitWidth = YES;
    self.bTitle.minimumScaleFactor = 0.7;
    [self.telemetryCard addSubview:self.bTitle];

    self.batteryLabel = [[UILabel alloc] init];
    self.batteryLabel.text = @"--";
    self.batteryLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
    self.batteryLabel.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
    self.batteryLabel.adjustsFontSizeToFitWidth = YES;
    self.batteryLabel.minimumScaleFactor = 0.7;
    [self.telemetryCard addSubview:self.batteryLabel];

    self.mTitle = [[UILabel alloc] init];
    self.mTitle.text = @"FREE RAM";
    self.mTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.mTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    self.mTitle.adjustsFontSizeToFitWidth = YES;
    self.mTitle.minimumScaleFactor = 0.7;
    [self.telemetryCard addSubview:self.mTitle];

    self.ramLabel = [[UILabel alloc] init];
    self.ramLabel.text = @"-- MB";
    self.ramLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
    self.ramLabel.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.55 alpha:1.0];
    self.ramLabel.adjustsFontSizeToFitWidth = YES;
    self.ramLabel.minimumScaleFactor = 0.7;
    [self.telemetryCard addSubview:self.ramLabel];

    self.purgeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.purgeButton setTitle:@"Purge Inactive Memory Pages" forState:UIControlStateNormal];
    self.purgeButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.purgeButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.purgeButton.titleLabel.minimumScaleFactor = 0.8;
    [self.purgeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.purgeButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.28 blue:0.20 alpha:0.9];
    self.purgeButton.layer.cornerRadius = 12;
    self.purgeButton.layer.borderWidth = 1.0;
    self.purgeButton.layer.borderColor = [UIColor colorWithRed:0.25 green:0.65 blue:0.4 alpha:0.5].CGColor;
    [self.purgeButton addTarget:self action:@selector(purgeRAMTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.telemetryCard addSubview:self.purgeButton];

    // Card 2: UI Acceleration & Storage
    self.revivalCard = [[UIView alloc] init];
    self.revivalCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    self.revivalCard.layer.cornerRadius = 16;
    self.revivalCard.layer.borderWidth = 1.0;
    self.revivalCard.layer.borderColor = [UIColor colorWithRed:0.20 green:0.28 blue:0.38 alpha:1.0].CGColor;
    [self.scrollView addSubview:self.revivalCard];

    self.revivalTitle = [[UILabel alloc] init];
    self.revivalTitle.text = @"COMPOSITOR & STORAGE MAINTENANCE";
    self.revivalTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.revivalTitle.textColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0];
    self.revivalTitle.adjustsFontSizeToFitWidth = YES;
    self.revivalTitle.minimumScaleFactor = 0.75;
    [self.revivalCard addSubview:self.revivalTitle];

    self.turboTitle = [[UILabel alloc] init];
    self.turboTitle.text = @"Turbo UI (Disable SpringBoard Blur & Motion)";
    self.turboTitle.font = [UIFont boldSystemFontOfSize:14];
    self.turboTitle.textColor = [UIColor whiteColor];
    self.turboTitle.adjustsFontSizeToFitWidth = YES;
    self.turboTitle.minimumScaleFactor = 0.75;
    [self.revivalCard addSubview:self.turboTitle];

    self.turboStatusLabel = [[UILabel alloc] init];
    self.turboStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.turboStatusLabel.numberOfLines = 2;
    self.turboStatusLabel.adjustsFontSizeToFitWidth = YES;
    self.turboStatusLabel.minimumScaleFactor = 0.75;
    [self.revivalCard addSubview:self.turboStatusLabel];

    self.turboSwitch = [[UISwitch alloc] init];
    [self.turboSwitch addTarget:self action:@selector(turboSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.revivalCard addSubview:self.turboSwitch];
    [self refreshTurboUIState];

    self.cleanStorageButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cleanStorageButton setTitle:@"Clear Diagnostic Logs & Expired Caches" forState:UIControlStateNormal];
    self.cleanStorageButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.cleanStorageButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.cleanStorageButton.titleLabel.minimumScaleFactor = 0.75;
    [self.cleanStorageButton setTitleColor:[UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    self.cleanStorageButton.backgroundColor = [UIColor colorWithRed:0.10 green:0.18 blue:0.26 alpha:0.9];
    self.cleanStorageButton.layer.cornerRadius = 12;
    self.cleanStorageButton.layer.borderWidth = 1.0;
    self.cleanStorageButton.layer.borderColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.7 alpha:0.4].CGColor;
    [self.cleanStorageButton addTarget:self action:@selector(cleanStorageTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.revivalCard addSubview:self.cleanStorageButton];

    self.jetsamRow = [[UIView alloc] init];
    self.jetsamRow.backgroundColor = [UIColor colorWithRed:0.05 green:0.07 blue:0.10 alpha:0.8];
    self.jetsamRow.layer.cornerRadius = 10;
    [self.revivalCard addSubview:self.jetsamRow];

    self.jIcon = [[UILabel alloc] init];
    self.jIcon.text = @"•";
    self.jIcon.font = [UIFont boldSystemFontOfSize:20];
    self.jIcon.textAlignment = NSTextAlignmentCenter;
    self.jIcon.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
    [self.jetsamRow addSubview:self.jIcon];

    self.jetsamStatusLabel = [[UILabel alloc] init];
    self.jetsamStatusLabel.numberOfLines = 2;
    self.jetsamStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.jetsamStatusLabel.adjustsFontSizeToFitWidth = YES;
    self.jetsamStatusLabel.minimumScaleFactor = 0.75;
    [self.jetsamRow addSubview:self.jetsamStatusLabel];

    // Card 3: Live XNU Kernel Parameters
    self.defCard = [[UIView alloc] init];
    self.defCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    self.defCard.layer.cornerRadius = 16;
    self.defCard.layer.borderWidth = 1.0;
    self.defCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:self.defCard];

    self.cfgBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cfgBtn setTitle:@"Gateway Config" forState:UIControlStateNormal];
    self.cfgBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.cfgBtn.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.cfgBtn.titleLabel.minimumScaleFactor = 0.75;
    [self.cfgBtn setTitleColor:[UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    self.cfgBtn.backgroundColor = [UIColor colorWithRed:0.08 green:0.22 blue:0.28 alpha:0.8];
    self.cfgBtn.layer.cornerRadius = 8;
    [self.cfgBtn addTarget:self action:@selector(configGatewayTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.defCard addSubview:self.cfgBtn];

    self.defTLabels = [NSMutableArray array];
    self.defVLabels = [NSMutableArray array];
    NSArray<NSString *> *rowTitles = @[
        @"Gateway ARP Table",
        @"TCP Delayed ACK (net.inet.tcp.delayed_ack)",
        @"TCP Segmentation Offload (net.inet.tcp.tso)",
        @"Socket Auto-Buffers (autorcvbufmax / recvspace)",
        @"Listen Backlog (kern.ipc.somaxconn)",
        @"ICMP Redirect & Port Blackhole",
        @"Radio Coexistence (awdl0 & Wi-Fi QoS)"
    ];

    for (NSString *title in rowTitles) {
        UILabel *tLbl = [[UILabel alloc] init];
        tLbl.text = title;
        tLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        tLbl.textColor = [UIColor colorWithWhite:0.52 alpha:1.0];
        tLbl.adjustsFontSizeToFitWidth = YES;
        tLbl.minimumScaleFactor = 0.75;
        [self.defCard addSubview:tLbl];
        [self.defTLabels addObject:tLbl];

        UILabel *vLbl = [[UILabel alloc] init];
        vLbl.text = @"Reading kernel...";
        vLbl.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
        vLbl.textColor = [UIColor whiteColor];
        vLbl.adjustsFontSizeToFitWidth = YES;
        vLbl.minimumScaleFactor = 0.75;
        [self.defCard addSubview:vLbl];
        [self.defVLabels addObject:vLbl];
    }

    // Card 4: Process Scheduler Priority
    self.vipCard = [[UIView alloc] init];
    self.vipCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    self.vipCard.layer.cornerRadius = 16;
    self.vipCard.layer.borderWidth = 1.0;
    self.vipCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:self.vipCard];

    self.vipTitle = [[UILabel alloc] init];
    self.vipTitle.text = @"PROCESS SCHEDULING PRIORITY (setpriority)";
    self.vipTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.vipTitle.textColor = [UIColor colorWithWhite:0.52 alpha:1.0];
    self.vipTitle.adjustsFontSizeToFitWidth = YES;
    self.vipTitle.minimumScaleFactor = 0.75;
    [self.vipCard addSubview:self.vipTitle];

    self.vipList = [[UILabel alloc] init];
    self.vipList.text = @"Media (-10): mediaserverd, coreaudiod, WebKit, Stremio, YouTube, Netflix, Disney+, Prime Video\nGaming (-10): gamecontrollerd, Moonlight, SteamLink, RetroArch, Delta, Roblox, Minecraft\nBackground (+10): cloudd, nsurlsessiond, appstored, triald, photoanalysisd";
    self.vipList.numberOfLines = 0;
    self.vipList.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.vipList.textColor = [UIColor colorWithRed:0.85 green:0.9 blue:1.0 alpha:0.9];
    self.vipList.adjustsFontSizeToFitWidth = YES;
    self.vipList.minimumScaleFactor = 0.75;
    [self.vipCard addSubview:self.vipList];

    self.vipSub = [[UILabel alloc] init];
    self.vipSub.text = @"Checking scheduler policy...";
    self.vipSub.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.vipSub.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.45 alpha:0.9];
    self.vipSub.adjustsFontSizeToFitWidth = YES;
    self.vipSub.minimumScaleFactor = 0.75;
    [self.vipCard addSubview:self.vipSub];

    // Card 5: Notification Bar Banner & Boot Persistence
    self.daemonCard = [[UIView alloc] init];
    self.daemonCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    self.daemonCard.layer.cornerRadius = 16;
    self.daemonCard.layer.borderWidth = 1.0;
    self.daemonCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:self.daemonCard];

    self.bannerTitle = [[UILabel alloc] init];
    self.bannerTitle.text = @"Notification Bar Banner";
    self.bannerTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    self.bannerTitle.textColor = [UIColor whiteColor];
    self.bannerTitle.adjustsFontSizeToFitWidth = YES;
    self.bannerTitle.minimumScaleFactor = 0.75;
    [self.daemonCard addSubview:self.bannerTitle];

    self.bannerStatusLabel = [[UILabel alloc] init];
    self.bannerStatusLabel.text = @"Pinned in Notification Center: Streaming, Gaming, Normal, RAM & Cache.";
    self.bannerStatusLabel.numberOfLines = 2;
    self.bannerStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.bannerStatusLabel.textColor = [UIColor colorWithRed:0.2 green:0.95 blue:0.4 alpha:1.0];
    self.bannerStatusLabel.adjustsFontSizeToFitWidth = YES;
    self.bannerStatusLabel.minimumScaleFactor = 0.75;
    [self.daemonCard addSubview:self.bannerStatusLabel];

    self.bannerSwitch = [[UISwitch alloc] init];
    self.bannerSwitch.on = YES;
    [self.bannerSwitch addTarget:self action:@selector(bannerSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.daemonCard addSubview:self.bannerSwitch];

    self.daemonDivider = [[UIView alloc] init];
    self.daemonDivider.backgroundColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:0.9];
    [self.daemonCard addSubview:self.daemonDivider];

    self.dTitle = [[UILabel alloc] init];
    self.dTitle.text = @"Apply Profile at Boot (LaunchDaemon)";
    self.dTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    self.dTitle.textColor = [UIColor whiteColor];
    self.dTitle.adjustsFontSizeToFitWidth = YES;
    self.dTitle.minimumScaleFactor = 0.75;
    [self.daemonCard addSubview:self.dTitle];

    self.daemonStatusLabel = [[UILabel alloc] init];
    self.daemonStatusLabel.text = @"Off: Profile only applies when toggled manually.";
    self.daemonStatusLabel.numberOfLines = 2;
    self.daemonStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.daemonStatusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    self.daemonStatusLabel.adjustsFontSizeToFitWidth = YES;
    self.daemonStatusLabel.minimumScaleFactor = 0.75;
    [self.daemonCard addSubview:self.daemonStatusLabel];

    self.daemonSwitch = [[UISwitch alloc] init];
    [self.daemonSwitch addTarget:self action:@selector(daemonSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.daemonCard addSubview:self.daemonSwitch];

    // Card 6: Source Repository
    self.gitCard = [[UIView alloc] init];
    self.gitCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    self.gitCard.layer.cornerRadius = 16;
    self.gitCard.layer.borderWidth = 1.0;
    self.gitCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:self.gitCard];

    self.gitTitle = [[UILabel alloc] init];
    self.gitTitle.text = @"OPEN SOURCE REPOSITORY";
    self.gitTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.gitTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    self.gitTitle.adjustsFontSizeToFitWidth = YES;
    self.gitTitle.minimumScaleFactor = 0.75;
    [self.gitCard addSubview:self.gitTitle];

    self.gitButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.gitButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.15 blue:0.22 alpha:0.95];
    self.gitButton.layer.cornerRadius = 12;
    self.gitButton.layer.borderWidth = 1.0;
    self.gitButton.layer.borderColor = [UIColor colorWithRed:0.22 green:0.35 blue:0.52 alpha:0.5].CGColor;
    [self.gitButton addTarget:self action:@selector(openGitHubTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.gitCard addSubview:self.gitButton];

    self.ghIcon = [[UILabel alloc] init];
    self.ghIcon.text = @"</>";
    if (@available(iOS 13.0, *)) {
        self.ghIcon.font = [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightBold];
    } else {
        self.ghIcon.font = [UIFont fontWithName:@"Menlo-Bold" size:18] ?: [UIFont boldSystemFontOfSize:18];
    }
    self.ghIcon.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
    self.ghIcon.textAlignment = NSTextAlignmentCenter;
    [self.gitButton addSubview:self.ghIcon];

    self.githubNameLabel = [[UILabel alloc] init];
    self.githubNameLabel.text = @"NightKnight24 (GitHub)";
    self.githubNameLabel.font = [UIFont boldSystemFontOfSize:15];
    self.githubNameLabel.textColor = [UIColor whiteColor];
    self.githubNameLabel.adjustsFontSizeToFitWidth = YES;
    self.githubNameLabel.minimumScaleFactor = 0.75;
    [self.gitButton addSubview:self.githubNameLabel];

    self.githubSubLabel = [[UILabel alloc] init];
    self.githubSubLabel.text = @"github.com/NightKnight24/AntiLagShield • MIT License";
    self.githubSubLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.githubSubLabel.textColor = [UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:0.9];
    self.githubSubLabel.adjustsFontSizeToFitWidth = YES;
    self.githubSubLabel.minimumScaleFactor = 0.75;
    [self.gitButton addSubview:self.githubSubLabel];

    self.arrowLabel = [[UILabel alloc] init];
    self.arrowLabel.text = @"Open ↗";
    self.arrowLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    self.arrowLabel.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
    self.arrowLabel.textAlignment = NSTextAlignmentRight;
    self.arrowLabel.adjustsFontSizeToFitWidth = YES;
    self.arrowLabel.minimumScaleFactor = 0.75;
    [self.gitButton addSubview:self.arrowLabel];

    UILongPressGestureRecognizer *ghPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(gitButtonLongPressed:)];
    [self.gitButton addGestureRecognizer:ghPress];

    self.footerLabel = [[UILabel alloc] init];
    self.footerLabel.text = @"Anti-Lag Shield v1.0.0 • NightKnight24";
    self.footerLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.footerLabel.textColor = [UIColor colorWithWhite:0.42 alpha:1.0];
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel.adjustsFontSizeToFitWidth = YES;
    self.footerLabel.minimumScaleFactor = 0.75;
    [self.scrollView addSubview:self.footerLabel];

    [self updateRAM];
    [self updateBattery];
    [self refreshKernelSysctlLabels];
    [self syncFromSystemState];

    self.telemetryTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                           target:self
                                                         selector:@selector(refreshTelemetry)
                                                         userInfo:nil
                                                          repeats:YES];
    [self refreshTelemetry];
}

- (void)appWillEnterForeground {
    [self refreshTurboUIState];
    [self syncFromSystemState];
    [self refreshTelemetry];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.scrollView.frame = self.view.bounds;
    [self relayoutUI];
}

- (void)relayoutUI {
    CGFloat width = self.view.bounds.size.width;
    if (width <= 0) return;

    CGFloat contentW = MIN(width - 32.0, 680.0);
    CGFloat startX = (width - contentW) / 2.0;
    CGFloat y = 36.0;

    self.iconLabel.frame = CGRectMake(startX, y, contentW, 46);
    y += 50;

    self.titleLabel.frame = CGRectMake(startX, y, contentW, 28);
    y += 30;

    self.subLabel.frame = CGRectMake(startX, y, contentW, 20);
    y += 28;

    CGFloat badgeW = MIN(contentW - 32.0, 270.0);
    self.statusBadge.frame = CGRectMake(startX + (contentW - badgeW) / 2.0, y, badgeW, 32);
    y += 42;

    self.modeControl.frame = CGRectMake(startX, y, contentW, 38);
    y += 48;

    BOOL isNarrow = (contentW < 440.0);
    CGFloat telemetryH = isNarrow ? 178.0 : 140.0;
    self.telemetryCard.frame = CGRectMake(startX, y, contentW, telemetryH);

    if (isNarrow) {
        CGFloat colW = (contentW - 32.0) / 2.0;
        self.rTitle.frame = CGRectMake(12, 12, colW, 16);
        self.routerPingLabel.frame = CGRectMake(12, 28, colW, 24);

        self.iTitle.frame = CGRectMake(20 + colW, 12, colW, 16);
        self.internetPingLabel.frame = CGRectMake(20 + colW, 28, colW, 24);

        self.bTitle.frame = CGRectMake(12, 60, colW, 16);
        self.batteryLabel.frame = CGRectMake(12, 76, colW, 24);

        self.mTitle.frame = CGRectMake(20 + colW, 60, colW, 16);
        self.ramLabel.frame = CGRectMake(20 + colW, 76, colW, 24);

        self.purgeButton.frame = CGRectMake(12, 114, contentW - 24, 46);
    } else {
        CGFloat colW = (contentW - 50.0) / 4.0;
        self.rTitle.frame = CGRectMake(12, 14, colW, 18);
        self.routerPingLabel.frame = CGRectMake(12, 34, colW, 26);

        self.iTitle.frame = CGRectMake(16 + colW, 14, colW, 18);
        self.internetPingLabel.frame = CGRectMake(16 + colW, 34, colW, 26);

        self.bTitle.frame = CGRectMake(20 + colW * 2, 14, colW, 18);
        self.batteryLabel.frame = CGRectMake(20 + colW * 2, 34, colW, 26);

        self.mTitle.frame = CGRectMake(24 + colW * 3, 14, colW, 18);
        self.ramLabel.frame = CGRectMake(24 + colW * 3, 34, colW, 26);

        self.purgeButton.frame = CGRectMake(12, 76, contentW - 24, 48);
    }
    y += telemetryH + 14.0;

    CGFloat revivalH = 214.0;
    self.revivalCard.frame = CGRectMake(startX, y, contentW, revivalH);
    self.revivalTitle.frame = CGRectMake(16, 12, contentW - 32, 16);
    self.turboTitle.frame = CGRectMake(16, 34, contentW - 85, 20);
    self.turboStatusLabel.frame = CGRectMake(16, 56, contentW - 85, 34);
    self.turboSwitch.frame = CGRectMake(contentW - 65, 38, 51, 31);
    self.cleanStorageButton.frame = CGRectMake(12, 98, contentW - 24, 46);
    self.jetsamRow.frame = CGRectMake(12, 154, contentW - 24, 48);
    self.jIcon.frame = CGRectMake(10, 12, 22, 24);
    self.jetsamStatusLabel.frame = CGRectMake(34, 5, contentW - 70, 38);
    y += revivalH + 14.0;

    CGFloat cfgW = isNarrow ? 98.0 : 120.0;
    self.cfgBtn.frame = CGRectMake(contentW - cfgW - 12.0, 8, cfgW, 26);

    CGFloat defH = 12.0 + (self.defTLabels.count * 43.0) + 8.0;
    self.defCard.frame = CGRectMake(startX, y, contentW, defH);

    CGFloat dy = 10.0;
    for (NSUInteger i = 0; i < self.defTLabels.count; i++) {
        UILabel *tLbl = self.defTLabels[i];
        UILabel *vLbl = self.defVLabels[i];
        CGFloat rightLimit = (i == 0) ? (contentW - cfgW - 24.0) : (contentW - 32.0);
        tLbl.frame = CGRectMake(16, dy, rightLimit, 15);
        vLbl.frame = CGRectMake(16, dy + 15, contentW - 32.0, 18);
        dy += 43.0;
    }
    y += defH + 14.0;

    CGFloat vipH = isNarrow ? 156.0 : 134.0;
    self.vipCard.frame = CGRectMake(startX, y, contentW, vipH);
    self.vipTitle.frame = CGRectMake(16, 12, contentW - 32, 16);
    self.vipList.frame = CGRectMake(16, 32, contentW - 32, isNarrow ? 88 : 68);
    self.vipSub.frame = CGRectMake(16, isNarrow ? 124 : 104, contentW - 32, 20);
    y += vipH + 14.0;

    CGFloat daemonH = 152.0;
    self.daemonCard.frame = CGRectMake(startX, y, contentW, daemonH);
    self.bannerTitle.frame = CGRectMake(16, 14, contentW - 85, 20);
    self.bannerStatusLabel.frame = CGRectMake(16, 36, contentW - 85, 32);
    self.bannerSwitch.frame = CGRectMake(contentW - 65, 24, 51, 31);
    self.daemonDivider.frame = CGRectMake(16, 76, contentW - 32, 1);
    self.dTitle.frame = CGRectMake(16, 86, contentW - 85, 20);
    self.daemonStatusLabel.frame = CGRectMake(16, 108, contentW - 85, 32);
    self.daemonSwitch.frame = CGRectMake(contentW - 65, 96, 51, 31);
    y += daemonH + 14.0;

    CGFloat gitH = 114.0;
    self.gitCard.frame = CGRectMake(startX, y, contentW, gitH);
    self.gitTitle.frame = CGRectMake(16, 12, contentW - 32, 16);

    CGFloat gBtnW = contentW - 24.0;
    self.gitButton.frame = CGRectMake(12, 34, gBtnW, 66);
    self.ghIcon.frame = CGRectMake(10, 13, 44, 40);

    CGFloat arrowW = isNarrow ? 32.0 : 72.0;
    self.arrowLabel.text = isNarrow ? @"↗" : @"Open ↗";
    self.arrowLabel.frame = CGRectMake(gBtnW - arrowW - 12.0, 22, arrowW, 22);

    CGFloat textW = gBtnW - 60.0 - arrowW - 16.0;
    self.githubNameLabel.frame = CGRectMake(58, 12, textW, 22);
    self.githubSubLabel.frame = CGRectMake(58, 36, textW, 18);
    y += gitH + 14.0;

    self.footerLabel.frame = CGRectMake(startX, y, contentW, 20);
    y += 35.0;

    self.scrollView.contentSize = CGSizeMake(width, y + 30.0);
}

- (void)refreshTurboUIState {
    BOOL isOn = get_turbo_ui_status();
    self.turboSwitch.on = isOn;
    if (isOn) {
        self.turboStatusLabel.text = @"Enabled: Reduce Motion & Contrast active in SpringBoard.";
        self.turboStatusLabel.textColor = [UIColor colorWithRed:0.2 green:0.95 blue:0.4 alpha:1.0];
    } else {
        self.turboStatusLabel.text = @"Disabled: Standard SpringBoard blur & motion animations.";
        self.turboStatusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    }
}

- (void)refreshKernelSysctlLabels {
    if (self.defVLabels.count < 7) return;

    // 1. TCP Delayed ACK
    int delayedAck = -1;
    if (read_sysctl_int("net.inet.tcp.delayed_ack", &delayedAck)) {
        if (delayedAck == 0) {
            self.defVLabels[1].text = @"0 — Immediate ACK (0 ms Delay)";
            self.defVLabels[1].textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
        } else if (delayedAck == 3) {
            self.defVLabels[1].text = @"3 — Adaptive RFC 5681";
            self.defVLabels[1].textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
        } else {
            self.defVLabels[1].text = [NSString stringWithFormat:@"%d", delayedAck];
            self.defVLabels[1].textColor = [UIColor whiteColor];
        }
    } else {
        self.defVLabels[1].text = @"Unavailable";
    }

    // 2. TCP Segmentation Offload
    int tso = -1;
    if (read_sysctl_int("net.inet.tcp.tso", &tso)) {
        if (tso == 1) {
            self.defVLabels[2].text = @"Enabled (tso = 1)";
            self.defVLabels[2].textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
        } else {
            self.defVLabels[2].text = @"Disabled (tso = 0, Low-Jitter)";
            self.defVLabels[2].textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
        }
    }

    // 3. Socket Buffers
    int autoRcvMax = 0, rcvSpace = 0;
    if (read_sysctl_int("net.inet.tcp.autorcvbufmax", &autoRcvMax) &&
        read_sysctl_int("net.inet.tcp.recvspace", &rcvSpace)) {
        double maxMB = (double)autoRcvMax / (1024.0 * 1024.0);
        int initKB = rcvSpace / 1024;
        self.defVLabels[3].text = [NSString stringWithFormat:@"%.1f MB Max Auto-Buffer (%d KB Initial)", maxMB, initKB];
        self.defVLabels[3].textColor = (autoRcvMax >= 4194304)
            ? [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0]
            : [UIColor whiteColor];
    }

    // 4. Listen Queue Backlog
    int somaxconn = 0;
    if (read_sysctl_int("kern.ipc.somaxconn", &somaxconn)) {
        self.defVLabels[4].text = [NSString stringWithFormat:@"%d Sockets", somaxconn];
        self.defVLabels[4].textColor = (somaxconn >= 512)
            ? [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0]
            : [UIColor colorWithWhite:0.75 alpha:1.0];
    }

    // 5. Blackhole & ICMP Redirect
    int tcpBh = 0, dropRedir = 0;
    if (read_sysctl_int("net.inet.tcp.blackhole", &tcpBh) &&
        read_sysctl_int("net.inet.icmp.drop_redirect", &dropRedir)) {
        if (tcpBh > 0 && dropRedir > 0) {
            self.defVLabels[5].text = [NSString stringWithFormat:@"Active (tcp.blackhole = %d, drop_redirect = 1)", tcpBh];
            self.defVLabels[5].textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
        } else {
            self.defVLabels[5].text = @"Disabled (Stock iOS Stack)";
            self.defVLabels[5].textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        }
    }

    // 6. Radio Coexistence (awdl0 + Wi-Fi QoS)
    BOOL awdlExists = NO;
    BOOL awdlUp = is_interface_up("awdl0", &awdlExists);
    int wifiQos = 0;
    read_sysctl_int("net.qos.policy.wifi_enabled", &wifiQos);
    if (awdlExists && !awdlUp) {
        self.defVLabels[6].text = [NSString stringWithFormat:@"awdl0 Paused (No Scan Stutter) • QoS Policy %d", wifiQos];
        self.defVLabels[6].textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
    } else if (awdlExists) {
        self.defVLabels[6].text = @"awdl0 Active (Standard AirDrop Radio)";
        self.defVLabels[6].textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    } else {
        self.defVLabels[6].text = [NSString stringWithFormat:@"Wi-Fi QoS Policy = %d", wifiQos];
    }

    // Card 2 Memorystatus Row
    int purgeOnWarn = 1;
    if (read_sysctl_int("kern.memorystatus_purge_on_warning", &purgeOnWarn)) {
        if (purgeOnWarn == 0) {
            self.jIcon.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
            self.jetsamStatusLabel.text = @"Memorystatus Warning Purge Disabled (purge_on_warning = 0)\nPrevents XNU from flushing cached app pages on memory warning.";
            self.jetsamStatusLabel.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
        } else {
            self.jIcon.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
            self.jetsamStatusLabel.text = @"Stock XNU Memorystatus Policy (purge_on_warning = 1)\nStandard iOS cache eviction on memory pressure.";
            self.jetsamStatusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        }
    }
}

- (void)applyStatusBadgeForMode:(NSString *)mode bootDaemon:(BOOL)bootDaemon {
    if ([mode isEqualToString:@"streaming"]) {
        self.modeControl.selectedSegmentIndex = 0;
        self.statusBadge.text = bootDaemon ? @"●  STREAMING ACTIVE (BOOT)" : @"●  STREAMING PROFILE ACTIVE";
        self.statusBadge.textColor = [UIColor colorWithRed:0.2 green:0.95 blue:0.4 alpha:1.0];
        self.statusBadge.backgroundColor = [UIColor colorWithRed:0.06 green:0.22 blue:0.12 alpha:0.9];
        self.vipSub.text = @"Active media & streaming processes prioritized at nice -10.";
        self.vipSub.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.45 alpha:0.9];
    } else if ([mode isEqualToString:@"gaming"]) {
        self.modeControl.selectedSegmentIndex = 1;
        self.statusBadge.text = bootDaemon ? @"●  GAMING ACTIVE (BOOT)" : @"●  GAMING PROFILE ACTIVE";
        self.statusBadge.textColor = [UIColor colorWithRed:1.0 green:0.68 blue:0.2 alpha:1.0];
        self.statusBadge.backgroundColor = [UIColor colorWithRed:0.24 green:0.16 blue:0.05 alpha:0.9];
        self.vipSub.text = @"Active game & controller processes prioritized at nice -10.";
        self.vipSub.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.45 alpha:0.9];
    } else {
        self.modeControl.selectedSegmentIndex = 2;
        self.statusBadge.text = @"●  NORMAL MODE (STOCK XNU)";
        self.statusBadge.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        self.statusBadge.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.9];
        self.vipSub.text = @"Normal Mode: Processes running at stock iOS priority (nice 0).";
        self.vipSub.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    }
}

- (void)syncFromSystemState {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int code = 0;
        NSString *out = run_exec_capture(shield_ctl_bin(), @[@"status", @"--detail"], &code);

        NSString *mode = @"off";
        NSString *iface = @"en0";
        NSString *ip = @"";
        NSString *mac = @"";
        NSString *gh = @"";
        BOOL arpPerm = NO;
        BOOL bootDaemon = NO;
        BOOL bannerEnabled = YES;

        for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"MODE="]) {
                mode = [line substringFromIndex:5];
            } else if ([line hasPrefix:@"INTERFACE="]) {
                iface = [line substringFromIndex:10];
            } else if ([line hasPrefix:@"ROUTER_IP="]) {
                ip = [line substringFromIndex:10];
            } else if ([line hasPrefix:@"ROUTER_MAC="]) {
                mac = [line substringFromIndex:11];
            } else if ([line hasPrefix:@"ARP_PERMANENT="]) {
                arpPerm = [[line substringFromIndex:14] intValue] == 1;
            } else if ([line hasPrefix:@"BOOT_DAEMON="]) {
                bootDaemon = [[line substringFromIndex:12] intValue] == 1;
            } else if ([line hasPrefix:@"BANNER_ENABLED="]) {
                bannerEnabled = [[line substringFromIndex:15] intValue] == 1;
            } else if ([line hasPrefix:@"GITHUB_URL="]) {
                gh = [line substringFromIndex:11];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentGatewayIP = ip;

            if (gh.length > 0) {
                self.githubURL = gh;
                if ([gh containsString:@"github.com/"]) {
                    NSString *tail = [gh componentsSeparatedByString:@"github.com/"].lastObject;
                    NSString *user = [tail componentsSeparatedByString:@"/"].firstObject;
                    if (user.length > 0) {
                        self.githubNameLabel.text = [NSString stringWithFormat:@"%@ (GitHub)", user];
                    }
                }
            }

            if (self.defVLabels.count > 0) {
                if (ip.length > 0 && mac.length > 0 && arpPerm) {
                    self.defVLabels[0].text = [NSString stringWithFormat:@"Static Lock: %@ (%@) on %@", ip, mac, iface];
                    self.defVLabels[0].textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
                } else if (ip.length > 0) {
                    self.defVLabels[0].text = [NSString stringWithFormat:@"Dynamic ARP: %@ on %@", ip, iface];
                    self.defVLabels[0].textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
                } else {
                    self.defVLabels[0].text = @"No Default Gateway Detected";
                    self.defVLabels[0].textColor = [UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0];
                }
            }

            self.bannerSwitch.on = bannerEnabled;
            if (bannerEnabled) {
                self.bannerStatusLabel.text = @"Pinned in Notification Center: Streaming, Gaming, Normal, RAM & Cache.";
                self.bannerStatusLabel.textColor = [UIColor colorWithRed:0.2 green:0.95 blue:0.4 alpha:1.0];
            } else {
                self.bannerStatusLabel.text = @"Hidden: Enable to pin quick controls inside Notification Center.";
                self.bannerStatusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
            }

            self.daemonSwitch.on = bootDaemon;
            if (bootDaemon) {
                self.daemonStatusLabel.text = @"Enabled: LaunchDaemon applies profile once at boot (0% idle CPU).";
                self.daemonStatusLabel.textColor = [UIColor colorWithRed:0.2 green:0.95 blue:0.4 alpha:1.0];
            } else {
                self.daemonStatusLabel.text = @"Off: Profile only applies when toggled manually.";
                self.daemonStatusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
            }

            [self applyStatusBadgeForMode:mode bootDaemon:bootDaemon];
            [self refreshKernelSysctlLabels];
        });
    });
}

- (void)modeChanged:(UISegmentedControl *)sender {
    NSInteger idx = sender.selectedSegmentIndex;
    sender.enabled = NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int code = 0;
        NSString *out = nil;
        if (idx == 0) {
            out = run_exec_capture(shield_ctl_bin(), @[@"start", @"streaming"], &code);
        } else if (idx == 1) {
            out = run_exec_capture(shield_ctl_bin(), @[@"start", @"gaming"], &code);
        } else {
            out = run_exec_capture(shield_ctl_bin(), @[@"stop"], &code);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            if (code != 0) {
                UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Kernel Update Failed"
                                                                                  message:(out.length > 0 ? out : @"shield_ctl returned a non-zero exit code.")
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errAlert animated:YES completion:nil];
            }
            [self syncFromSystemState];
        });
    });
}

- (void)bannerSwitchChanged:(UISwitch *)sender {
    BOOL wantEnabled = sender.isOn;
    sender.enabled = NO;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int code = 0;
        run_exec_capture(shield_ctl_bin(), @[@"banner", wantEnabled ? @"enable" : @"disable"], &code);
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            [self syncFromSystemState];
        });
    });
}

- (void)configGatewayTapped:(UIButton *)sender {
    (void)sender;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Gateway ARP Configuration"
                                                                   message:@"Leave on Automatic to discover the active router on any Wi-Fi network, or specify a static IPv4 and MAC override."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Gateway IPv4 (e.g. 192.168.1.1)";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Gateway MAC (e.g. aa:bb:cc:dd:ee:ff)";
        textField.keyboardType = UIKeyboardTypeASCIICapable;
    }];

    UIAlertAction *autoAction = [UIAlertAction actionWithTitle:@"Automatic Detection" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        (void)action;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            int code = 0;
            run_exec_capture(shield_ctl_bin(), @[@"config", @"auto"], &code);
            if (self.modeControl.selectedSegmentIndex != 2) {
                NSString *m = (self.modeControl.selectedSegmentIndex == 1) ? @"gaming" : @"streaming";
                run_exec_capture(shield_ctl_bin(), @[@"start", m], &code);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [self syncFromSystemState];
            });
        });
    }];

    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save Override" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        (void)action;
        NSString *ip = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *mac = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (ip.length == 0 || mac.length == 0) return;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            int code = 0;
            NSString *res = run_exec_capture(shield_ctl_bin(), @[@"config", @"set", ip, mac], &code);
            if (code == 0 && self.modeControl.selectedSegmentIndex != 2) {
                NSString *m = (self.modeControl.selectedSegmentIndex == 1) ? @"gaming" : @"streaming";
                run_exec_capture(shield_ctl_bin(), @[@"start", m], &code);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (code != 0) {
                    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"Invalid Address"
                                                                                 message:(res.length > 0 ? res : @"Enter a valid IPv4 address and 6-byte colon-separated MAC.")
                                                                          preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:err animated:YES completion:nil];
                }
                [self syncFromSystemState];
            });
        });
    }];

    [alert addAction:autoAction];
    [alert addAction:saveAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openGitHubTapped:(UIButton *)sender {
    (void)sender;
    NSString *urlStr = (self.githubURL.length > 0) ? self.githubURL : @"https://github.com/NightKnight24";
    if (![urlStr hasPrefix:@"http://"] && ![urlStr hasPrefix:@"https://"]) {
        urlStr = [NSString stringWithFormat:@"https://github.com/%@", urlStr];
    }
    NSURL *url = [NSURL URLWithString:urlStr];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)gitButtonLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Repository URL"
                                                                   message:@"Configure the GitHub URL opened by this card:"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = (self.githubURL.length > 0) ? self.githubURL : @"https://github.com/NightKnight24";
        textField.placeholder = @"https://github.com/username";
        textField.keyboardType = UIKeyboardTypeURL;
    }];

    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        (void)action;
        NSString *newUrl = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newUrl.length > 0) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                int code = 0;
                run_exec_capture(shield_ctl_bin(), @[@"config", @"set-github", newUrl], &code);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self syncFromSystemState];
                });
            });
        }
    }];

    [alert addAction:saveAction];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)purgeRAMTapped:(UIButton *)sender {
    sender.enabled = NO;
    NSUInteger beforeMB = get_available_memory_mb();
    [sender setTitle:@"Purging Inactive Memory..." forState:UIControlStateNormal];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int code = 0;
        run_exec_capture(shield_ctl_bin(), @[@"purge"], &code);
        NSUInteger afterMB = get_available_memory_mb();

        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateRAM];
            if (code != 0) {
                [sender setTitle:@"Purge Tool Unavailable" forState:UIControlStateNormal];
            } else if (afterMB > beforeMB) {
                NSUInteger freed = afterMB - beforeMB;
                [sender setTitle:[NSString stringWithFormat:@"✓ Freed +%lu MB (%lu MB Available)", (unsigned long)freed, (unsigned long)afterMB]
                        forState:UIControlStateNormal];
            } else {
                [sender setTitle:[NSString stringWithFormat:@"✓ Cache Flushed (%lu MB Available)", (unsigned long)afterMB]
                        forState:UIControlStateNormal];
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [sender setTitle:@"Purge Inactive Memory Pages" forState:UIControlStateNormal];
                sender.enabled = YES;
            });
        });
    });
}

- (void)turboSwitchChanged:(UISwitch *)sender {
    BOOL ok = set_turbo_ui(sender.isOn);
    if (!ok) {
        sender.on = get_turbo_ui_status();
    }
    [self refreshTurboUIState];
}

- (void)cleanStorageTapped:(UIButton *)sender {
    sender.enabled = NO;
    [sender setTitle:@"Scanning Diagnostic & Cache Directories..." forState:UIControlStateNormal];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int code = 0;
        NSString *res = [run_exec_capture(shield_ctl_bin(), @[@"clean"], &code) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        NSString *buttonMsg = nil;
        BOOL success = NO;

        if (code == 0 && [res hasPrefix:@"CLEANED:"]) {
            NSArray<NSString *> *parts = [res componentsSeparatedByString:@":"];
            if (parts.count >= 3) {
                long long fileCount = [parts[1] longLongValue];
                unsigned long long byteCount = (unsigned long long)[parts[2] longLongValue];
                success = YES;

                if (fileCount == 0) {
                    buttonMsg = @"✓ Already Clean (0 Stale Files)";
                } else if (byteCount < 1024ULL * 1024ULL) {
                    double kb = (double)byteCount / 1024.0;
                    buttonMsg = [NSString stringWithFormat:@"✓ Removed %lld %@ (%.1f KB Freed)",
                                 fileCount, (fileCount == 1 ? @"File" : @"Files"), kb];
                } else {
                    double mb = (double)byteCount / (1024.0 * 1024.0);
                    buttonMsg = [NSString stringWithFormat:@"✓ Removed %lld %@ (%.2f MB Freed)",
                                 fileCount, (fileCount == 1 ? @"File" : @"Files"), mb];
                }
            }
        }

        if (!buttonMsg) {
            buttonMsg = @"Clean Failed (Permission Error)";
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [sender setTitle:buttonMsg forState:UIControlStateNormal];
            if (success) {
                sender.backgroundColor = [UIColor colorWithRed:0.08 green:0.25 blue:0.15 alpha:0.9];
                sender.layer.borderColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:0.5].CGColor;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [sender setTitle:@"Clear Diagnostic Logs & Expired Caches" forState:UIControlStateNormal];
                sender.backgroundColor = [UIColor colorWithRed:0.10 green:0.18 blue:0.26 alpha:0.9];
                sender.layer.borderColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.7 alpha:0.4].CGColor;
                sender.enabled = YES;
            });
        });
    });
}

- (void)daemonSwitchChanged:(UISwitch *)sender {
    BOOL wantEnabled = sender.isOn;
    sender.enabled = NO;
    NSString *mode = (self.modeControl.selectedSegmentIndex == 1) ? @"gaming" : @"streaming";

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int code = 0;
        if (wantEnabled) {
            run_exec_capture(shield_ctl_bin(), @[@"daemon", @"enable", mode], &code);
        } else {
            run_exec_capture(shield_ctl_bin(), @[@"daemon", @"disable"], &code);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            [self syncFromSystemState];
        });
    });
}

- (void)updateRAM {
    NSUInteger availMB = get_available_memory_mb();
    self.ramLabel.text = [NSString stringWithFormat:@"%lu MB", (unsigned long)availMB];
}

- (void)updateBattery {
    float level = [UIDevice currentDevice].batteryLevel;
    UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
    BOOL isCharging = (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull);

    if (level >= 0.0f) {
        int percent = (int)lroundf(level * 100.0f);
        self.batteryLabel.text = [NSString stringWithFormat:@"%d%%%@", percent, isCharging ? @" ⚡" : @""];
        return;
    }

    BOOL iokitCharging = NO;
    int iokitPct = query_iokit_battery_percent(&iokitCharging);
    if (iokitPct >= 0) {
        self.batteryLabel.text = [NSString stringWithFormat:@"%d%%%@", iokitPct, iokitCharging ? @" ⚡" : @""];
    } else {
        self.batteryLabel.text = @"N/A";
    }
}

static NSString *parse_ping_ms(NSString *pingOutput, int exitCode) {
    if (exitCode != 0 || pingOutput.length == 0) {
        return @"Timeout";
    }
    NSRange range = [pingOutput rangeOfString:@"time="];
    if (range.location == NSNotFound) {
        return @"Timeout";
    }
    NSString *sub = [pingOutput substringFromIndex:range.location + 5];
    NSArray<NSString *> *parts = [sub componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (parts.count > 0 && parts[0].length > 0) {
        return [NSString stringWithFormat:@"%.1f ms", [parts[0] doubleValue]];
    }
    return @"Timeout";
}

- (void)refreshTelemetry {
    [self updateRAM];
    [self updateBattery];
    [self refreshKernelSysctlLabels];

    NSString *gwIP = self.currentGatewayIP;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSString *rMs = @"-- ms";
        if (gwIP.length > 0) {
            int rCode = 0;
            NSString *rOut = run_exec_capture(ping_bin(), @[@"-c", @"1", @"-W", @"400", gwIP], &rCode);
            rMs = parse_ping_ms(rOut, rCode);
        }

        int iCode = 0;
        NSString *iOut = run_exec_capture(ping_bin(), @[@"-c", @"1", @"-W", @"500", @"1.1.1.1"], &iCode);
        NSString *iMs = parse_ping_ms(iOut, iCode);

        dispatch_async(dispatch_get_main_queue(), ^{
            self.routerPingLabel.text = rMs;
            self.internetPingLabel.text = iMs;
        });
    });
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[ShieldViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    (void)app;
    (void)options;
    NSString *host = url.host.lowercaseString;
    if (!host) return NO;

    if ([host isEqualToString:@"banner"]) {
        notify_post(kShowBannerNotify);
        return YES;
    }

    ShieldViewController *vc = (ShieldViewController *)self.window.rootViewController;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        int code = 0;
        if ([host isEqualToString:@"streaming"]) {
            run_exec_capture(shield_ctl_bin(), @[@"start", @"streaming"], &code);
        } else if ([host isEqualToString:@"gaming"]) {
            run_exec_capture(shield_ctl_bin(), @[@"start", @"gaming"], &code);
        } else if ([host isEqualToString:@"normal"] || [host isEqualToString:@"off"] || [host isEqualToString:@"stop"]) {
            run_exec_capture(shield_ctl_bin(), @[@"stop"], &code);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([vc isKindOfClass:[ShieldViewController class]]) {
                [vc syncFromSystemState];
            }
        });
    });
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
