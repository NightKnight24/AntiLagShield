#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#include <notify.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static NSString *const kStatePlistPath = @"/var/mobile/Library/Caches/com.nightknight.antilagshield.state.plist";
static NSString *const kLegacyStatePath = @"/var/mobile/Library/Caches/shield_state.txt";
static NSString *const kBannerCategoryID = @"SHIELD_SWITCHER";
static NSString *const kBannerRequestID = @"antilag_shield_banner";
static const char *const kShowBannerNotify = "com.nightknight.antilagshield.showbanner";
static const char *const kStateChangedNotify = "com.nightknight.antilagshield.statechanged";

static void spawn_shield_ctl(const char *arg1, const char *arg2) {
    const char *ctl = (access("/var/jb/usr/bin/shield_ctl", X_OK) == 0)
        ? "/var/jb/usr/bin/shield_ctl"
        : "/usr/bin/shield_ctl";
    const char *argv[] = {ctl, arg1, arg2, NULL};
    pid_t pid = 0;
    if (posix_spawn(&pid, ctl, NULL, NULL, (char * const *)argv, environ) == 0) {
        int status = 0;
        waitpid(pid, &status, 0);
    }
}

static NSString *read_current_mode(void) {
    NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:kStatePlistPath];
    if (state) {
        return [state[@"Active"] boolValue] ? (state[@"Mode"] ?: @"streaming") : @"off";
    }
    NSString *legacy = [NSString stringWithContentsOfFile:kLegacyStatePath encoding:NSUTF8StringEncoding error:nil];
    if ([legacy containsString:@"gaming"]) return @"gaming";
    if ([legacy containsString:@"streaming"]) return @"streaming";
    return @"off";
}

@interface AntiLagShieldBanner : NSObject <UNUserNotificationCenterDelegate>
@property (nonatomic, weak) id<UNUserNotificationCenterDelegate> previousDelegate;
+ (instancetype)sharedInstance;
- (void)setup;
- (void)postBannerWithMode:(NSString *)mode;
@end

@implementation AntiLagShieldBanner

+ (instancetype)sharedInstance {
    static AntiLagShieldBanner *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AntiLagShieldBanner alloc] init];
    });
    return shared;
}

- (void)setup {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    if (center.delegate && center.delegate != self) {
        self.previousDelegate = center.delegate;
    }
    center.delegate = self;

    UNNotificationAction *streamAction = [UNNotificationAction actionWithIdentifier:@"ACTION_STREAMING"
                                                                              title:@"Streaming Profile"
                                                                            options:UNNotificationActionOptionNone];
    UNNotificationAction *gameAction = [UNNotificationAction actionWithIdentifier:@"ACTION_GAMING"
                                                                           title:@"Gaming Profile"
                                                                         options:UNNotificationActionOptionNone];
    UNNotificationAction *offAction = [UNNotificationAction actionWithIdentifier:@"ACTION_OFF"
                                                                          title:@"Turn Off"
                                                                        options:UNNotificationActionOptionDestructive];

    UNNotificationCategory *shieldCategory = [UNNotificationCategory categoryWithIdentifier:kBannerCategoryID
                                                                                    actions:@[streamAction, gameAction, offAction]
                                                                          intentIdentifiers:@[]
                                                                                    options:UNNotificationCategoryOptionCustomDismissAction];

    [center getNotificationCategoriesWithCompletionHandler:^(NSSet<UNNotificationCategory *> * _Nonnull categories) {
        NSMutableSet<UNNotificationCategory *> *merged = [NSMutableSet set];
        for (UNNotificationCategory *cat in categories) {
            if (![cat.identifier isEqualToString:kBannerCategoryID]) {
                [merged addObject:cat];
            }
        }
        [merged addObject:shieldCategory];
        [center setNotificationCategories:merged];
    }];

    int showToken = 0;
    notify_register_dispatch(kShowBannerNotify, &showToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [[AntiLagShieldBanner sharedInstance] postBannerWithMode:read_current_mode()];
    });

    int stateToken = 0;
    notify_register_dispatch(kStateChangedNotify, &stateToken, dispatch_get_main_queue(), ^(int token) {
        (void)token;
        [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
            for (UNNotification *notif in notifications) {
                if ([notif.request.identifier isEqualToString:kBannerRequestID]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[AntiLagShieldBanner sharedInstance] postBannerWithMode:read_current_mode()];
                    });
                    break;
                }
            }
        }];
    });
}

- (void)postBannerWithMode:(NSString *)mode {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"Anti-Lag Shield";

    if ([mode isEqualToString:@"streaming"]) {
        content.subtitle = @"Active Profile: Streaming";
        content.body = @"4 MB auto-buffers & adaptive ACK enabled. Long-press to switch profiles.";
    } else if ([mode isEqualToString:@"gaming"]) {
        content.subtitle = @"Active Profile: Gaming";
        content.body = @"Immediate ACK (0 ms) & TSO disabled. Long-press to switch profiles.";
    } else {
        content.subtitle = @"Inactive (Stock iOS Defaults)";
        content.body = @"Long-press banner to enable Streaming or Gaming profile.";
    }

    content.categoryIdentifier = kBannerCategoryID;
    content.sound = nil;

    UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:kBannerRequestID
                                                                      content:content
                                                                      trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req withCompletionHandler:nil];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    if (![notification.request.content.categoryIdentifier isEqualToString:kBannerCategoryID]) {
        id<UNUserNotificationCenterDelegate> prev = self.previousDelegate;
        if (prev && [prev respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)]) {
            [prev userNotificationCenter:center willPresentNotification:notification withCompletionHandler:completionHandler];
            return;
        }
        completionHandler(UNNotificationPresentationOptionNone);
        return;
    }

    if (@available(iOS 14.0, *)) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
    } else {
        completionHandler(UNNotificationPresentationOptionAlert);
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
    if (![response.notification.request.content.categoryIdentifier isEqualToString:kBannerCategoryID]) {
        id<UNUserNotificationCenterDelegate> prev = self.previousDelegate;
        if (prev && [prev respondsToSelector:@selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)]) {
            [prev userNotificationCenter:center didReceiveNotificationResponse:response withCompletionHandler:completionHandler];
            return;
        }
        completionHandler();
        return;
    }

    NSString *actionId = response.actionIdentifier;
    if ([actionId isEqualToString:@"ACTION_STREAMING"]) {
        spawn_shield_ctl("start", "streaming");
        [self postBannerWithMode:@"streaming"];
    } else if ([actionId isEqualToString:@"ACTION_GAMING"]) {
        spawn_shield_ctl("start", "gaming");
        [self postBannerWithMode:@"gaming"];
    } else if ([actionId isEqualToString:@"ACTION_OFF"]) {
        spawn_shield_ctl("stop", NULL);
        [self postBannerWithMode:@"off"];
    }

    completionHandler();
}

@end

__attribute__((constructor))
static void initAntiLagShieldBanner(void) {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[AntiLagShieldBanner sharedInstance] setup];
    });
}
