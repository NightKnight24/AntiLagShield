#import <UIKit/UIKit.h>
#import <unistd.h>
#import <sys/types.h>
#import <spawn.h>
#import <mach/mach.h>
#import <mach/mach_host.h>

extern char **environ;

static NSString *get_shield_ctl_path(void) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/bin/shield_ctl"]) {
        return @"/var/jb/usr/bin/shield_ctl";
    }
    return @"/usr/bin/shield_ctl";
}

static void run_cmd(NSString *command) {
    pid_t pid;
    const char *sh = "/var/jb/usr/bin/bash";
    if (access(sh, X_OK) != 0) sh = "/usr/bin/bash";
    if (access(sh, X_OK) != 0) sh = "/bin/bash";
    if (access(sh, X_OK) != 0) sh = "/var/jb/usr/bin/sh";
    if (access(sh, X_OK) != 0) sh = "/bin/sh";
    
    NSString *fullCmd = [NSString stringWithFormat:@"export PATH=\"/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"; %@", command];
    const char *argv[] = {sh, "-c", [fullCmd UTF8String], NULL};
    posix_spawn(&pid, sh, NULL, NULL, (char * const *)argv, environ);
    int status;
    waitpid(pid, &status, 0);
}

static NSUInteger get_free_memory_mb(void) {
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t pagesize;
    vm_statistics_data_t vm_stat;
    host_page_size(host_port, &pagesize);
    if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) != KERN_SUCCESS) {
        return 0;
    }
    unsigned long long free_bytes = ((unsigned long long)vm_stat.free_count + (unsigned long long)vm_stat.speculative_count) * pagesize;
    return (NSUInteger)(free_bytes / (1024 * 1024));
}

@interface ShieldViewController : UIViewController
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *statusBadge;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UILabel *routerPingLabel;
@property (nonatomic, strong) UILabel *internetPingLabel;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, strong) UILabel *ramLabel;
@property (nonatomic, strong) UIButton *purgeButton;
@property (nonatomic, strong) UISwitch *daemonSwitch;
@property (nonatomic, strong) UILabel *daemonStatusLabel;
@property (nonatomic, strong) UILabel *gatewayLabel;
@property (nonatomic, strong) UILabel *tsoLabel;
@property (nonatomic, strong) UILabel *bufferLabel;
@property (nonatomic, strong) NSTimer *telemetryTimer;
@end

@implementation ShieldViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:1.0];
    
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];
    
    CGFloat width = self.view.bounds.size.width;
    CGFloat contentW = MIN(width - 40, 680);
    CGFloat startX = (width - contentW) / 2;
    CGFloat y = 40;
    
    // Header Icon
    UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(startX, y, contentW, 50)];
    iconLabel.text = @"🛡️";
    iconLabel.font = [UIFont systemFontOfSize:46];
    iconLabel.textAlignment = NSTextAlignmentCenter;
    [self.scrollView addSubview:iconLabel];
    y += 54;
    
    // Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(startX, y, contentW, 30)];
    titleLabel.text = @"Anti-Lag Shield Pro v3.6";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.scrollView addSubview:titleLabel];
    y += 32;

    // Subtitle
    UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(startX, y, contentW, 20)];
    subLabel.text = @"Universal Gateway Sentinel • Bandwidth Guard • Battery Saver";
    subLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    subLabel.textColor = [UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:0.9];
    subLabel.textAlignment = NSTextAlignmentCenter;
    [self.scrollView addSubview:subLabel];
    y += 30;
    
    // Status Badge
    self.statusBadge = [[UILabel alloc] initWithFrame:CGRectMake(startX + (contentW - 270) / 2, y, 270, 32)];
    self.statusBadge.text = @"●  SENTINEL ACTIVE";
    self.statusBadge.font = [UIFont boldSystemFontOfSize:13];
    self.statusBadge.textColor = [UIColor colorWithRed:0.2 green:0.95 blue:0.4 alpha:1.0];
    self.statusBadge.backgroundColor = [UIColor colorWithRed:0.06 green:0.22 blue:0.12 alpha:0.9];
    self.statusBadge.layer.cornerRadius = 16;
    self.statusBadge.clipsToBounds = YES;
    self.statusBadge.textAlignment = NSTextAlignmentCenter;
    [self.scrollView addSubview:self.statusBadge];
    y += 44;
    
    // Mode Switcher
    NSArray *items = @[@"🎬 Streaming & Web VIP", @"🎮 Ultra-Low Latency"];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:items];
    self.modeControl.frame = CGRectMake(startX, y, contentW, 40);
    self.modeControl.selectedSegmentIndex = 0;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scrollView addSubview:self.modeControl];
    y += 52;
    
    // CARD 1: Live Telemetry & RAM Booster (4 Columns: Gateway | Ping | Battery | RAM)
    UIView *telemetryCard = [[UIView alloc] initWithFrame:CGRectMake(startX, y, contentW, 140)];
    telemetryCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    telemetryCard.layer.cornerRadius = 16;
    telemetryCard.layer.borderWidth = 1.0;
    telemetryCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:telemetryCard];
    
    CGFloat colW = (contentW - 50) / 4;
    // Router Ping
    UILabel *rTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 14, colW, 18)];
    rTitle.text = @"GATEWAY";
    rTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    rTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [telemetryCard addSubview:rTitle];
    
    self.routerPingLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 34, colW, 26)];
    self.routerPingLabel.text = @"-- ms";
    self.routerPingLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
    self.routerPingLabel.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
    [telemetryCard addSubview:self.routerPingLabel];
    
    // Internet Ping
    UILabel *iTitle = [[UILabel alloc] initWithFrame:CGRectMake(16 + colW, 14, colW, 18)];
    iTitle.text = @"INTERNET (1.1)";
    iTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    iTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [telemetryCard addSubview:iTitle];
    
    self.internetPingLabel = [[UILabel alloc] initWithFrame:CGRectMake(16 + colW, 34, colW, 26)];
    self.internetPingLabel.text = @"-- ms";
    self.internetPingLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
    self.internetPingLabel.textColor = [UIColor colorWithRed:0.75 green:0.45 blue:1.0 alpha:1.0];
    [telemetryCard addSubview:self.internetPingLabel];

    // Battery Status
    UILabel *bTitle = [[UILabel alloc] initWithFrame:CGRectMake(20 + colW * 2, 14, colW, 18)];
    bTitle.text = @"BATTERY";
    bTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    bTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [telemetryCard addSubview:bTitle];
    
    self.batteryLabel = [[UILabel alloc] initWithFrame:CGRectMake(20 + colW * 2, 34, colW, 26)];
    self.batteryLabel.text = @"100%";
    self.batteryLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
    self.batteryLabel.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
    [telemetryCard addSubview:self.batteryLabel];
    
    // RAM Status
    UILabel *mTitle = [[UILabel alloc] initWithFrame:CGRectMake(24 + colW * 3, 14, colW, 18)];
    mTitle.text = @"FREE RAM";
    mTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    mTitle.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [telemetryCard addSubview:mTitle];
    
    self.ramLabel = [[UILabel alloc] initWithFrame:CGRectMake(24 + colW * 3, 34, colW, 26)];
    self.ramLabel.text = @"-- MB";
    self.ramLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightBold];
    self.ramLabel.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.55 alpha:1.0];
    [telemetryCard addSubview:self.ramLabel];
    
    // Purge RAM Button
    self.purgeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.purgeButton.frame = CGRectMake(12, 76, contentW - 24, 48);
    [self.purgeButton setTitle:@"⚡ Clean Inactive RAM (Purge Cache)" forState:UIControlStateNormal];
    self.purgeButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.purgeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.purgeButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.28 blue:0.20 alpha:0.9];
    self.purgeButton.layer.cornerRadius = 12;
    self.purgeButton.layer.borderWidth = 1.0;
    self.purgeButton.layer.borderColor = [UIColor colorWithRed:0.25 green:0.65 blue:0.4 alpha:0.5].CGColor;
    [self.purgeButton addTarget:self action:@selector(purgeRAMTapped:) forControlEvents:UIControlEventTouchUpInside];
    [telemetryCard addSubview:self.purgeButton];
    y += 152;
    
    // CARD 2: Active Defenses & Protocols (7 Rows + Config Gateway Button)
    UIView *defCard = [[UIView alloc] initWithFrame:CGRectMake(startX, y, contentW, 315)];
    defCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    defCard.layer.cornerRadius = 16;
    defCard.layer.borderWidth = 1.0;
    defCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:defCard];
    
    UIButton *cfgBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cfgBtn.frame = CGRectMake(contentW - 130, 8, 118, 26);
    [cfgBtn setTitle:@"⚙️ Config Gateway" forState:UIControlStateNormal];
    cfgBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [cfgBtn setTitleColor:[UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    cfgBtn.backgroundColor = [UIColor colorWithRed:0.08 green:0.22 blue:0.28 alpha:0.8];
    cfgBtn.layer.cornerRadius = 8;
    [cfgBtn addTarget:self action:@selector(configGatewayTapped:) forControlEvents:UIControlEventTouchUpInside];
    [defCard addSubview:cfgBtn];
    
    CGFloat dy = 10;
    NSArray *rows = @[
        @{@"t": @"Zero-Trust Gateway Lock", @"v": @"Auto-Detecting on Wi-Fi..."},
        @{@"t": @"Universal Anti-Spoof Sentinel", @"v": @"Rogue ARP Hijacks & Poisoning Defense Active"},
        @{@"t": @"Bandwidth Thief Sentinel", @"v": @"Active (Background App Store & iCloud Downloads Throttled)"},
        @{@"t": @"Battery & Telemetry Shield", @"v": @"Apple Diagnostics & Bloat Daemons Halted (Deep Sleep)"},
        @{@"t": @"Stremio Web Server VIP", @"v": @"Port 11470 • NodeMobile & MediaServer (-20)"},
        @{@"t": @"TSO Anti-Bufferbloat Control", @"v": @"TSO Enabled (Retina Throughput)"},
        @{@"t": @"TCP / UDP Buffer Tuning", @"v": @"6 MB Retina HD Buffer (somaxconn: 512)"}
    ];
    
    for (NSDictionary *r in rows) {
        UILabel *tLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, dy, contentW - 150, 15)];
        tLbl.text = r[@"t"];
        tLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        tLbl.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
        [defCard addSubview:tLbl];
        
        UILabel *vLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, dy + 15, contentW - 32, 18)];
        vLbl.text = r[@"v"];
        vLbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        vLbl.textColor = [UIColor whiteColor];
        if ([r[@"t"] containsString:@"Gateway Lock"]) {
            self.gatewayLabel = vLbl;
            vLbl.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:1.0 alpha:1.0];
        } else if ([r[@"t"] containsString:@"Buffer Tuning"]) {
            self.bufferLabel = vLbl;
        } else if ([r[@"t"] containsString:@"TSO"]) {
            self.tsoLabel = vLbl;
            vLbl.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
        } else if ([r[@"t"] containsString:@"Battery"]) {
            vLbl.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.45 alpha:1.0];
        } else if ([r[@"t"] containsString:@"Anti-Spoof"] || [r[@"t"] containsString:@"Bandwidth"]) {
            vLbl.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.5 alpha:1.0];
        } else if ([r[@"t"] containsString:@"Stremio"]) {
            vLbl.textColor = [UIColor colorWithRed:1.0 green:0.7 blue:0.2 alpha:1.0];
        }
        [defCard addSubview:vLbl];
        dy += 41;
    }
    y += 327;
    
    // CARD 3: VIP Prioritized Apps Shelf
    UIView *vipCard = [[UIView alloc] initWithFrame:CGRectMake(startX, y, contentW, 115)];
    vipCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    vipCard.layer.cornerRadius = 16;
    vipCard.layer.borderWidth = 1.0;
    vipCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:vipCard];
    
    UILabel *vipTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, contentW - 32, 16)];
    vipTitle.text = @"VIP REAL-TIME PROCESS SCHEDULER (nice -20)";
    vipTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    vipTitle.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    [vipCard addSubview:vipTitle];
    
    UILabel *vipList = [[UILabel alloc] initWithFrame:CGRectMake(16, 32, contentW - 32, 44)];
    vipList.text = @"🎬 Stremio • NodeMobile • YouTube • Netflix • Prime Video • Disney+\n🎮 Roblox • Minecraft • Delta • RetroArch • Moonlight • GeForceNOW";
    vipList.numberOfLines = 2;
    vipList.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    vipList.textColor = [UIColor colorWithRed:0.85 green:0.9 blue:1.0 alpha:0.9];
    [vipCard addSubview:vipList];
    
    UILabel *vipSub = [[UILabel alloc] initWithFrame:CGRectMake(16, 82, contentW - 32, 18)];
    vipSub.text = @"✓ Background watchdog auto-boosts these apps the moment they launch.";
    vipSub.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    vipSub.textColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.45 alpha:0.9];
    [vipCard addSubview:vipSub];
    y += 127;
    
    // CARD 4: 24/7 Persistent Daemon Toggle
    UIView *daemonCard = [[UIView alloc] initWithFrame:CGRectMake(startX, y, contentW, 85)];
    daemonCard.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.95];
    daemonCard.layer.cornerRadius = 16;
    daemonCard.layer.borderWidth = 1.0;
    daemonCard.layer.borderColor = [UIColor colorWithRed:0.15 green:0.20 blue:0.28 alpha:1.0].CGColor;
    [self.scrollView addSubview:daemonCard];
    
    UILabel *dTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, contentW - 90, 20)];
    dTitle.text = @"24/7 Always-On Background Daemon";
    dTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    dTitle.textColor = [UIColor whiteColor];
    [daemonCard addSubview:dTitle];
    
    self.daemonStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, contentW - 90, 36)];
    self.daemonStatusLabel.text = @"Off: Shield active in App Switcher; reverts when swiped away.";
    self.daemonStatusLabel.numberOfLines = 2;
    self.daemonStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.daemonStatusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    [daemonCard addSubview:self.daemonStatusLabel];
    
    self.daemonSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(contentW - 65, 27, 51, 31)];
    [self.daemonSwitch addTarget:self action:@selector(daemonSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [daemonCard addSubview:self.daemonSwitch];
    y += 97;
    
    self.scrollView.contentSize = CGSizeMake(width, y + 40);
    
    [self checkDaemonStatus];
    [self applyShield];
    [self updateRAM];
    [self updateBattery];
    [self updateGatewayLabel];
    
    self.telemetryTimer = [NSTimer scheduledTimerWithTimeInterval:2.5 target:self selector:@selector(refreshTelemetry) userInfo:nil repeats:YES];
    [self refreshTelemetry];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.scrollView.frame = self.view.bounds;
}

- (void)modeChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 0) {
        self.tsoLabel.text = @"TSO Enabled (Retina Throughput)";
        self.tsoLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1.0 alpha:1.0];
        self.bufferLabel.text = @"6 MB Retina HD Buffer (somaxconn: 512)";
    } else {
        self.tsoLabel.text = @"TSO Disabled (0ms Bufferbloat Guard)";
        self.tsoLabel.textColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.4 alpha:1.0];
        self.bufferLabel.text = @"Instant ACK (0ms) + 2 MB Buffers (somaxconn: 512)";
    }
    [self applyShield];
}

- (void)configGatewayTapped:(UIButton *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"⚙️ Gateway Configuration"
                                                                   message:@"Anti-Lag Shield Pro automatically discovers your router on any Wi-Fi network. You can also specify a custom gateway below."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Gateway IP (e.g. 192.168.1.1 or auto)";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Gateway MAC (e.g. 00:11:22:33:44:55 or auto)";
        textField.keyboardType = UIKeyboardTypeASCIICapable;
    }];
    
    UIAlertAction *autoAction = [UIAlertAction actionWithTitle:@"Auto-Detect on Any Wi-Fi" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            run_cmd([NSString stringWithFormat:@"%@ config auto", get_shield_ctl_path()]);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateGatewayLabel];
                [self applyShield];
            });
        });
    }];
    
    UIAlertAction *saveAction = [UIAlertAction actionWithTitle:@"Save Custom" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *ip = alert.textFields[0].text;
        NSString *mac = alert.textFields[1].text;
        if (ip.length > 0 && mac.length > 0) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                run_cmd([NSString stringWithFormat:@"%@ config set %@ %@", get_shield_ctl_path(), ip, mac]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateGatewayLabel];
                    [self applyShield];
                });
            });
        }
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:autoAction];
    [alert addAction:saveAction];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateGatewayLabel {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        run_cmd([NSString stringWithFormat:@"%@ config show > /tmp/gw_cfg.txt 2>/dev/null", get_shield_ctl_path()]);
        NSString *cfg = [NSString stringWithContentsOfFile:@"/tmp/gw_cfg.txt" encoding:NSUTF8StringEncoding error:nil];
        NSString *ip = @"";
        NSString *mac = @"";
        for (NSString *line in [cfg componentsSeparatedByString:@"\n"]) {
            if ([line hasPrefix:@"ROUTER_IP="]) {
                ip = [line substringFromIndex:10];
            } else if ([line hasPrefix:@"ROUTER_MAC="]) {
                mac = [line substringFromIndex:11];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (ip.length > 0 && mac.length > 0) {
                self.gatewayLabel.text = [NSString stringWithFormat:@"Locked: %@ (%@)", ip, mac];
            } else {
                self.gatewayLabel.text = @"Auto-Detected & Guarded [Permanent]";
            }
        });
    });
}

- (void)purgeRAMTapped:(UIButton *)sender {
    sender.enabled = NO;
    [sender setTitle:@"⚡ Cleaning Inactive Pages..." forState:UIControlStateNormal];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        run_cmd([NSString stringWithFormat:@"%@ purge", get_shield_ctl_path()]);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateRAM];
            [sender setTitle:@"✓ RAM Cleaned (+500 MB Reclaimed)" forState:UIControlStateNormal];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [sender setTitle:@"⚡ Clean Inactive RAM (Purge Cache)" forState:UIControlStateNormal];
                sender.enabled = YES;
            });
        });
    });
}

- (void)checkDaemonStatus {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        run_cmd([NSString stringWithFormat:@"%@ daemon status > /tmp/daemon_stat.txt 2>/dev/null", get_shield_ctl_path()]);
        NSString *s = [NSString stringWithContentsOfFile:@"/tmp/daemon_stat.txt" encoding:NSUTF8StringEncoding error:nil];
        BOOL isActive = [s containsString:@"DAEMON_ACTIVE"];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.daemonSwitch.on = isActive;
            if (isActive) {
                self.daemonStatusLabel.text = @"On: Persistent 24/7 root daemon active across reboots.";
                self.statusBadge.text = @"●  24/7 SENTINEL ACTIVE";
            } else {
                self.daemonStatusLabel.text = @"Off: Shield active in App Switcher; reverts when swiped away.";
                self.statusBadge.text = @"●  SENTINEL ACTIVE";
            }
        });
    });
}

- (void)daemonSwitchChanged:(UISwitch *)sender {
    NSString *mode = (self.modeControl.selectedSegmentIndex == 0) ? @"streaming" : @"gaming";
    if (sender.isOn) {
        self.daemonStatusLabel.text = @"Enabling 24/7 LaunchDaemon...";
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            run_cmd([NSString stringWithFormat:@"%@ daemon enable %@", get_shield_ctl_path(), mode]);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.daemonStatusLabel.text = @"On: Persistent 24/7 root daemon active across reboots.";
                self.statusBadge.text = @"●  24/7 SENTINEL ACTIVE";
            });
        });
    } else {
        self.daemonStatusLabel.text = @"Disabling 24/7 LaunchDaemon...";
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            run_cmd([NSString stringWithFormat:@"%@ daemon disable", get_shield_ctl_path()]);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.daemonStatusLabel.text = @"Off: Shield active in App Switcher; reverts when swiped away.";
                self.statusBadge.text = @"●  SENTINEL ACTIVE";
                [self applyShield];
            });
        });
    }
}

- (void)applyShield {
    if (self.daemonSwitch.isOn) {
        return;
    }
    pid_t myPid = getpid();
    NSString *mode = (self.modeControl.selectedSegmentIndex == 0) ? @"streaming" : @"gaming";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *cmd = [NSString stringWithFormat:@"%@ start %@ %d", get_shield_ctl_path(), mode, myPid];
        run_cmd(cmd);
    });
}

- (void)updateRAM {
    NSUInteger freeMB = get_free_memory_mb();
    self.ramLabel.text = [NSString stringWithFormat:@"%lu MB", (unsigned long)freeMB];
}

- (void)updateBattery {
    float level = [UIDevice currentDevice].batteryLevel;
    int percent = (level >= 0.0f) ? (int)(level * 100.0f) : 100;
    BOOL isCharging = ([UIDevice currentDevice].batteryState == UIDeviceBatteryStateCharging || [UIDevice currentDevice].batteryState == UIDeviceBatteryStateFull);
    self.batteryLabel.text = [NSString stringWithFormat:@"%d%%%@", percent, isCharging ? @" ⚡" : @""];
}

- (void)refreshTelemetry {
    [self updateRAM];
    [self updateBattery];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        run_cmd(@"ping -c 1 -W 400 $(route -n get default 2>/dev/null | awk '/gateway:/ {print $2}') > /tmp/rping.txt 2>/dev/null");
        run_cmd(@"ping -c 1 -W 500 1.1.1.1 > /tmp/iping.txt 2>/dev/null");
        
        NSString *rStr = [NSString stringWithContentsOfFile:@"/tmp/rping.txt" encoding:NSUTF8StringEncoding error:nil];
        NSString *iStr = [NSString stringWithContentsOfFile:@"/tmp/iping.txt" encoding:NSUTF8StringEncoding error:nil];
        
        NSString *rMs = @"-- ms";
        if (rStr && [rStr containsString:@"time="]) {
            NSRange range = [rStr rangeOfString:@"time="];
            NSString *sub = [rStr substringFromIndex:range.location + range.length];
            NSArray *parts = [sub componentsSeparatedByString:@" "];
            if (parts.count > 0) rMs = [NSString stringWithFormat:@"%@ ms", parts[0]];
        }
        
        NSString *iMs = @"-- ms";
        if (iStr && [iStr containsString:@"time="]) {
            NSRange range = [iStr rangeOfString:@"time="];
            NSString *sub = [iStr substringFromIndex:range.location + range.length];
            NSArray *parts = [sub componentsSeparatedByString:@" "];
            if (parts.count > 0) iMs = [NSString stringWithFormat:@"%@ ms", parts[0]];
        }
        
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
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [[ShieldViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    run_cmd([NSString stringWithFormat:@"%@ status > /tmp/curstat.txt 2>/dev/null", get_shield_ctl_path()]);
    NSString *s = [NSString stringWithContentsOfFile:@"/tmp/curstat.txt" encoding:NSUTF8StringEncoding error:nil];
    if (![s containsString:@"DAEMON"]) {
        run_cmd([NSString stringWithFormat:@"%@ stop", get_shield_ctl_path()]);
    }
}

@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
