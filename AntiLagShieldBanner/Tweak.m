#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <mach/mach.h>
#include <notify.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <spawn.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static NSString *const kPrefsPlistPath = @"/var/mobile/Library/Preferences/com.nightknight.antilagshield.plist";
static NSString *const kStatePlistPath = @"/var/mobile/Library/Caches/com.nightknight.antilagshield.state.plist";
static NSString *const kLegacyStatePath = @"/var/mobile/Library/Caches/shield_state.txt";
static const char *const kShowBannerNotify = "com.nightknight.antilagshield.showbanner";
static const char *const kStateChangedNotify = "com.nightknight.antilagshield.statechanged";

static const CGFloat kBannerHeight = 124.0;
static const void *kAssociatedBannerViewKey = &kAssociatedBannerViewKey;
static const void *kLastAdjunctHeightKey = &kLastAdjunctHeightKey;

static BOOL sInAdjunctLayoutSync = NO;

static const char *shield_ctl_path(void) {
    if (access("/var/jb/usr/bin/shield_ctl", X_OK) == 0) {
        return "/var/jb/usr/bin/shield_ctl";
    }
    if (access("/usr/bin/shield_ctl", X_OK) == 0) {
        return "/usr/bin/shield_ctl";
    }
    return NULL;
}

static NSString *run_shield_ctl_capture(NSArray<NSString *> *args, int *outExitCode) {
    const char *bin = shield_ctl_path();
    if (!bin) {
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
    char buf[512];
    ssize_t n = 0;
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

static NSUInteger query_available_ram_mb(void) {
    mach_port_t host = mach_host_self();
    vm_size_t pagesize = 0;
    host_page_size(host, &pagesize);

    vm_statistics64_data_t vmstat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vmstat, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (kr != KERN_SUCCESS || pagesize == 0) {
        return 0;
    }
    uint64_t pages = (uint64_t)vmstat.free_count + (uint64_t)vmstat.speculative_count;
    uint64_t bytes = pages * (uint64_t)pagesize;
    return (NSUInteger)(bytes / (1024ULL * 1024ULL));
}

static BOOL read_sysctl_int(const char *name, int *outVal) {
    int val = 0;
    size_t len = sizeof(val);
    if (sysctlbyname(name, &val, &len, NULL, 0) == 0) {
        if (outVal) *outVal = val;
        return YES;
    }
    return NO;
}

static BOOL is_banner_enabled(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPlistPath];
    if (prefs && prefs[@"BannerEnabled"] != nil) {
        return [prefs[@"BannerEnabled"] boolValue];
    }
    return YES;
}

static NSString *read_active_mode(void) {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:kStatePlistPath];
    if (state) {
        if (![state[@"Active"] boolValue]) {
            return @"normal";
        }
        NSString *m = state[@"Mode"];
        return ([m isEqualToString:@"gaming"]) ? @"gaming" : @"streaming";
    }
    NSString *legacy = [NSString stringWithContentsOfFile:kLegacyStatePath encoding:NSUTF8StringEncoding error:nil];
    if ([legacy containsString:@"gaming"]) return @"gaming";
    if ([legacy containsString:@"streaming"]) return @"streaming";
    return @"normal";
}

#pragma mark - Banner Platter View

@interface ALSNotificationBannerView : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIImageView *shieldIconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *streamingButton;
@property (nonatomic, strong) UIButton *gamingButton;
@property (nonatomic, strong) UIButton *normalButton;
@property (nonatomic, strong) UIButton *clearRAMButton;
@property (nonatomic, strong) UIButton *clearCacheButton;
@property (nonatomic, copy) NSString *currentMode;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) NSUInteger statusOverrideToken;

- (void)refreshStateIfIdle;
@end

@implementation ALSNotificationBannerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.userInteractionEnabled = YES;
        self.clipsToBounds = YES;
        self.layer.cornerRadius = 22.0;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;

        UIBlurEffect *blur = nil;
        if (@available(iOS 13.0, *)) {
            blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        } else {
            blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        }
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        _blurView.userInteractionEnabled = NO;
        [self addSubview:_blurView];

        _shieldIconView = [[UIImageView alloc] init];
        _shieldIconView.contentMode = UIViewContentModeScaleAspectFit;
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightSemibold];
            _shieldIconView.image = [UIImage systemImageNamed:@"bolt.shield.fill" withConfiguration:symCfg];
        }
        _shieldIconView.tintColor = [UIColor colorWithRed:0.22 green:0.86 blue:1.0 alpha:1.0];
        [self addSubview:_shieldIconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = @"Anti-Lag Shield";
        _titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor colorWithWhite:0.96 alpha:1.0];
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        _titleLabel.minimumScaleFactor = 0.8;
        [self addSubview:_titleLabel];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightMedium];
        _statusLabel.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
        _statusLabel.textAlignment = NSTextAlignmentRight;
        _statusLabel.adjustsFontSizeToFitWidth = YES;
        _statusLabel.minimumScaleFactor = 0.70;
        [self addSubview:_statusLabel];

        _streamingButton = [self buildPillButtonWithTitle:@"Streaming" symbol:@"tv.fill" action:@selector(streamingTapped)];
        _gamingButton = [self buildPillButtonWithTitle:@"Gaming" symbol:@"gamecontroller.fill" action:@selector(gamingTapped)];
        _normalButton = [self buildPillButtonWithTitle:@"Normal" symbol:@"slider.horizontal.3" action:@selector(normalTapped)];

        _clearRAMButton = [self buildPillButtonWithTitle:@"Clear RAM" symbol:@"memorychip" action:@selector(clearRAMTapped)];
        _clearCacheButton = [self buildPillButtonWithTitle:@"Clear Cache" symbol:@"trash" action:@selector(clearCacheTapped)];

        [self addSubview:_streamingButton];
        [self addSubview:_gamingButton];
        [self addSubview:_normalButton];
        [self addSubview:_clearRAMButton];
        [self addSubview:_clearCacheButton];

        [self styleActionButtons];

        NSLayoutConstraint *hConstraint = [self.heightAnchor constraintEqualToConstant:kBannerHeight];
        hConstraint.priority = 999;
        hConstraint.active = YES;

        NSLayoutConstraint *wConstraint = [self.widthAnchor constraintEqualToConstant:425.0];
        wConstraint.priority = 999;
        wConstraint.active = YES;

        [self refreshStateIfIdle];
    }
    return self;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(425.0, kBannerHeight);
}

- (UIButton *)buildPillButtonWithTitle:(NSString *)title symbol:(NSString *)symbolName action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.clipsToBounds = YES;
    btn.layer.cornerRadius = 10.0;
    if (@available(iOS 13.0, *)) {
        btn.layer.cornerCurve = kCACornerCurveContinuous;
    }
    btn.layer.borderWidth = 0.5;

    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:11.0 weight:UIImageSymbolWeightSemibold];
        UIImage *img = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
        if (img) {
            [btn setImage:img forState:UIControlStateNormal];
            btn.imageView.contentMode = UIViewContentModeScaleAspectFit;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            btn.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 0);
            btn.imageEdgeInsets = UIEdgeInsetsMake(0, -2, 0, 2);
#pragma clang diagnostic pop
        }
    }

    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    btn.titleLabel.adjustsFontSizeToFitWidth = YES;
    btn.titleLabel.minimumScaleFactor = 0.72;
    btn.titleLabel.lineBreakMode = NSLineBreakByClipping;

    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [btn addTarget:self action:@selector(pillTouchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [btn addTarget:self action:@selector(pillTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return btn;
}

- (void)pillTouchDown:(UIButton *)sender {
    [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        sender.alpha = 0.70;
        sender.transform = CGAffineTransformMakeScale(0.97, 0.97);
    } completion:nil];
}

- (void)pillTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
        sender.alpha = 1.0;
        sender.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    self.blurView.frame = self.bounds;

    CGFloat padX = 12.0;
    if (self.shieldIconView.image) {
        self.shieldIconView.frame = CGRectMake(padX + 2.0, 12.0, 16.0, 16.0);
        self.titleLabel.frame = CGRectMake(padX + 23.0, 9.0, 118.0, 22.0);
    } else {
        self.titleLabel.frame = CGRectMake(padX + 2.0, 9.0, 130.0, 22.0);
    }

    CGFloat statusX = CGRectGetMaxX(self.titleLabel.frame) + 6.0;
    self.statusLabel.frame = CGRectMake(statusX, 9.0, MAX(0.0, w - statusX - padX - 2.0), 22.0);

    CGFloat gap = 7.0;
    CGFloat row1Y = 38.0;
    CGFloat btnH = 34.0;
    CGFloat modeW = (w - (padX * 2.0) - (gap * 2.0)) / 3.0;

    self.streamingButton.frame = CGRectMake(padX, row1Y, modeW, btnH);
    self.gamingButton.frame = CGRectMake(padX + modeW + gap, row1Y, modeW, btnH);
    self.normalButton.frame = CGRectMake(padX + (modeW + gap) * 2.0, row1Y, modeW, btnH);

    CGFloat row2Y = 79.0;
    CGFloat actW = (w - (padX * 2.0) - gap) / 2.0;
    self.clearRAMButton.frame = CGRectMake(padX, row2Y, actW, btnH);
    self.clearCacheButton.frame = CGRectMake(padX + actW + gap, row2Y, actW, btnH);
}

- (void)styleActionButtons {
    UIColor *ramText = [UIColor colorWithRed:0.65 green:0.98 blue:0.80 alpha:1.0];
    self.clearRAMButton.backgroundColor = [UIColor colorWithRed:0.10 green:0.34 blue:0.22 alpha:0.62];
    self.clearRAMButton.layer.borderColor = [UIColor colorWithRed:0.28 green:0.82 blue:0.52 alpha:0.36].CGColor;
    [self.clearRAMButton setTitleColor:ramText forState:UIControlStateNormal];
    self.clearRAMButton.tintColor = ramText;

    UIColor *cacheText = [UIColor colorWithRed:0.68 green:0.90 blue:1.0 alpha:1.0];
    self.clearCacheButton.backgroundColor = [UIColor colorWithRed:0.12 green:0.25 blue:0.38 alpha:0.62];
    self.clearCacheButton.layer.borderColor = [UIColor colorWithRed:0.32 green:0.72 blue:0.96 alpha:0.36].CGColor;
    [self.clearCacheButton setTitleColor:cacheText forState:UIControlStateNormal];
    self.clearCacheButton.tintColor = cacheText;
}

- (void)applyModeButtonSelection:(NSString *)mode {
    self.currentMode = mode;

    NSArray<UIButton *> *buttons = @[self.streamingButton, self.gamingButton, self.normalButton];
    for (UIButton *b in buttons) {
        b.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        b.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
        UIColor *dim = [UIColor colorWithWhite:0.84 alpha:1.0];
        [b setTitleColor:dim forState:UIControlStateNormal];
        b.tintColor = dim;
    }

    if ([mode isEqualToString:@"streaming"]) {
        self.streamingButton.backgroundColor = [UIColor colorWithRed:0.06 green:0.50 blue:0.78 alpha:0.90];
        self.streamingButton.layer.borderColor = [UIColor colorWithRed:0.32 green:0.86 blue:1.0 alpha:0.70].CGColor;
        [self.streamingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.streamingButton.tintColor = [UIColor whiteColor];
        self.shieldIconView.tintColor = [UIColor colorWithRed:0.24 green:0.88 blue:1.0 alpha:1.0];
    } else if ([mode isEqualToString:@"gaming"]) {
        self.gamingButton.backgroundColor = [UIColor colorWithRed:0.82 green:0.44 blue:0.08 alpha:0.90];
        self.gamingButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.28 alpha:0.70].CGColor;
        [self.gamingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.gamingButton.tintColor = [UIColor whiteColor];
        self.shieldIconView.tintColor = [UIColor colorWithRed:1.0 green:0.68 blue:0.22 alpha:1.0];
    } else {
        self.normalButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.22];
        self.normalButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.40].CGColor;
        [self.normalButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.normalButton.tintColor = [UIColor whiteColor];
        self.shieldIconView.tintColor = [UIColor colorWithWhite:0.76 alpha:1.0];
    }
}

- (void)updateLiveStatusTextForMode:(NSString *)mode {
    NSUInteger freeMB = query_available_ram_mb();
    int delayedAck = -1;
    BOOL hasAck = read_sysctl_int("net.inet.tcp.delayed_ack", &delayedAck);

    if ([mode isEqualToString:@"streaming"]) {
        if (hasAck) {
            self.statusLabel.text = [NSString stringWithFormat:@"Streaming • ACK %d • %lu MB Free", delayedAck, (unsigned long)freeMB];
        } else {
            self.statusLabel.text = [NSString stringWithFormat:@"Streaming • %lu MB Free", (unsigned long)freeMB];
        }
        self.statusLabel.textColor = [UIColor colorWithRed:0.40 green:0.92 blue:1.0 alpha:1.0];
    } else if ([mode isEqualToString:@"gaming"]) {
        if (hasAck && delayedAck == 0) {
            self.statusLabel.text = [NSString stringWithFormat:@"Gaming • 0ms ACK • %lu MB Free", (unsigned long)freeMB];
        } else {
            self.statusLabel.text = [NSString stringWithFormat:@"Gaming • %lu MB Free", (unsigned long)freeMB];
        }
        self.statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.76 blue:0.34 alpha:1.0];
    } else {
        self.statusLabel.text = [NSString stringWithFormat:@"Normal Mode • %lu MB Free", (unsigned long)freeMB];
        self.statusLabel.textColor = [UIColor colorWithWhite:0.74 alpha:1.0];
    }
}

- (void)refreshStateIfIdle {
    NSString *mode = read_active_mode();
    [self applyModeButtonSelection:mode];
    if (self.statusOverrideToken == 0 && !self.busy) {
        [self updateLiveStatusTextForMode:mode];
    }
}

- (void)showTransientStatus:(NSString *)message color:(UIColor *)color duration:(NSTimeInterval)seconds {
    self.statusOverrideToken += 1;
    NSUInteger token = self.statusOverrideToken;
    self.statusLabel.text = message;
    self.statusLabel.textColor = color;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.statusOverrideToken != token) return;
        strongSelf.statusOverrideToken = 0;
        NSString *mode = read_active_mode();
        [strongSelf applyModeButtonSelection:mode];
        [strongSelf updateLiveStatusTextForMode:mode];
    });
}

- (void)setControlsEnabled:(BOOL)enabled {
    self.busy = !enabled;
    self.streamingButton.enabled = enabled;
    self.gamingButton.enabled = enabled;
    self.normalButton.enabled = enabled;
    self.clearRAMButton.enabled = enabled;
    self.clearCacheButton.enabled = enabled;
}

- (void)switchToMode:(NSString *)targetMode {
    if (self.busy) return;
    [self setControlsEnabled:NO];

    NSString *labelTitle = [targetMode capitalizedString];
    self.statusLabel.text = [NSString stringWithFormat:@"Applying %@...", labelTitle];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.88 alpha:1.0];

    NSArray<NSString *> *args = [targetMode isEqualToString:@"normal"]
        ? @[@"stop"]
        : @[@"start", targetMode];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int code = 0;
        run_shield_ctl_capture(args, &code);
        NSString *verifiedMode = read_active_mode();
        NSUInteger freeMB = query_available_ram_mb();

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf setControlsEnabled:YES];
            [strongSelf applyModeButtonSelection:verifiedMode];

            if (code == 0) {
                NSString *msg = nil;
                UIColor *col = nil;
                if ([verifiedMode isEqualToString:@"streaming"]) {
                    msg = [NSString stringWithFormat:@"✓ Streaming Active • %lu MB Free", (unsigned long)freeMB];
                    col = [UIColor colorWithRed:0.35 green:0.96 blue:0.58 alpha:1.0];
                } else if ([verifiedMode isEqualToString:@"gaming"]) {
                    msg = [NSString stringWithFormat:@"✓ Gaming Active • %lu MB Free", (unsigned long)freeMB];
                    col = [UIColor colorWithRed:1.0 green:0.78 blue:0.32 alpha:1.0];
                } else {
                    msg = [NSString stringWithFormat:@"✓ Normal Mode (Stock XNU) • %lu MB", (unsigned long)freeMB];
                    col = [UIColor colorWithWhite:0.88 alpha:1.0];
                }
                [strongSelf showTransientStatus:msg color:col duration:3.0];
            } else {
                [strongSelf showTransientStatus:@"Kernel Tune Failed"
                                          color:[UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0]
                                       duration:3.0];
            }
        });
    });
}

- (void)streamingTapped {
    [self switchToMode:@"streaming"];
}

- (void)gamingTapped {
    [self switchToMode:@"gaming"];
}

- (void)normalTapped {
    [self switchToMode:@"normal"];
}

- (void)clearRAMTapped {
    if (self.busy) return;
    [self setControlsEnabled:NO];

    NSUInteger beforeMB = query_available_ram_mb();
    self.statusLabel.text = @"Purging Inactive RAM...";
    self.statusLabel.textColor = [UIColor colorWithRed:0.65 green:0.98 blue:0.80 alpha:1.0];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int code = 0;
        run_shield_ctl_capture(@[@"purge"], &code);
        NSUInteger afterMB = query_available_ram_mb();

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf setControlsEnabled:YES];

            if (code != 0) {
                [strongSelf showTransientStatus:@"RAM Purge Unavailable"
                                          color:[UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0]
                                       duration:3.0];
            } else if (afterMB > beforeMB) {
                NSUInteger delta = afterMB - beforeMB;
                NSString *msg = [NSString stringWithFormat:@"✓ Freed +%lu MB (%lu MB Free)", (unsigned long)delta, (unsigned long)afterMB];
                [strongSelf showTransientStatus:msg
                                          color:[UIColor colorWithRed:0.35 green:0.96 blue:0.58 alpha:1.0]
                                       duration:3.5];
            } else {
                NSString *msg = [NSString stringWithFormat:@"✓ RAM Flushed (%lu MB Free)", (unsigned long)afterMB];
                [strongSelf showTransientStatus:msg
                                          color:[UIColor colorWithRed:0.35 green:0.96 blue:0.58 alpha:1.0]
                                       duration:3.5];
            }
        });
    });
}

- (void)clearCacheTapped {
    if (self.busy) return;
    [self setControlsEnabled:NO];

    self.statusLabel.text = @"Cleaning Logs & Caches...";
    self.statusLabel.textColor = [UIColor colorWithRed:0.68 green:0.90 blue:1.0 alpha:1.0];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int code = 0;
        NSString *raw = [run_shield_ctl_capture(@[@"clean"], &code) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        NSString *msg = nil;
        BOOL ok = NO;
        if (code == 0 && [raw hasPrefix:@"CLEANED:"]) {
            NSArray<NSString *> *parts = [raw componentsSeparatedByString:@":"];
            if (parts.count >= 3) {
                long long files = [parts[1] longLongValue];
                unsigned long long bytes = (unsigned long long)[parts[2] longLongValue];
                ok = YES;
                if (files == 0) {
                    msg = @"✓ Already Clean (0 Stale Files)";
                } else if (bytes < 1024ULL * 1024ULL) {
                    msg = [NSString stringWithFormat:@"✓ Cleared %lld %@ (%.1f KB)",
                           files, (files == 1 ? @"File" : @"Files"), (double)bytes / 1024.0];
                } else {
                    msg = [NSString stringWithFormat:@"✓ Cleared %lld %@ (%.2f MB)",
                           files, (files == 1 ? @"File" : @"Files"), (double)bytes / (1024.0 * 1024.0)];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf setControlsEnabled:YES];

            if (ok && msg) {
                [strongSelf showTransientStatus:msg
                                          color:[UIColor colorWithRed:0.42 green:0.92 blue:1.0 alpha:1.0]
                                       duration:3.5];
            } else {
                [strongSelf showTransientStatus:@"Cache Clean Failed"
                                          color:[UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0]
                                       duration:3.0];
            }
        });
    });
}

@end

#pragma mark - SpringBoard CoverSheet Adjunct Integration

static NSHashTable<UIViewController *> *sCombinedControllers = nil;

static UIViewController *get_adjunct_vc(UIViewController *combinedVC) {
    if (!combinedVC) return nil;
    Ivar ivar = class_getInstanceVariable([combinedVC class], "_adjunctListViewController");
    if (ivar) {
        id val = object_getIvar(combinedVC, ivar);
        if ([val isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)val;
        }
    }
    SEL sel = sel_registerName("adjunctListViewController");
    if ([combinedVC respondsToSelector:sel]) {
        id val = ((id (*)(id, SEL))objc_msgSend)(combinedVC, sel);
        if ([val isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)val;
        }
    }
    return nil;
}

static CGSize compute_required_stack_size(UIStackView *stackView, CGSize baseSize) {
    if (![stackView isKindOfClass:[UIStackView class]]) {
        return baseSize;
    }
    CGFloat totalH = 0.0;
    NSUInteger visibleCount = 0;
    for (UIView *sub in stackView.arrangedSubviews) {
        if (sub.hidden || sub.alpha <= 0.01) continue;
        CGFloat subH = sub.bounds.size.height;
        if ([sub isKindOfClass:[ALSNotificationBannerView class]]) {
            subH = kBannerHeight;
        } else if (subH < 1.0) {
            subH = [sub systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
        }
        if (subH > 0.0) {
            if (visibleCount > 0) {
                totalH += stackView.spacing;
            }
            totalH += subH;
            visibleCount++;
        }
    }
    if (visibleCount == 0) {
        return baseSize;
    }
    CGFloat w = (baseSize.width > 0.0) ? baseSize.width : (stackView.bounds.size.width > 0.0 ? stackView.bounds.size.width : 445.0);
    CGFloat reqH = MAX(baseSize.height, totalH);
    return CGSizeMake(w, reqH);
}

static ALSNotificationBannerView *ensure_banner_in_combined_vc(UIViewController *combinedVC) {
    if (!combinedVC) return nil;
    if (!sCombinedControllers) {
        sCombinedControllers = [NSHashTable weakObjectsHashTable];
    }
    [sCombinedControllers addObject:combinedVC];

    UIViewController *adjunctVC = get_adjunct_vc(combinedVC);
    if (!adjunctVC || ![adjunctVC isViewLoaded]) return nil;

    UIStackView *stackView = (UIStackView *)adjunctVC.view;
    if (![stackView isKindOfClass:[UIStackView class]]) return nil;

    __block ALSNotificationBannerView *banner = objc_getAssociatedObject(adjunctVC, kAssociatedBannerViewKey);
    BOOL wantVisible = is_banner_enabled();

    [UIView performWithoutAnimation:^{
        if (!banner && wantVisible) {
            banner = [[ALSNotificationBannerView alloc] initWithFrame:CGRectMake(0, 0, 425.0, kBannerHeight)];
            objc_setAssociatedObject(adjunctVC, kAssociatedBannerViewKey, banner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [stackView insertArrangedSubview:banner atIndex:0];

            NSLayoutConstraint *maxWidth = [banner.widthAnchor constraintLessThanOrEqualToAnchor:stackView.widthAnchor constant:-20.0];
            maxWidth.priority = UILayoutPriorityRequired;
            maxWidth.active = YES;
        }

        if (banner) {
            if (![stackView.arrangedSubviews containsObject:banner] && wantVisible) {
                [stackView insertArrangedSubview:banner atIndex:0];
            }
            banner.hidden = !wantVisible;
            if (wantVisible) {
                [banner refreshStateIfIdle];
            }
        }
    }];

    return banner;
}

static void sync_combined_vc_layout(UIViewController *combinedVC) {
    if (!combinedVC || ![combinedVC isViewLoaded]) return;

    ALSNotificationBannerView *banner = ensure_banner_in_combined_vc(combinedVC);
    UIViewController *adjunctVC = get_adjunct_vc(combinedVC);
    if (!adjunctVC || ![adjunctVC isViewLoaded]) return;

    UIStackView *stackView = (UIStackView *)adjunctVC.view;
    if (![stackView isKindOfClass:[UIStackView class]]) return;

    BOOL visible = (banner != nil && !banner.hidden);
    CGSize reqSize = compute_required_stack_size(stackView, CGSizeZero);
    CGFloat targetH = reqSize.height;

    if (visible) {
        stackView.hidden = NO;
        stackView.alpha = 1.0;
        stackView.userInteractionEnabled = YES;
    }

    NSNumber *prevNum = objc_getAssociatedObject(combinedVC, kLastAdjunctHeightKey);
    CGFloat prevH = prevNum ? [prevNum doubleValue] : -1.0;

    if (!sInAdjunctLayoutSync && fabs(prevH - targetH) > 0.5) {
        objc_setAssociatedObject(combinedVC, kLastAdjunctHeightKey, @(targetH), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        sInAdjunctLayoutSync = YES;

        [UIView performWithoutAnimation:^{
            CGFloat reportW = stackView.bounds.size.width > 0.0 ? stackView.bounds.size.width : 445.0;
            SEL didUpdateSel = sel_registerName("adjunctListViewController:didUpdateWithSize:");
            if ([combinedVC respondsToSelector:didUpdateSel]) {
                ((void (*)(id, SEL, id, CGSize))objc_msgSend)(combinedVC, didUpdateSel, adjunctVC, CGSizeMake(reportW, targetH));
            }
            SEL insetSel = sel_registerName("_updateListViewContentInset");
            if ([combinedVC respondsToSelector:insetSel]) {
                ((void (*)(id, SEL))objc_msgSend)(combinedVC, insetSel);
            }
            SEL layoutSel = sel_registerName("_layoutListView");
            if ([combinedVC respondsToSelector:layoutSel]) {
                ((void (*)(id, SEL))objc_msgSend)(combinedVC, layoutSel);
            }
            if (visible && stackView.frame.size.height < targetH) {
                CGRect f = stackView.frame;
                f.size.width = (f.size.width > 1.0) ? f.size.width : reportW;
                f.size.height = targetH;
                stackView.frame = f;
            } else if (!visible && targetH == 0.0 && stackView.frame.size.height > 0.0) {
                CGRect f = stackView.frame;
                f.size.height = 0.0;
                stackView.frame = f;
            }
            [stackView setNeedsLayout];
            [stackView layoutIfNeeded];
            [stackView.layer removeAllAnimations];
        }];

        sInAdjunctLayoutSync = NO;
    }
}

static void refresh_all_banners(void) {
    for (UIViewController *vc in [sCombinedControllers allObjects]) {
        sync_combined_vc_layout(vc);
    }
}

static UIViewController *find_vc_of_class(UIViewController *root, Class targetClass) {
    if (!root || !targetClass) return nil;
    if ([root isKindOfClass:targetClass]) return root;
    for (UIViewController *child in root.childViewControllers) {
        UIViewController *found = find_vc_of_class(child, targetClass);
        if (found) return found;
    }
    if (root.presentedViewController) {
        UIViewController *found = find_vc_of_class(root.presentedViewController, targetClass);
        if (found) return found;
    }
    return nil;
}

static void attach_to_existing_windows(void) {
    Class combinedCls = objc_getClass("CSCombinedListViewController");
    if (!combinedCls) return;

    NSArray<UIWindow *> *windows = nil;
    if (@available(iOS 15.0, *)) {
        NSMutableArray<UIWindow *> *collected = [NSMutableArray array];
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                [collected addObjectsFromArray:((UIWindowScene *)scene).windows];
            }
        }
        windows = collected;
    }
    if (windows.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        windows = [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
    }

    for (UIWindow *win in windows) {
        UIViewController *found = find_vc_of_class(win.rootViewController, combinedCls);
        if (found) {
            sync_combined_vc_layout(found);
        }
    }
}

#pragma mark - Swizzled Methods

static CGSize (*orig_adjunct_stackViewContentSize)(id, SEL) = NULL;
static CGSize swz_adjunct_stackViewContentSize(UIViewController *self, SEL _cmd) {
    CGSize orig = orig_adjunct_stackViewContentSize ? orig_adjunct_stackViewContentSize(self, _cmd) : CGSizeZero;
    if (![self isViewLoaded] || !is_banner_enabled()) {
        return orig;
    }
    ALSNotificationBannerView *banner = objc_getAssociatedObject(self, kAssociatedBannerViewKey);
    if (!banner || banner.hidden) {
        return orig;
    }
    return compute_required_stack_size((UIStackView *)self.view, orig);
}

static BOOL (*orig_adjunct_isPresentingContent)(id, SEL) = NULL;
static BOOL swz_adjunct_isPresentingContent(UIViewController *self, SEL _cmd) {
    BOOL orig = orig_adjunct_isPresentingContent ? orig_adjunct_isPresentingContent(self, _cmd) : NO;
    if (orig) return YES;
    ALSNotificationBannerView *banner = objc_getAssociatedObject(self, kAssociatedBannerViewKey);
    if (banner && !banner.hidden && is_banner_enabled()) {
        return YES;
    }
    return NO;
}

static void (*orig_combined_viewDidLoad)(id, SEL) = NULL;
static void swz_combined_viewDidLoad(UIViewController *self, SEL _cmd) {
    if (orig_combined_viewDidLoad) {
        orig_combined_viewDidLoad(self, _cmd);
    }
    sync_combined_vc_layout(self);
}

static void (*orig_combined_viewWillAppear)(id, SEL, BOOL) = NULL;
static void swz_combined_viewWillAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    if (orig_combined_viewWillAppear) {
        orig_combined_viewWillAppear(self, _cmd, animated);
    }
    sync_combined_vc_layout(self);
}

static void (*orig_combined_layoutListView)(id, SEL) = NULL;
static void swz_combined_layoutListView(UIViewController *self, SEL _cmd) {
    if (orig_combined_layoutListView) {
        orig_combined_layoutListView(self, _cmd);
    }
    sync_combined_vc_layout(self);
}

static CGSize (*orig_combined_adjunctSize)(id, SEL) = NULL;
static CGSize swz_combined_adjunctSize(UIViewController *self, SEL _cmd) {
    CGSize orig = orig_combined_adjunctSize ? orig_combined_adjunctSize(self, _cmd) : CGSizeZero;
    if (!is_banner_enabled()) return orig;
    UIViewController *adjunctVC = get_adjunct_vc(self);
    if (!adjunctVC || ![adjunctVC isViewLoaded]) return orig;
    return compute_required_stack_size((UIStackView *)adjunctVC.view, orig);
}

static CGSize (*orig_combined_adjunctSizeSpacing)(id, SEL) = NULL;
static CGSize swz_combined_adjunctSizeSpacing(UIViewController *self, SEL _cmd) {
    CGSize orig = orig_combined_adjunctSizeSpacing ? orig_combined_adjunctSizeSpacing(self, _cmd) : CGSizeZero;
    if (!is_banner_enabled()) return orig;
    UIViewController *adjunctVC = get_adjunct_vc(self);
    if (!adjunctVC || ![adjunctVC isViewLoaded]) return orig;
    return compute_required_stack_size((UIStackView *)adjunctVC.view, orig);
}

static void hook_method(Class cls, SEL sel, IMP newImp, IMP *origStore) {
    if (!cls || !sel || !newImp) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP prev = method_setImplementation(m, newImp);
    if (origStore) {
        *origStore = prev;
    }
}

static void install_hooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class adjunctCls = objc_getClass("CSNotificationAdjunctListViewController");
        if (adjunctCls) {
            hook_method(adjunctCls, sel_registerName("stackViewContentSize"),
                        (IMP)swz_adjunct_stackViewContentSize, (IMP *)&orig_adjunct_stackViewContentSize);
            hook_method(adjunctCls, sel_registerName("isPresentingContent"),
                        (IMP)swz_adjunct_isPresentingContent, (IMP *)&orig_adjunct_isPresentingContent);
        }

        Class combinedCls = objc_getClass("CSCombinedListViewController");
        if (combinedCls) {
            hook_method(combinedCls, @selector(viewDidLoad),
                        (IMP)swz_combined_viewDidLoad, (IMP *)&orig_combined_viewDidLoad);
            hook_method(combinedCls, @selector(viewWillAppear:),
                        (IMP)swz_combined_viewWillAppear, (IMP *)&orig_combined_viewWillAppear);
            hook_method(combinedCls, sel_registerName("_layoutListView"),
                        (IMP)swz_combined_layoutListView, (IMP *)&orig_combined_layoutListView);
            hook_method(combinedCls, sel_registerName("_adjunctListViewSize"),
                        (IMP)swz_combined_adjunctSize, (IMP *)&orig_combined_adjunctSize);
            hook_method(combinedCls, sel_registerName("_adjunctListViewSizeIncludingSpacing"),
                        (IMP)swz_combined_adjunctSizeSpacing, (IMP *)&orig_combined_adjunctSizeSpacing);
        }

        int showToken = 0;
        notify_register_dispatch(kShowBannerNotify, &showToken, dispatch_get_main_queue(), ^(int token) {
            (void)token;
            attach_to_existing_windows();
            refresh_all_banners();
        });

        int stateToken = 0;
        notify_register_dispatch(kStateChangedNotify, &stateToken, dispatch_get_main_queue(), ^(int token) {
            (void)token;
            refresh_all_banners();
        });

        attach_to_existing_windows();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            attach_to_existing_windows();
            refresh_all_banners();
        });
    });
}

__attribute__((constructor))
static void initAntiLagShieldBanner(void) {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        install_hooks();
    });
}
