#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Crash Prevention (from reference dylib)

static void ym_uncaughtExceptionHandler(NSException *exception) {
    NSLog(@"[YallaMaster] exception=%@ reason=%@", exception.name, exception.reason);
}

static void ym_signalHandler(int sig) {
    NSLog(@"[YallaMaster] signal=%d", sig);
}

static void ym_installCrashProtection(void) {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        NSSetUncaughtExceptionHandler(&ym_uncaughtExceptionHandler);
        signal(SIGSEGV, ym_signalHandler);
        signal(SIGBUS, ym_signalHandler);
        signal(SIGABRT, ym_signalHandler);
        signal(SIGILL, ym_signalHandler);
    });
}

#define YM_TRY_CXX(op, slot) @try { op; } @catch (NSException *e) { NSLog(@"[YallaMaster] " slot @" CXX exception name=%@ reason=%@", e.name, e.reason); }
#define YM_TRY_MIC(op) @try { op; } @catch (NSException *e) { NSLog(@"[YallaMaster] tapMic exception name=%@ reason=%@", e.name, e.reason); }
#define YM_TRY(op) @try { op; } @catch (NSException *e) { NSLog(@"[YallaMaster] exception=%@ reason=%@", e.name, e.reason); }

// Safe keyWindow for iOS 13+ scene-based apps
static UIWindow *ym_keyWindow(void) {
    if (@available(iOS 13, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                UIWindow *w = ws.keyWindow;
                if (w) return w;
            }
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

#pragma mark - Config

static NSString *const kYalla = @"com.yalla.yallalite";
static int const kMsVals[5] = {50, 25, 10, 5, 1};
static NSString *const kNameList[8] = {
    @"Abdulilah", @"Lahlouh", @"Charo", @"Abu Mutab",
    @"Saeed", @"Al-Kaed", @"Al-Shammarah", @"Al-Habbas"
};

#pragma mark - State

@interface YMState : NSObject
@property (nonatomic, assign) int selectedIdx;
@property (nonatomic, assign) int msIdx;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL liteOn;
@property (nonatomic, assign) BOOL cxxOn;
+ (instancetype)s;
- (int)ms;
@end

@implementation YMState
+ (instancetype)s {
    static YMState *x = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ x = [[self alloc] init]; });
    return x;
}
- (instancetype)init {
    if ((self = [super init])) {
        _selectedIdx = -1;
        _msIdx = 2;
        _isActive = NO; _liteOn = NO; _cxxOn = NO;
    }
    return self;
}
- (int)ms { return kMsVals[self.msIdx]; }
@end

#pragma mark - Slave Registry (shared state within process)

@interface YMSlaveRegistry : NSObject
@property (nonatomic, strong) NSMutableSet *slaves;
@property (nonatomic, strong) NSLock *lock;
+ (instancetype)shared;
- (int)count;
- (void)add:(NSString *)uuid;
- (void)remove:(NSString *)uuid;
@end

@implementation YMSlaveRegistry
+ (instancetype)shared {
    static YMSlaveRegistry *x = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ x = [[self alloc] init]; });
    return x;
}
- (instancetype)init {
    if ((self = [super init])) {
        _slaves = [NSMutableSet set];
        _lock = [[NSLock alloc] init];
    }
    return self;
}
- (int)count {
    [_lock lock];
    int c = (int)_slaves.count;
    [_lock unlock];
    return c;
}
- (void)add:(NSString *)uuid {
    [_lock lock];
    [_slaves addObject:uuid];
    [_lock unlock];
}
- (void)remove:(NSString *)uuid {
    [_lock lock];
    [_slaves removeObject:uuid];
    [_lock unlock];
}
@end

#pragma mark - Cross-Process Tap Registry (Darwin heartbeat)

static NSString *const kTapPrefix = @"com.yalla.liteagent.cmd.tap.";

@interface YMTapRegistry : NSObject
@property (nonatomic, strong) NSMutableDictionary *taps;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, assign) int totalEver;
@property (nonatomic, assign) int cxxCount;
+ (instancetype)shared;
- (int)activeCount;
- (void)prune;
@end

@implementation YMTapRegistry
+ (instancetype)shared {
    static YMTapRegistry *x = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ x = [[self alloc] init]; });
    return x;
}
- (instancetype)init {
    if ((self = [super init])) {
        _taps = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc] init];
    }
    return self;
}
- (int)activeCount {
    [_lock lock];
    int c = (int)_taps.count;
    [_lock unlock];
    return c;
}
- (void)receivedTapFromUUID:(NSString *)uuid {
    [_lock lock];
    _taps[uuid] = @([[NSDate date] timeIntervalSince1970]);
    int cur = (int)_taps.count;
    if (cur > _totalEver) _totalEver = cur;
    [_lock unlock];
}
- (void)prune {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [_lock lock];
    NSMutableArray *stale = [NSMutableArray array];
    [_taps enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *val, BOOL *stop) {
        if (now - [val doubleValue] > 12.0) [stale addObject:key];
    }];
    [_taps removeObjectsForKeys:stale];
    [_lock unlock];
}
@end

static void ym_onTapNotification(CFNotificationCenterRef center, void *observer,
                                  CFStringRef name, const void *object,
                                  CFDictionaryRef userInfo) {
    NSString *n = (__bridge NSString *)name;
    if (![n hasPrefix:kTapPrefix]) return;
    NSString *uuid = [n substringFromIndex:kTapPrefix.length];
    if (uuid.length > 0) {
        [[YMTapRegistry shared] receivedTapFromUUID:uuid];
    }
}

static void ym_startTapObserver(void) {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            ym_onTapNotification,
            NULL, // observe all
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        [NSTimer scheduledTimerWithTimeInterval:5.0 repeats:YES block:^(NSTimer *t) {
            [[YMTapRegistry shared] prune];
        }];
    });
}

#pragma mark - Darwin Notification IPC

static __weak id s_cachedMicFace = nil;

static id ym_findMicFace(void) {
    id face = s_cachedMicFace;
    if (face) return face;
    UIWindow *kw = ym_keyWindow();
    if (!kw) return nil;
    __block id found = nil;
    void (^search)(UIView *) = ^(UIView *v) {
        if (found) return;
        NSString *cn = NSStringFromClass([v class]);
        if ([cn containsString:@"LTLivemikeFace"] || [cn containsString:@"LiveMikeFace"]) { found = v; return; }
        for (UIView *sv in v.subviews) search(sv);
    };
    search(kw);
    if (found) s_cachedMicFace = found;
    return found;
}

static NSString *const kNotifyPrefix = @"com.yalla.liteagent.cmd.";

@interface YMNotify : NSObject
- (void)post:(NSString *)name;
- (void)postSpeed:(int)ms;
- (void)postMic:(long)slot;
- (void)postCxx:(BOOL)on;
- (void)postLite:(BOOL)on;
- (void)postRun:(BOOL)on;
- (void)postTap;
@end

@implementation YMNotify
- (void)post:(NSString *)name {
    NSString *full = [kNotifyPrefix stringByAppendingString:name];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (__bridge CFStringRef)full,
                                          NULL, NULL, true);
    NSLog(@"[YallaMaster] posted: %@", full);

    YM_TRY({
        SEL pc = NSSelectorFromString(@"postCommand:");
        id mf = ym_findMicFace();
        if (mf && [mf respondsToSelector:pc]) {
            ((void (*)(id, SEL, id))[mf methodForSelector:pc])(mf, pc, full);
        }
    });
}
- (void)postSpeed:(int)ms {
    [self post:[NSString stringWithFormat:@"speed.%d", ms]];
}
- (void)postMic:(long)slot {
    [self post:[NSString stringWithFormat:@"mic.%ld", (long)slot]];
}
- (void)postCxx:(BOOL)on {
    [self post:on ? @"cxx.face" : @"cxx.safe"];
}
- (void)postLite:(BOOL)on {
    [self post:on ? @"lite.on" : @"lite.off"];
}
- (void)postRun:(BOOL)on {
    [self post:on ? @"run.on" : @"run.off"];
}
- (void)postTap {
    [self post:@"tap"];
}
@end

#pragma mark - Glitch Engine (App Freeze - FlexList CXX Style)

/*
 * The glitch freezes the mic status display inside Yalla Lite
 * while keeping chat and audio functional.
 * Effect: you can't see who raised/lowered their mic = competitive edge.
 *
 * Uses method swizzling at runtime to intercept mic update methods.
 * Replace the placeholder selectors below once headers are available.
 */

@interface YMGlitch : NSObject
@property (nonatomic, assign) BOOL active;
@property (nonatomic, strong) NSTimer *antiLag;
@property (nonatomic, assign) BOOL isFrozen;

+ (instancetype)g;
- (void)enable:(BOOL)en ms:(int)msVal;
- (void)freeze;
- (void)unfreeze;
- (void)invokeCxxOnMicFace;
- (void)invokeSafeCxxOnMicFace;
@end

@implementation YMGlitch

static BOOL glitchBlock = NO;

+ (instancetype)g {
    static YMGlitch *x = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ x = [[self alloc] init]; });
    return x;
}
- (instancetype)init {
    if ((self = [super init])) { }
    return self;
}

- (void)enable:(BOOL)en ms:(int)msVal {
    self.active = en;
    if (self.antiLag) { [self.antiLag invalidate]; self.antiLag = nil; }
    if (en) {
        [self freeze];
        self.antiLag = [NSTimer scheduledTimerWithTimeInterval:MAX(0.5, msVal*0.01) repeats:YES block:^(NSTimer *t) {
            if (glitchBlock) {
                UIWindow *kw = ym_keyWindow();
                if (!kw) return;
                [self invokeCxxOnMicFace];
                [self freezeMicFaceViews:kw];
                [self freezeMicViews:kw];
            }
        }];
    } else {
        [self unfreeze];
    }
}

- (void)freeze {
    glitchBlock = YES;
    self.isFrozen = YES;

    // Try calling cxxNoSync on LTLivemikeFace (from analyzed dylib)
    [self invokeCxxOnMicFace];

    // Hook ALL mic face methods once (FlexList cxx style = freeze the class)
    Class micClass = NSClassFromString(@"LTLivemikeFace");
    if (!micClass) micClass = NSClassFromString(@"YallaLite.LTLivemikeFace");
    if (micClass) {
        static dispatch_once_t mfOnce;
        dispatch_once(&mfOnce, ^{
            unsigned int mc = 0;
            Method *methods = class_copyMethodList(micClass, &mc);
            for (unsigned int i = 0; i < mc; i++) {
                SEL sel = method_getName(methods[i]);
                const char *name = sel_getName(sel);
                NSLog(@"[YallaMaster] LTLivemikeFace: %s", name);

                NSString *s = [NSString stringWithUTF8String:name];
                if ([s containsString:@"cxx"] || [s containsString:@"update"] ||
                    [s containsString:@"refresh"] || [s containsString:@"reload"] ||
                    [s containsString:@"status"] || [s containsString:@"setMic"] ||
                    [s containsString:@"display"] || [s containsString:@"show"] ||
                    [s containsString:@"layout"] || [s containsString:@"render"]) {
                    IMP origIMP = method_getImplementation(methods[i]);
                    method_setImplementation(methods[i], imp_implementationWithBlock(^(id self) {
                        if (!glitchBlock) {
                            ((void (*)(id, SEL))origIMP)(self, sel);
                        }
                    }));
                    NSLog(@"[YallaMaster] HOOKED: %s", name);
                }
            }
            free(methods);

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIWindow *kw = ym_keyWindow();
                if (kw) [self freezeMicFaceViews:kw];
            });
        });

        UIWindow *kw = ym_keyWindow();
        if (kw) [self freezeMicFaceViews:kw];
    }

    static dispatch_once_t roomOnce;
    dispatch_once(&roomOnce, ^{
        NSArray *roomNames = @[@"YallaRoomViewController", @"LTLiveRoomVC",
                               @"RoomViewController", @"YallaLiveViewController"];
        for (NSString *rn in roomNames) {
            Class rc = NSClassFromString(rn);
            if (rc) {
                unsigned int mc = 0;
                Method *methods = class_copyMethodList(rc, &mc);
                for (unsigned int i = 0; i < mc; i++) {
                    SEL sel = method_getName(methods[i]);
                    const char *name = sel_getName(sel);
                    NSString *s = [NSString stringWithUTF8String:name];
                    if ([s containsString:@"refreshMic"] || [s containsString:@"updateMic"] ||
                        [s containsString:@"reloadMicList"] || [s containsString:@"micStatus"] ||
                        [s containsString:@"reloadData"]) {
                        IMP origIMP = method_getImplementation(methods[i]);
                        method_setImplementation(methods[i], imp_implementationWithBlock(^(id self) {
                            if (!glitchBlock) {
                                ((void (*)(id, SEL))origIMP)(self, sel);
                            }
                        }));
                        NSLog(@"[YallaMaster] HOOKED room %@: %s", rn, name);
                    }
                }
                free(methods);
                break;
            }
        }
    });

    UIWindow *kw = ym_keyWindow();
    if (kw) [self freezeMicViews:kw];
}

- (void)unfreeze {
    glitchBlock = NO;
    self.isFrozen = NO;

    [self invokeSafeCxxOnMicFace];

    UIWindow *kw = ym_keyWindow();
    if (kw) [self restoreMicViews:kw];
}

- (void)invokeCxxOnMicFace {
    id face = ym_findMicFace();
    if (!face) return;

    YM_TRY_CXX({
        SEL d6s = NSSelectorFromString(@"d6s:result:");
        if ([face respondsToSelector:d6s]) {
            ((void (*)(id, SEL, id, id))[face methodForSelector:d6s])(face, d6s, @(1), nil);
        }
    }, @"OLD");

    YM_TRY_CXX({
        SEL c7rs = NSSelectorFromString(@"c7rs:result:");
        if ([face respondsToSelector:c7rs]) {
            ((void (*)(id, SEL, id, id))[face methodForSelector:c7rs])(face, c7rs, @(1), nil);
        }
    }, @"OLD");

    YM_TRY_CXX({
        SEL c7rsChat = NSSelectorFromString(@"c7rsInsideChatOnly:result:");
        if ([face respondsToSelector:c7rsChat]) {
            ((void (*)(id, SEL, id, id))[face methodForSelector:c7rsChat])(face, c7rsChat, @(1), nil);
        }
    }, @"OLD");

    YM_TRY_CXX({
        SEL cxxSel = NSSelectorFromString(@"cxxNoSync");
        if ([face respondsToSelector:cxxSel]) {
            ((void (*)(id, SEL))[face methodForSelector:cxxSel])(face, cxxSel);
        }
    }, @"OLD");
}

- (void)invokeSafeCxxOnMicFace {
    id face = ym_findMicFace();
    if (!face) return;

    YM_TRY_CXX({
        SEL d6s = NSSelectorFromString(@"d6s:result:");
        if ([face respondsToSelector:d6s]) {
            ((void (*)(id, SEL, id, id))[face methodForSelector:d6s])(face, d6s, @(0), nil);
        }
    }, @"SAFE");

    YM_TRY_CXX({
        SEL c7rs = NSSelectorFromString(@"c7rs:result:");
        if ([face respondsToSelector:c7rs]) {
            ((void (*)(id, SEL, id, id))[face methodForSelector:c7rs])(face, c7rs, @(0), nil);
        }
    }, @"SAFE");

    YM_TRY_CXX({
        SEL c7rsChat = NSSelectorFromString(@"c7rsInsideChatOnly:result:");
        if ([face respondsToSelector:c7rsChat]) {
            ((void (*)(id, SEL, id, id))[face methodForSelector:c7rsChat])(face, c7rsChat, @(0), nil);
        }
    }, @"SAFE");

    YM_TRY_CXX({
        SEL safeSel = NSSelectorFromString(@"safeCxxNoSync");
        if ([face respondsToSelector:safeSel]) {
            ((void (*)(id, SEL))[face methodForSelector:safeSel])(face, safeSel);
        }
    }, @"SAFE");
}

- (void)freezeMicViews:(UIView *)v {
    [v.subviews enumerateObjectsUsingBlock:^(__kindof UIView *sv, NSUInteger idx, BOOL *stop) {
        NSString *cn = NSStringFromClass([sv class]);
        if ([cn containsString:@"Mic"] || [cn containsString:@"microphone"] ||
            [cn containsString:@"Microphone"] || [cn containsString:@"Voice"] ||
            [cn containsString:@"voice"]) {
            sv.layer.speed = 0.0;
            sv.alpha = MAX(0.02, sv.alpha * 0.3);
        }
        if (sv.subviews.count) [self freezeMicViews:sv];
    }];
}

- (void)restoreMicViews:(UIView *)v {
    [v.subviews enumerateObjectsUsingBlock:^(__kindof UIView *sv, NSUInteger idx, BOOL *stop) {
        NSString *cn = NSStringFromClass([sv class]);
        if ([cn containsString:@"Mic"] || [cn containsString:@"microphone"] ||
            [cn containsString:@"Microphone"] || [cn containsString:@"Voice"] ||
            [cn containsString:@"voice"]) {
            sv.layer.speed = 1.0;
            sv.alpha = MIN(1.0, sv.alpha / 0.3);
        }
        if (sv.subviews.count) [self restoreMicViews:sv];
    }];
}

- (void)freezeMicFaceViews:(UIView *)v {
    for (UIView *sv in v.subviews) {
        NSString *cn = NSStringFromClass([sv class]);
        if ([cn containsString:@"LTLivemikeFace"] || [cn containsString:@"LiveMikeFace"] ||
            [cn containsString:@"mic"] || [cn containsString:@"Mic"] ||
            [cn containsString:@"microphone"] || [cn containsString:@"Microphone"]) {
            sv.layer.speed = 0.0;
            sv.hidden = YES;
        }
        if (sv.subviews.count) [self freezeMicFaceViews:sv];
    }
}

- (void)dealloc {
    [self.antiLag invalidate];
}
@end

#pragma mark - UI

@interface YMUI : UIView
@property (nonatomic, strong) UIView *rect;
@property (nonatomic, strong) UIView *circle;
@property (nonatomic, strong) UIView *passcodeView;
@property (nonatomic, strong) NSMutableArray *btns;
@property (nonatomic, strong) UIButton *onBtn, *msBtn, *cxxBtn, *liteBtn, *hideBtn;
@property (nonatomic, strong) UILabel *st;
@property (nonatomic, strong) YMNotify *notify;
- (void)build;
- (void)showPasscode;
@end

@implementation YMUI
- (instancetype)init {
    if ((self = [super init])) {
        self.btns = [NSMutableArray array];
        self.userInteractionEnabled = YES;
        self.notify = [[YMNotify alloc] init];
        [self showPasscode];
    }
    return self;
}

- (void)showPasscode {
    UIWindow *kw = ym_keyWindow();
    if (!kw) return;

    self.passcodeView = [[UIView alloc] initWithFrame:kw.bounds];
    self.passcodeView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    self.passcodeView.userInteractionEnabled = YES;
    self.passcodeView.tag = 999;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 160)];
    box.center = CGPointMake(kw.bounds.size.width/2, kw.bounds.size.height/2);
    box.backgroundColor = [UIColor blackColor];
    box.layer.cornerRadius = 16;
    box.layer.borderWidth = 2;
    box.layer.borderColor = [UIColor colorWithWhite:0.15 alpha:0.8].CGColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, 220, 30)];
    title.text = @"Abdulilah";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:14];
    title.textAlignment = NSTextAlignmentCenter;
    [box addSubview:title];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(30, 54, 160, 34)];
    tf.placeholder = @"515";
    tf.textAlignment = NSTextAlignmentCenter;
    tf.keyboardType = UIKeyboardTypeNumberPad;
    tf.secureTextEntry = YES;
    tf.textColor = [UIColor whiteColor];
    tf.font = [UIFont boldSystemFontOfSize:18];
    tf.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    tf.layer.cornerRadius = 8;
    tf.layer.borderWidth = 1;
    tf.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:0.8].CGColor;
    [box addSubview:tf];

    UIButton *unlock = [UIButton buttonWithType:UIButtonTypeCustom];
    unlock.frame = CGRectMake(30, 102, 160, 36);
    [unlock setTitle:@"Unlock" forState:UIControlStateNormal];
    [unlock setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    unlock.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.5 alpha:0.9];
    unlock.layer.cornerRadius = 8;
    unlock.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    __weak __typeof__(self) ws = self;
    [unlock addTarget:self action:@selector(passcodeSubmit:) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:unlock];

    [self.passcodeView addSubview:box];
    [kw addSubview:self.passcodeView];
    [kw bringSubviewToFront:self.passcodeView];
    [tf becomeFirstResponder];
}

- (void)passcodeSubmit:(UIButton *)s {
    UIView *box = s.superview;
    UITextField *tf = nil;
    for (UIView *v in box.subviews) {
        if ([v isKindOfClass:[UITextField class]]) {
            tf = (UITextField *)v;
            break;
        }
    }
    NSString *code = tf.text ?: @"";
    if ([code isEqualToString:@"515"]) {
        [self.passcodeView removeFromSuperview];
        self.passcodeView = nil;
        [self build];
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            [self upd];
        }];
    } else {
        // Shake animation
        CABasicAnimation *shake = [CABasicAnimation animationWithKeyPath:@"position"];
        shake.duration = 0.06;
        shake.repeatCount = 3;
        shake.autoreverses = YES;
        shake.fromValue = [NSValue valueWithCGPoint:CGPointMake(box.center.x - 8, box.center.y)];
        shake.toValue = [NSValue valueWithCGPoint:CGPointMake(box.center.x + 8, box.center.y)];
        [box.layer addAnimation:shake forKey:@"shake"];
        tf.text = @"";
    }
}

- (void)build {
    UIWindow *kw = ym_keyWindow();
    if (!kw) return;

    CGFloat rw = MIN(kw.bounds.size.width - 20, 350);
    CGFloat rh = 200;

    self.rect = [[UIView alloc] initWithFrame:CGRectMake((kw.bounds.size.width - rw)/2,
                                                         (kw.bounds.size.height - rh)/2 - 60,
                                                         rw, rh)];
    self.rect.backgroundColor = [UIColor clearColor];
    self.rect.layer.cornerRadius = 18;
    self.rect.layer.borderWidth = 2;
    self.rect.layer.borderColor = [UIColor blackColor].CGColor;
    self.rect.clipsToBounds = YES;

    // Names
    UIView *nr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rw, 38)];
    for (int i = 0; i < 8; i++) {
        int col = i % 4, row = i / 4;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10 + col * ((rw-40)/4 + 5), 6 + row * 16, (rw-40)/4, 14)];
        l.text = kNameList[i];
        l.textColor = [UIColor whiteColor];
        l.font = [UIFont boldSystemFontOfSize:9];
        l.adjustsFontSizeToFitWidth = YES;
        l.minimumScaleFactor = 0.6;
        [nr addSubview:l];
    }
    [self.rect addSubview:nr];

    // Sep
    UIView *s1 = [[UIView alloc] initWithFrame:CGRectMake(0, 38, rw, 1)];
    s1.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.5];
    [self.rect addSubview:s1];

    // Numbers LTR: 1 on left, 10 on right
    UIView *numRow = [[UIView alloc] initWithFrame:CGRectMake(0, 42, rw, 40)];
    numRow.backgroundColor = [UIColor clearColor];
    CGFloat bw = 26, gap = 4;
    CGFloat startX = (rw - (bw * 10 + gap * 9)) / 2;
    for (int i = 0; i < 10; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        CGFloat x = startX + i * (bw + gap);
        b.frame = CGRectMake(x, 5, bw, 30);
        b.layer.cornerRadius = 7;
        b.layer.masksToBounds = YES;
        b.backgroundColor = [UIColor blackColor];
        b.layer.borderWidth = 1.5;
        b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [b setTitle:@(i+1).stringValue forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.tag = i;
        [b addTarget:self action:@selector(tapNum:) forControlEvents:UIControlEventTouchUpInside];
        [numRow addSubview:b];
        [self.btns addObject:b];
    }
    [self.rect addSubview:numRow];

    // Sep
    UIView *s2 = [[UIView alloc] initWithFrame:CGRectMake(0, 82, rw, 1.5)];
    s2.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.5];
    [self.rect addSubview:s2];

    // Controls RTL: hide | lite | cxx | ms | on
    NSArray *ids = @[@"hide", @"lite", @"cxx", @"ms", @"on"];
    CGFloat cw = (rw - 24) / 5;
    for (int i = 0; i < 5; i++) {
        NSString *cid = ids[i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        CGFloat x = 10 + (4 - i) * (cw + 2);
        b.frame = CGRectMake(x, 87, cw, 30);
        b.layer.cornerRadius = 8;
        b.layer.masksToBounds = YES;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:10];
        b.layer.borderWidth = 1;

        if ([cid isEqualToString:@"on"]) {
            b.backgroundColor = [UIColor blackColor];
            b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
            [b setTitle:@"ON" forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapOn) forControlEvents:UIControlEventTouchUpInside];
            self.onBtn = b;
        } else if ([cid isEqualToString:@"ms"]) {
            b.backgroundColor = [UIColor blackColor];
            b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
            [b setTitle:@"ms:10" forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapMs) forControlEvents:UIControlEventTouchUpInside];
            self.msBtn = b;
        } else if ([cid isEqualToString:@"cxx"]) {
            b.backgroundColor = [UIColor blackColor];
            b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
            [b setTitle:@"cxx" forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapCxx) forControlEvents:UIControlEventTouchUpInside];
            self.cxxBtn = b;
        } else if ([cid isEqualToString:@"lite"]) {
            b.backgroundColor = [UIColor blackColor];
            b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
            [b setTitle:@"LiTE" forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapLite) forControlEvents:UIControlEventTouchUpInside];
            self.liteBtn = b;
        } else if ([cid isEqualToString:@"hide"]) {
            b.backgroundColor = [UIColor blackColor];
            b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
            [b setTitle:@"Hide" forState:UIControlStateNormal];
            [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapHide) forControlEvents:UIControlEventTouchUpInside];
            self.hideBtn = b;
        }
        [self.rect addSubview:b];
    }

    // Status
    self.st = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, rw, 16)];
    self.st.textAlignment = NSTextAlignmentCenter;
    self.st.textColor = [UIColor whiteColor];
    self.st.font = [UIFont systemFontOfSize:9];
    [self upd];
    [self.rect addSubview:self.st];

    CGFloat th = 142;
    self.rect.frame = CGRectMake((kw.bounds.size.width - rw)/2, (kw.bounds.size.height - th)/2 - 40, rw, th);

    [kw addSubview:self.rect];
    [kw bringSubviewToFront:self.rect];

    // Draggable panel (from reference dylib: panPanel:)
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    [self.rect addGestureRecognizer:pan];

    // Circle hidden
    self.circle = [[UIView alloc] initWithFrame:CGRectMake(kw.bounds.size.width - 80, kw.bounds.size.height/2 - 25, 48, 48)];
    self.circle.backgroundColor = [UIColor blackColor];
    self.circle.layer.cornerRadius = 24;
    self.circle.layer.borderWidth = 2.5;
    self.circle.layer.borderColor = [UIColor blackColor].CGColor;
    self.circle.hidden = YES;
    self.circle.userInteractionEnabled = YES;
    UILabel *cl = [[UILabel alloc] initWithFrame:self.circle.bounds];
    cl.text = @"515";
    cl.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    cl.font = [UIFont boldSystemFontOfSize:13];
    cl.textAlignment = NSTextAlignmentCenter;
    [self.circle addSubview:cl];
    UITapGestureRecognizer *ct = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showRect)];
    [self.circle addGestureRecognizer:ct];
    UIPanGestureRecognizer *cp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    [self.circle addGestureRecognizer:cp];
    [kw addSubview:self.circle];
}

- (void)tapNum:(UIButton *)s {
    int idx = (int)s.tag;
    YMState *st = [YMState s];
    if (st.isActive) return;

    if (st.selectedIdx == idx) {
        st.selectedIdx = -1;
        s.backgroundColor = [UIColor blackColor];
        s.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        [s setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        return;
    }

    // Deselect all
    for (UIButton *b in self.btns) {
        b.backgroundColor = [UIColor blackColor];
        b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }

    st.selectedIdx = idx;
    s.backgroundColor = [UIColor colorWithRed:0 green:0.16 blue:0.04 alpha:0.7];
    s.layer.borderColor = [UIColor colorWithRed:0 green:0.8 blue:0.27 alpha:0.8].CGColor;
    [s setTitleColor:[UIColor colorWithRed:0 green:1 blue:0.33 alpha:0.9] forState:UIControlStateNormal];
    [self.notify postMic:st.selectedIdx+1];
    [self upd];
}

- (void)tapOn {
    YMState *st = [YMState s];
    if (st.selectedIdx < 0) return;
    st.isActive = !st.isActive;
    [self.onBtn setTitle:st.isActive ? @"OFF" : @"ON" forState:UIControlStateNormal];
    if (st.isActive) {
        self.onBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.1 blue:0.1 alpha:0.9];
        self.onBtn.layer.borderColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.9].CGColor;
        [self.onBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [self.notify postMic:st.selectedIdx+1];
        [self.notify postRun:YES];
    } else {
        self.onBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.1 alpha:0.9];
        self.onBtn.layer.borderColor = [UIColor colorWithRed:0.2 green:1 blue:0.2 alpha:0.9].CGColor;
        [self.onBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [self.notify postMic:st.selectedIdx+1];
        [self.notify postRun:NO];
    }
}

- (void)tapMs {
    YMState *st = [YMState s];
    st.msIdx = (st.msIdx + 1) % 5;
    [self.msBtn setTitle:[NSString stringWithFormat:@"ms:%d", [st ms]] forState:UIControlStateNormal];
    [self.notify postSpeed:[st ms]];
    if (st.cxxOn) [[YMGlitch g] enable:YES ms:[st ms]];
    [self upd];
}

- (void)tapCxx {
    YMState *st = [YMState s];
    st.cxxOn = !st.cxxOn;
    self.cxxBtn.backgroundColor = st.cxxOn ?
        [UIColor colorWithRed:0.6 green:0.1 blue:0.6 alpha:0.9] :
        [UIColor blackColor];
    self.cxxBtn.layer.borderColor = st.cxxOn ?
        [UIColor colorWithRed:1 green:0.2 blue:1 alpha:0.9].CGColor :
        [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
    [[YMGlitch g] enable:st.cxxOn ms:[st ms]];
    [self.notify postSpeed:[st ms]];
    [self.notify postCxx:st.cxxOn];
    [YMTapRegistry shared].cxxCount = st.cxxOn ? [[YMTapRegistry shared] activeCount] : 0;
    [self upd];
}

- (void)tapLite {
    YMState *st = [YMState s];
    st.liteOn = !st.liteOn;
    self.liteBtn.backgroundColor = st.liteOn ?
        [UIColor colorWithRed:0.1 green:0.1 blue:0.6 alpha:0.9] :
        [UIColor blackColor];
    self.liteBtn.layer.borderColor = st.liteOn ?
        [UIColor colorWithRed:0.2 green:0.2 blue:1 alpha:0.9].CGColor :
        [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
    [self.notify postLite:st.liteOn];
    if (st.liteOn) {
        if (st.selectedIdx >= 0 && st.isActive) {
            [self.notify postMic:st.selectedIdx+1];
            [self.notify postRun:YES];
        }
    }
}

- (void)tapHide {
    self.rect.hidden = YES;
    self.circle.hidden = NO;
}

- (void)showRect {
    self.rect.hidden = NO;
    self.circle.hidden = YES;
}

- (void)panPanel:(UIPanGestureRecognizer *)g {
    static CGPoint startCenter;
    UIView *v = g.view;
    if (g.state == UIGestureRecognizerStateBegan) {
        startCenter = v.center;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(startCenter.x + t.x, startCenter.y + t.y);
    }
}

- (void)upd {
    YMState *st = [YMState s];
    YMTapRegistry *reg = [YMTapRegistry shared];
    int cnt = [reg activeCount];
    int cc = reg.cxxCount;
    NSString *s = st.selectedIdx >= 0 ? [NSString stringWithFormat:@"Slot %d", (int)(st.selectedIdx + 1)] : @"None";
    NSString *lite = st.liteOn ? @"LiTE✓" : @"";
    NSString *cxx = st.cxxOn ? @"cxx✓" : @"";
    self.st.text = [NSString stringWithFormat:@"%@ | ms:%d | %@ %@ (%d)", s, [st ms], lite, cxx, cnt];

    // Update button texts with counts
    [self.liteBtn setTitle:st.liteOn ? [NSString stringWithFormat:@"LiTE %d/%d", cnt, reg.totalEver] : @"LiTE" forState:UIControlStateNormal];
    [self.cxxBtn setTitle:st.cxxOn ? [NSString stringWithFormat:@"cxx %d", cc] : @"cxx" forState:UIControlStateNormal];
}
@end

#pragma mark - Hooks

static YMUI *gUI = nil;

#pragma mark - Method Swizzling (Substrate-free)

static void (*orig_viewDidAppear)(id, SEL, BOOL);
static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_viewDidAppear(self, _cmd, animated);
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!gUI) gUI = [[YMUI alloc] init];
        });
    });
}

static void ym_swizzleViewDidAppear(void) {
    Class cls = [UIViewController class];
    SEL sel = @selector(viewDidAppear:);
    Method m = class_getInstanceMethod(cls, sel);
    orig_viewDidAppear = (void(*)(id, SEL, BOOL))method_getImplementation(m);
    method_setImplementation(m, (IMP)hook_viewDidAppear);
}

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        ym_installCrashProtection();
        ym_startTapObserver();
        ym_swizzleViewDidAppear();
        if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:kYalla]) {
            // Background task to keep tweak alive
            static UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
                bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"YallaMasterBG" expirationHandler:^{
                    [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                    bgTask = UIBackgroundTaskInvalid;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"YallaMasterBG" expirationHandler:^{
                            [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                            bgTask = UIBackgroundTaskInvalid;
                        }];
                    });
                }];
            }];
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
                if (bgTask != UIBackgroundTaskInvalid) {
                    [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                    bgTask = UIBackgroundTaskInvalid;
                }
                if (gUI) [gUI upd];
            }];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!gUI) gUI = [[YMUI alloc] init];
            });
        }
    }
}
