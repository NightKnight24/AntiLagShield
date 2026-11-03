#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <notify.h>
#import <spawn.h>

extern char **environ;

static void run_cmd(const char *cmd) {
    pid_t pid;
    const char *argv[] = {"/bin/sh", "-c", cmd, NULL};
    posix_spawn(&pid, "/bin/sh", NULL, NULL, (char * const *)argv, environ);
    int status;
    waitpid(pid, &status, 0);
}

@interface AntiLagShieldBanner : NSObject <UNUserNotificationCenterDelegate>
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
    center.delegate = self;
    
    UNNotificationAction *streamAction = [UNNotificationAction actionWithIdentifier:@"ACTION_STREAMING"
                                                                              title:@"🎬 Streaming Mode"
                                                                            options:UNNotificationActionOptionNone];
    UNNotificationAction *gameAction = [UNNotificationAction actionWithIdentifier:@"ACTION_GAMING"
                                                                           title:@"🎮 Gaming Mode"
                                                                         options:UNNotificationActionOptionNone];
    UNNotificationAction *offAction = [UNNotificationAction actionWithIdentifier:@"ACTION_OFF"
                                                                         title:@"🛑 Turn Off"
                                                                       options:UNNotificationActionOptionDestructive];

    UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:@"SHIELD_SWITCHER"
                                                                              actions:@[streamAction, gameAction, offAction]
                                                                    intentIdentifiers:@[]
                                                                              options:UNNotificationCategoryOptionCustomDismissAction];

    [center setNotificationCategories:[NSSet setWithObject:category]];
    
    // Register Darwin notification listener for updates from AntiLagShield app
    int token;
    notify_register_dispatch("com.nightknight.antilagshield.updatebanner", &token, dispatch_get_main_queue(), ^(int token) {
        NSString *s = [NSString stringWithContentsOfFile:@"/var/mobile/Library/Caches/shield_state.txt" encoding:NSUTF8StringEncoding error:nil];
        NSString *m = @"off";
        if ([s containsString:@"streaming"]) m = @"streaming";
        else if ([s containsString:@"gaming"]) m = @"gaming";
        [[AntiLagShieldBanner sharedInstance] postBannerWithMode:m];
    });
    
    // Post initial banner if shield is currently active
    NSString *s = [NSString stringWithContentsOfFile:@"/var/mobile/Library/Caches/shield_state.txt" encoding:NSUTF8StringEncoding error:nil];
    if ([s containsString:@"streaming"]) {
        [self postBannerWithMode:@"streaming"];
    } else if ([s containsString:@"gaming"]) {
        [self postBannerWithMode:@"gaming"];
    }
}

- (void)postBannerWithMode:(NSString *)mode {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"🛡️ Anti-Lag Shield Pro";
    
    if ([mode isEqualToString:@"streaming"]) {
        content.subtitle = @"Current Mode: 🎬 Streaming (Active)";
        content.body = @"Retina throughput & zero stutter. Pull down or hold banner to toggle.";
    } else if ([mode isEqualToString:@"gaming"]) {
        content.subtitle = @"Current Mode: 🎮 Gaming (Active)";
        content.body = @"0ms instant ACK & anti-bufferbloat active. Pull down or hold banner to toggle.";
    } else {
        content.subtitle = @"Status: 🛑 Off (Stock iOS)";
        content.body = @"Pull down or hold banner to quickly enable Streaming or Gaming.";
    }
    
    content.categoryIdentifier = @"SHIELD_SWITCHER";
    content.sound = nil;
    
    UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:@"antilag_shield_banner"
                                                                      content:content
                                                                      trigger:nil];
    [center addNotificationRequest:req withCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[AntiLagShieldBanner] Error adding request: %@", error);
        } else {
            NSLog(@"[AntiLagShieldBanner] Successfully posted banner with mode: %@", mode);
        }
    }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    if (@available(iOS 14.0, *)) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
    } else {
        completionHandler(UNNotificationPresentationOptionAlert);
    }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
    NSString *actionId = response.actionIdentifier;
    
    if ([actionId isEqualToString:@"ACTION_STREAMING"]) {
        run_cmd("/var/jb/usr/bin/shield_ctl start streaming");
        [self postBannerWithMode:@"streaming"];
        notify_post("com.nightknight.antilagshield.modetag");
    } else if ([actionId isEqualToString:@"ACTION_GAMING"]) {
        run_cmd("/var/jb/usr/bin/shield_ctl start gaming");
        [self postBannerWithMode:@"gaming"];
        notify_post("com.nightknight.antilagshield.modetag");
    } else if ([actionId isEqualToString:@"ACTION_OFF"]) {
        run_cmd("/var/jb/usr/bin/shield_ctl stop");
        [self postBannerWithMode:@"off"];
        notify_post("com.nightknight.antilagshield.modetag");
    }
    
    completionHandler();
}

@end

__attribute__((constructor))
static void initBannerTweak() {
    // Delay slightly to ensure SpringBoard's UserNotifications server is running
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[AntiLagShieldBanner sharedInstance] setup];
    });
}
