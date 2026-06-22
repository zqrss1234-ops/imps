#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *const kNotifyPrefix = @"com.yalla.liteagent.cmd.";
static int kMsVals[] = {50, 25, 10, 5, 1};
static int s_msIdx = 2;
static BOOL s_liteOn = NO;
static BOOL s_cxxOn = NO;
static int s_instanceId = 0;
static __weak UIView *s_micFace = nil;

static int getInstanceId(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    NSString *prefix = @"com.yalla.yallalite";
    if ([bid isEqualToString:prefix]) return 0;
    return [[bid substringFromIndex:prefix.length] intValue];
}

static UIView *findMicFace(void) {
    if (s_micFace) return s_micFace;
    UIWindow *kw = [UIApplication sharedApplication].keyWindow;
    if (!kw) return nil;
    __block UIView *found = nil;
    void (^search)(UIView *) = ^(UIView *v) {
        if (found) return;
        NSString *cn = NSStringFromClass([v class]);
        if ([cn containsString:@"LTLivemikeFace"] || [cn containsString:@"LiveMikeFace"]) { found = v; return; }
        for (UIView *sv in v.subviews) search(sv);
    };
    search(kw);
    if (found) s_micFace = found;
    return found;
}

static void toggleLite(void) {
    s_liteOn = !s_liteOn;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *face = findMicFace();
        if (!face) return;
        face.hidden = s_liteOn;
        for (UIView *sv in face.subviews) sv.hidden = s_liteOn;
    });
}

static void cxxFreeze(void) {
    s_cxxOn = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findMicFace();
        if (!face) return;
        @try {
            SEL s = NSSelectorFromString(@"d6s:result:");
            if ([face respondsToSelector:s]) ((void (*)(id, SEL, id, id))[face methodForSelector:s])(face, s, @(1), nil);
        } @catch (NSException *e) {}
        @try {
            SEL s = NSSelectorFromString(@"c7rs:result:");
            if ([face respondsToSelector:s]) ((void (*)(id, SEL, id, id))[face methodForSelector:s])(face, s, @(1), nil);
        } @catch (NSException *e) {}
        @try {
            SEL s = NSSelectorFromString(@"c7rsInsideChatOnly:result:");
            if ([face respondsToSelector:s]) ((void (*)(id, SEL, id, id))[face methodForSelector:s])(face, s, @(1), nil);
        } @catch (NSException *e) {}
        @try {
            SEL s = NSSelectorFromString(@"cxxNoSync");
            if ([face respondsToSelector:s]) ((void (*)(id, SEL))[face methodForSelector:s])(face, s);
        } @catch (NSException *e) {}
    });
}

static void cxxUnfreeze(void) {
    s_cxxOn = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findMicFace();
        if (!face) return;
        @try {
            SEL s = NSSelectorFromString(@"d6s:result:");
            if ([face respondsToSelector:s]) ((void (*)(id, SEL, id, id))[face methodForSelector:s])(face, s, @(0), nil);
        } @catch (NSException *e) {}
        @try {
            SEL s = NSSelectorFromString(@"c7rs:result:");
            if ([face respondsToSelector:s]) ((void (*)(id, SEL, id, id))[face methodForSelector:s])(face, s, @(0), nil);
        } @catch (NSException *e) {}
        @try {
            SEL s = NSSelectorFromString(@"c7rsInsideChatOnly:result:");
            if ([face respondsToSelector:s]) ((void (*)(id, SEL, id, id))[face methodForSelector:s])(face, s, @(0), nil);
        } @catch (NSException *e) {}
        @try {
            SEL s = NSSelectorFromString(@"safeCxxNoSync");
            if ([face respondsToSelector:s]) ((void (*)(id, SEL))[face methodForSelector:s])(face, s);
        } @catch (NSException *e) {}
    });
}

static void setMic(int slot, BOOL active) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findMicFace();
        if (!face) return;
        @try {
            SEL sel = NSSelectorFromString(@"selectMic:");
            if ([face respondsToSelector:sel])
                ((void (*)(id, SEL, id))[face methodForSelector:sel])(face, sel, @(slot));
            SEL m6b = NSSelectorFromString(@"setm6b:");
            if ([face respondsToSelector:m6b])
                ((void (*)(id, SEL, id))[face methodForSelector:m6b])(face, m6b, @(active ? 1 : 0));
            SEL runUI = NSSelectorFromString(@"masterSetRunUIOnly:");
            if ([face respondsToSelector:runUI])
                ((void (*)(id, SEL, id))[face methodForSelector:runUI])(face, runUI, @(active ? 1 : 0));
        } @catch (NSException *e) {}
    });
}

static void handleCmd(NSString *cmd) {
    if ([cmd isEqualToString:@"lite"]) {
        toggleLite();
    } else if ([cmd isEqualToString:@"cxx"]) {
        if (s_cxxOn) cxxUnfreeze(); else cxxFreeze();
    } else if ([cmd hasPrefix:@"micon."]) {
        int slot = [[cmd substringFromIndex:6] intValue];
        if (slot >= 1 && slot <= 10) setMic(slot, YES);
    } else if ([cmd hasPrefix:@"micoff."]) {
        int slot = [[cmd substringFromIndex:7] intValue];
        if (slot >= 1 && slot <= 10) setMic(slot, NO);
    } else if ([cmd hasPrefix:@"ms."]) {
        int ms = [[cmd substringFromIndex:3] intValue];
        for (int i = 0; i < 5; i++) {
            if (kMsVals[i] == ms) { s_msIdx = i; break; }
        }
    }
}

static void onNotify(CFNotificationCenterRef c, void *o, CFStringRef n, const void *o2, CFDictionaryRef d) {
    NSString *name = (__bridge NSString *)n;
    if ([name hasPrefix:kNotifyPrefix]) {
        NSString *cmd = [name substringFromIndex:kNotifyPrefix.length];
        dispatch_async(dispatch_get_main_queue(), ^{ handleCmd(cmd); });
    }
}

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        NSString *prefix = @"com.yalla.yallalite";
        if (![bid isEqualToString:prefix] && ![bid hasPrefix:prefix]) return;
        s_instanceId = getInstanceId();

        NSSetUncaughtExceptionHandler(^(NSException *e) {
            NSLog(@"[YallaSlave] %@: %@", e.name, e.reason);
        });

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL, onNotify,
            NULL, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSString *hb = [NSString stringWithFormat:@"com.yalla.liteagent.slave.heartbeat.%d", s_instanceId];
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge CFStringRef)hb, NULL, NULL, YES);
        });
    }
}
