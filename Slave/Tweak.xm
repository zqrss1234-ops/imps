#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define kNotifyPrefix @"com.yalla.liteagent.cmd."
#define kNotifyHeartbeat @"com.yalla.liteagent.slave.heartbeat"

static int kMsVals[] = {50, 25, 10, 5, 1};
static int s_msIdx = 2;
static int s_msVal = 10;
static BOOL s_liteOn = NO;
static BOOL s_cxxOn = NO;
static BOOL s_safeCxx = NO;
static int s_instanceId = 0;
static __weak UIView *s_micFace = nil;
static dispatch_source_t s_timer = NULL;

static void ysExceptionHandler(NSException *e) {
    NSLog(@"[YallaSlave] %@: %@", e.name, e.reason);
}

static int getInstanceId(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    NSString *prefix = @"com.yalla.yallalite";
    if ([bid isEqualToString:prefix]) return 0;
    return [[bid substringFromIndex:prefix.length] intValue];
}

static UIView *findLiveMikeFace(void) {
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

static void callSel(id obj, NSString *selName, id arg1, id arg2) {
    @try {
        SEL s = NSSelectorFromString(selName);
        if ([obj respondsToSelector:s]) {
            if (arg2) ((void (*)(id, SEL, id, id))[obj methodForSelector:s])(obj, s, arg1, arg2);
            else if (arg1) ((void (*)(id, SEL, id))[obj methodForSelector:s])(obj, s, arg1);
            else ((void (*)(id, SEL))[obj methodForSelector:s])(obj, s);
        }
    } @catch (NSException *e) {
        NSLog(@"callSel exception %@ sel=%@", e.reason, selName);
    }
}

static void toggleLite(void) {
    s_liteOn = !s_liteOn;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *face = findLiveMikeFace();
        if (!face) return;
        face.hidden = s_liteOn;
        for (UIView *sv in face.subviews) sv.hidden = s_liteOn;
        callSel(face, @"lt_rippleButtonAction:", @(s_liteOn ? 1 : 0), nil);
        callSel(face, @"a9xView", nil, nil);
        callSel(face, @"findLiveMikeFace", nil, nil);
    });
}

static void cxxFreeze(void) {
    s_cxxOn = YES;
    s_safeCxx = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"d6s:result:", @(1), nil);
        callSel(face, @"c7rs:result:", @(1), nil);
        callSel(face, @"c7rsInsideChatOnly:result:", @(1), nil);
        callSel(face, @"cxxNoSync", nil, nil);
        callSel(face, @"g3v:", @(1), nil);
        callSel(face, @"q2f:", @(1), nil);
        callSel(face, @"u8k:", @(1), nil);
        callSel(face, @"scan:result:", @(1), nil);
    });
}

static void cxxSafeFreeze(void) {
    s_cxxOn = YES;
    s_safeCxx = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"d6s:result:", @(1), nil);
        callSel(face, @"c7rs:result:", @(1), nil);
        callSel(face, @"c7rsInsideChatOnly:result:", @(1), nil);
        callSel(face, @"safeCxxNoSync", nil, nil);
        callSel(face, @"v7l:", @(1), nil);
    });
}

static void cxxUnfreeze(void) {
    s_cxxOn = NO;
    s_safeCxx = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"d6s:result:", @(0), nil);
        callSel(face, @"c7rs:result:", @(0), nil);
        callSel(face, @"c7rsInsideChatOnly:result:", @(0), nil);
        callSel(face, @"safeCxxNoSync", nil, nil);
        callSel(face, @"g3v:", @(0), nil);
        callSel(face, @"q2f:", @(0), nil);
        callSel(face, @"u8k:", @(0), nil);
        callSel(face, @"scan:result:", @(0), nil);
        callSel(face, @"v7l:", @(0), nil);
    });
}

static void setMic(int slot, BOOL active) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"selectMic:", @(slot), nil);
        callSel(face, @"setm6b:", @(active ? 1 : 0), nil);
        callSel(face, @"masterSetRunUIOnly:", @(active ? 1 : 0), nil);
        callSel(face, @"tapMic", nil, nil);
        callSel(face, @"tapOnce", nil, nil);
        callSel(face, @"normalizedDigits:", [NSString stringWithFormat:@"%d", slot], nil);
    });
}

static void setSpeed(int ms) {
    s_msVal = ms;
    for (int i = 0; i < 5; i++) {
        if (kMsVals[i] == ms) { s_msIdx = i; break; }
    }
    if (s_timer) {
        dispatch_source_cancel(s_timer);
        s_timer = NULL;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"setSpeed:", @(ms), nil);
        callSel(face, @"changeSpeed", nil, nil);
        callSel(face, @"setStatus", nil, nil);
    });
}

static void startTimer(int ms) {
    if (s_timer) {
        dispatch_source_cancel(s_timer);
        s_timer = NULL;
    }
    s_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!s_timer) return;
    dispatch_source_set_timer(s_timer, dispatch_time(DISPATCH_TIME_NOW, ms * NSEC_PER_MSEC), ms * NSEC_PER_MSEC, 0);
    dispatch_source_set_event_handler(s_timer, ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"timerTick", nil, nil);
    });
    dispatch_resume(s_timer);
}

static void handleCmd(NSString *cmd) {
    if ([cmd isEqualToString:@"lite.on"]) {
        s_liteOn = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *face = findLiveMikeFace();
            if (!face) return;
            face.hidden = YES;
            for (UIView *sv in face.subviews) sv.hidden = YES;
            callSel(face, @"lt_rippleButtonAction:", @(1), nil);
        });
    } else if ([cmd isEqualToString:@"lite.off"]) {
        s_liteOn = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *face = findLiveMikeFace();
            if (!face) return;
            face.hidden = NO;
            for (UIView *sv in face.subviews) sv.hidden = NO;
            callSel(face, @"lt_rippleButtonAction:", @(0), nil);
        });
    } else if ([cmd isEqualToString:@"run.on"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            id face = findLiveMikeFace();
            if (!face) return;
            callSel(face, @"selectMic:", @(s_instanceId + 1), nil);
            callSel(face, @"setm6b:", @(1), nil);
            callSel(face, @"masterSetRunUIOnly:", @(1), nil);
            callSel(face, @"tapMic", nil, nil);
            callSel(face, @"tapOnce", nil, nil);
            callSel(face, @"isChatRoomTable:", face, nil);
            callSel(face, @"toggleRun", nil, nil);
        });
    } else if ([cmd isEqualToString:@"run.off"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            id face = findLiveMikeFace();
            if (!face) return;
            callSel(face, @"setm6b:", @(0), nil);
            callSel(face, @"masterSetRunUIOnly:", @(0), nil);
            callSel(face, @"toggleRun", nil, nil);
        });
    } else if ([cmd isEqualToString:@"cxx.face"]) {
        cxxFreeze();
    } else if ([cmd isEqualToString:@"cxx.safe"]) {
        cxxSafeFreeze();
    } else if ([cmd isEqualToString:@"P.M.S"]) {
        s_msIdx = s_msIdx >= 4 ? 0 : s_msIdx + 1;
        s_msVal = kMsVals[s_msIdx];
        setSpeed(s_msVal);
        startTimer(s_msVal);
    } else if ([cmd hasPrefix:@"speed."]) {
        int ms = [[cmd substringFromIndex:6] intValue];
        setSpeed(ms);
        startTimer(ms);
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

        NSSetUncaughtExceptionHandler(&ysExceptionHandler);

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL, onNotify,
            NULL, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSString *hb = [NSString stringWithFormat:@"%@.%d", kNotifyHeartbeat, s_instanceId];
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge CFStringRef)hb, NULL, NULL, YES);
        });
    }
}
