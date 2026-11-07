#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <notify.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static NSString *const kStatePlistPath = @"/var/mobile/Library/Caches/com.nightknight.antilagshield.state.plist";
static NSString *const kLegacyStatePath = @"/var/mobile/Library/Caches/shield_state.txt";
static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.nightknight.antilagshield.plist";
static const char *const kStateChangedNotify = "com.nightknight.antilagshield.statechanged";

@interface CCUIToggleModule : NSObject
- (void)refreshState;
@end

@interface AntiLagShieldCC : CCUIToggleModule {
    int _notifyToken;
}
@end

@implementation AntiLagShieldCC

- (instancetype)init {
    self = [super init];
    if (self) {
        __weak typeof(self) weakSelf = self;
        int token = 0;
        if (notify_register_dispatch(kStateChangedNotify, &token, dispatch_get_main_queue(), ^(int t) {
            (void)t;
            [weakSelf refreshState];
        }) == NOTIFY_STATUS_OK) {
            _notifyToken = token;
        }
    }
    return self;
}

- (void)dealloc {
    if (_notifyToken != 0) {
        notify_cancel(_notifyToken);
    }
}

- (NSString *)currentMode {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:kStatePlistPath];
    if (state) {
        return [state[@"Active"] boolValue] ? (state[@"Mode"] ?: @"streaming") : @"off";
    }
    NSString *legacy = [NSString stringWithContentsOfFile:kLegacyStatePath encoding:NSUTF8StringEncoding error:nil];
    if ([legacy containsString:@"gaming"]) return @"gaming";
    if ([legacy containsString:@"ACTIVE"]) return @"streaming";
    return @"off";
}

- (UIImage *)iconGlyph {
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"shield.fill"];
    }
    return nil;
}

- (UIColor *)selectedColor {
    if ([[self currentMode] isEqualToString:@"gaming"]) {
        return [UIColor colorWithRed:1.00 green:0.58 blue:0.00 alpha:1.0];
    }
    return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
}

- (BOOL)isSelected {
    return ![[self currentMode] isEqualToString:@"off"];
}

- (void)setSelected:(BOOL)selected {
    const char *ctl = (access("/var/jb/usr/bin/shield_ctl", X_OK) == 0)
        ? "/var/jb/usr/bin/shield_ctl"
        : "/usr/bin/shield_ctl";

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    NSString *preferredMode = [prefs[@"LastMode"] isEqualToString:@"gaming"] ? @"gaming" : @"streaming";

    pid_t pid = 0;
    if (selected) {
        const char *argv[] = {ctl, "start", preferredMode.UTF8String, NULL};
        if (posix_spawn(&pid, ctl, NULL, NULL, (char * const *)argv, environ) == 0) {
            int status = 0;
            waitpid(pid, &status, 0);
        }
    } else {
        const char *argv[] = {ctl, "stop", NULL};
        if (posix_spawn(&pid, ctl, NULL, NULL, (char * const *)argv, environ) == 0) {
            int status = 0;
            waitpid(pid, &status, 0);
        }
    }

    [self refreshState];
}

@end
