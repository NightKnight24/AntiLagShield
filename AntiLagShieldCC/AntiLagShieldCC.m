#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <spawn.h>

extern char **environ;

@interface CCUIToggleModule : NSObject
- (void)refreshState;
@end

@interface AntiLagShieldCC : CCUIToggleModule
@end

@implementation AntiLagShieldCC

- (UIImage *)iconGlyph {
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:@"shield.fill"];
    }
    return nil;
}

- (UIColor *)selectedColor {
    NSString *state = [NSString stringWithContentsOfFile:@"/var/mobile/Library/Caches/shield_state.txt" encoding:NSUTF8StringEncoding error:nil];
    if ([state containsString:@"gaming"]) {
        return [UIColor colorWithRed:1.00 green:0.58 blue:0.00 alpha:1.0];
    }
    return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0];
}

- (BOOL)isSelected {
    NSString *state = [NSString stringWithContentsOfFile:@"/var/mobile/Library/Caches/shield_state.txt" encoding:NSUTF8StringEncoding error:nil];
    return [state containsString:@"ACTIVE"];
}

- (void)setSelected:(BOOL)selected {
    pid_t pid;
    const char *cmd = selected ? "/var/jb/usr/bin/shield_ctl start streaming" : "/var/jb/usr/bin/shield_ctl stop";
    const char *argv[] = {"/bin/sh", "-c", cmd, NULL};
    posix_spawn(&pid, "/bin/sh", NULL, NULL, (char * const *)argv, environ);
    int status;
    waitpid(pid, &status, 0);
    
    [self refreshState];
}

@end
