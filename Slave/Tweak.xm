#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Crash Prevention (from reference dylib)

static void ys_uncaughtExceptionHandler(NSException *exception) {
    NSLog(@"[YallaSlave] exception=%@ reason=%@", exception.name, exception.reason);
}

static void ys_signalHandler(int sig) {
    NSLog(@"[YallaSlave] signal=%d", sig);
}

static void ys_installCrashProtection(void) {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        NSSetUncaughtExceptionHandler(&ys_uncaughtExceptionHandler);
        signal(SIGSEGV, ys_signalHandler);
        signal(SIGBUS, ys_signalHandler);
        signal(SIGABRT, ys_signalHandler);
        signal(SIGILL, ys_signalHandler);
    });
}

#define YS_TRY_CXX(op, slot) @try { op; } @catch (NSException *e) { NSLog(@"[YallaSlave] " slot @" CXX exception name=%@ reason=%@", e.name, e.reason); }
#define YS_TRY_MIC(op) @try { op; } @catch (NSException *e) { NSLog(@"[YallaSlave] tapMic exception name=%@ reason=%@", e.name, e.reason); }
#define YS_TRY(op) @try { op; } @catch (NSException *e) { NSLog(@"[YallaSlave] exception=%@ reason=%@", e.name, e.reason); }

static UIWindow *ys_keyWindow(void) {
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

static NSString *const kNotifyPrefix = @"com.yalla.liteagent.cmd.";
static int kMsVals[5] = {50, 25, 10, 5, 1};
static NSString *kNameList[8] = {@"Abdulilah", @"Lahlouh", @"Charo", @"Abu Mutab", @"Saeed", @"Al-Kaed", @"Al-Shammarah", @"Al-Habbas"};

static __weak id s_slaveCachedFace = nil;

static id ys_findMicFace(void) {
    id face = s_slaveCachedFace;
    if (face) return face;
    UIWindow *kw = ys_keyWindow();
    if (!kw) return nil;
    __block id found = nil;
    void (^search)(UIView *) = ^(UIView *v) {
        if (found) return;
        NSString *cn = NSStringFromClass([v class]);
        if ([cn containsString:@"LTLivemikeFace"] || [cn containsString:@"LiveMikeFace"]) { found = v; return; }
        for (UIView *sv in v.subviews) search(sv);
    };
    search(kw);
    if (found) s_slaveCachedFace = found;
    return found;
}

#pragma mark - YSState

@interface YSState : NSObject
@property (nonatomic, assign) int selectedIdx;
@property (nonatomic, assign) int msIdx;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL liteOn;
@property (nonatomic, assign) BOOL cxxOn;
+ (instancetype)s;
- (int)ms;
@end

@implementation YSState
+ (instancetype)s {
    static YSState *x = nil;
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

#pragma mark - Forward declarations

@class YSUI;
static YSUI *gSlaveUI = nil;

static void ys_invokeCxxOnMicFace(void);
static void ys_restoreCxxOnMicFace(void);

#pragma mark - YSUI

@interface YSUI : UIView
@property (nonatomic, strong) UIView *rect;
@property (nonatomic, strong) UIView *circle;
@property (nonatomic, strong) UIView *passcodeView;
@property (nonatomic, strong) NSMutableArray *btns;
@property (nonatomic, strong) UIButton *onBtn, *msBtn, *cxxBtn, *liteBtn, *hideBtn;
@property (nonatomic, strong) UILabel *st;
- (void)build;
- (void)showPasscode;
- (void)doOn;
- (void)doOff;
- (void)doCxxOn;
- (void)doCxxOff;
- (void)doLite:(BOOL)on;
- (void)upd;
@end

@implementation YSUI
- (instancetype)init {
    if ((self = [super init])) {
        self.btns = [NSMutableArray array];
        self.userInteractionEnabled = YES;
        [self showPasscode];
    }
    return self;
}

- (void)showPasscode {
    UIWindow *kw = ys_keyWindow();
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
        if ([v isKindOfClass:[UITextField class]]) { tf = (UITextField *)v; break; }
    }
    NSString *code = tf.text ?: @"";
    if ([code isEqualToString:@"515"]) {
        [self.passcodeView removeFromSuperview];
        self.passcodeView = nil;
        [self build];
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            if (gSlaveUI) [gSlaveUI upd];
        }];
    } else {
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
    UIWindow *kw = ys_keyWindow();
    if (!kw) return;
    CGFloat rw = MIN(kw.bounds.size.width - 20, 350);
    self.rect = [[UIView alloc] initWithFrame:CGRectMake((kw.bounds.size.width - rw)/2, (kw.bounds.size.height - 142)/2 - 40, rw, 142)];
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
    // Numbers LTR: 1 left, 10 right
    UIView *numRow = [[UIView alloc] initWithFrame:CGRectMake(0, 42, rw, 40)];
    CGFloat bw = 26, gap = 4;
    CGFloat startX = (rw - (bw * 10 + gap * 9)) / 2;
    for (int i = 0; i < 10; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(startX + i * (bw + gap), 5, bw, 30);
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
    NSArray *cids = @[@"hide", @"lite", @"cxx", @"ms", @"on"];
    CGFloat cw = (rw - 24) / 5;
    for (int i = 0; i < 5; i++) {
        NSString *cid = cids[i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(10 + (4 - i) * (cw + 2), 87, cw, 30);
        b.layer.cornerRadius = 8;
        b.layer.masksToBounds = YES;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:10];
        b.layer.borderWidth = 1;
        b.backgroundColor = [UIColor blackColor];
        b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        if ([cid isEqualToString:@"on"]) {
            [b setTitle:@"ON" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapOn) forControlEvents:UIControlEventTouchUpInside];
            self.onBtn = b;
        } else if ([cid isEqualToString:@"ms"]) {
            [b setTitle:@"ms:10" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapMs) forControlEvents:UIControlEventTouchUpInside];
            self.msBtn = b;
        } else if ([cid isEqualToString:@"cxx"]) {
            [b setTitle:@"cxx" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapCxx) forControlEvents:UIControlEventTouchUpInside];
            self.cxxBtn = b;
        } else if ([cid isEqualToString:@"lite"]) {
            [b setTitle:@"LiTE" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapLite) forControlEvents:UIControlEventTouchUpInside];
            self.liteBtn = b;
        } else if ([cid isEqualToString:@"hide"]) {
            [b setTitle:@"Hide" forState:UIControlStateNormal];
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
    [kw addSubview:self.rect];
    [kw bringSubviewToFront:self.rect];
    // Drag
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    [self.rect addGestureRecognizer:pan];
    // Circle
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
    YSState *st = [YSState s];
    if (st.isActive) return;
    if (st.selectedIdx == idx) {
        st.selectedIdx = -1;
        s.backgroundColor = [UIColor blackColor];
        s.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        [s setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        return;
    }
    for (UIButton *b in self.btns) {
        b.backgroundColor = [UIColor blackColor];
        b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    st.selectedIdx = idx;
    s.backgroundColor = [UIColor colorWithRed:0 green:0.16 blue:0.04 alpha:0.7];
    s.layer.borderColor = [UIColor colorWithRed:0 green:0.8 blue:0.27 alpha:0.8].CGColor;
    [s setTitleColor:[UIColor colorWithRed:0 green:1 blue:0.33 alpha:0.9] forState:UIControlStateNormal];
    [self upd];
}

- (void)doOn {
    YSState *st = [YSState s];
    if (st.selectedIdx < 0 || st.isActive) return;
    st.isActive = YES;
    [self.onBtn setTitle:@"OFF" forState:UIControlStateNormal];
    self.onBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.1 blue:0.1 alpha:0.9];
    self.onBtn.layer.borderColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.9].CGColor;
    [self.onBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    YS_TRY_MIC({
        id face = ys_findMicFace();
        if (face) {
            int s = st.selectedIdx + 1;
            ((void (*)(id, SEL, id))[face methodForSelector:NSSelectorFromString(@"selectMic:")])(face, NSSelectorFromString(@"selectMic:"), @(s));
            ((void (*)(id, SEL, id))[face methodForSelector:NSSelectorFromString(@"setm6b:")])(face, NSSelectorFromString(@"setm6b:"), @(1));
            ((void (*)(id, SEL, id))[face methodForSelector:NSSelectorFromString(@"masterSetRunUIOnly:")])(face, NSSelectorFromString(@"masterSetRunUIOnly:"), @(1));
        }
    });
    [self upd];
}

- (void)doOff {
    YSState *st = [YSState s];
    if (!st.isActive) return;
    st.isActive = NO;
    [self.onBtn setTitle:@"ON" forState:UIControlStateNormal];
    self.onBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.6 blue:0.1 alpha:0.9];
    self.onBtn.layer.borderColor = [UIColor colorWithRed:0.2 green:1 blue:0.2 alpha:0.9].CGColor;
    [self.onBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    YS_TRY_MIC({
        id face = ys_findMicFace();
        if (face) {
            int s = st.selectedIdx + 1;
            ((void (*)(id, SEL, id))[face methodForSelector:NSSelectorFromString(@"selectMic:")])(face, NSSelectorFromString(@"selectMic:"), @(s));
            ((void (*)(id, SEL, id))[face methodForSelector:NSSelectorFromString(@"setm6b:")])(face, NSSelectorFromString(@"setm6b:"), @(0));
            ((void (*)(id, SEL, id))[face methodForSelector:NSSelectorFromString(@"masterSetRunUIOnly:")])(face, NSSelectorFromString(@"masterSetRunUIOnly:"), @(0));
        }
    });
    [self upd];
}

- (void)tapOn {
    if ([YSState s].isActive) [self doOff]; else [self doOn];
}

- (void)tapMs {
    YSState *st = [YSState s];
    st.msIdx = (st.msIdx + 1) % 5;
    [self.msBtn setTitle:[NSString stringWithFormat:@"ms:%d", [st ms]] forState:UIControlStateNormal];
    if (st.cxxOn) { [self doCxxOff]; [self doCxxOn]; }
    [self upd];
}

- (void)doCxxOn {
    YSState *st = [YSState s];
    if (st.cxxOn) return;
    st.cxxOn = YES;
    self.cxxBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.1 blue:0.6 alpha:0.9];
    self.cxxBtn.layer.borderColor = [UIColor colorWithRed:1 green:0.2 blue:1 alpha:0.9].CGColor;
    ys_invokeCxxOnMicFace();
    [self upd];
}

- (void)doCxxOff {
    YSState *st = [YSState s];
    if (!st.cxxOn) return;
    st.cxxOn = NO;
    self.cxxBtn.backgroundColor = [UIColor blackColor];
    self.cxxBtn.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
    ys_restoreCxxOnMicFace();
    [self upd];
}

- (void)tapCxx {
    if ([YSState s].cxxOn) [self doCxxOff]; else [self doCxxOn];
}

- (void)doLite:(BOOL)on {
    YSState *st = [YSState s];
    if (st.liteOn == on) return;
    st.liteOn = on;
    self.liteBtn.backgroundColor = on ? [UIColor colorWithRed:0.1 green:0.1 blue:0.6 alpha:0.9] : [UIColor blackColor];
    self.liteBtn.layer.borderColor = on ? [UIColor colorWithRed:0.2 green:0.2 blue:1 alpha:0.9].CGColor : [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
    [self.liteBtn setTitle:on ? @"LiTE✓" : @"LiTE" forState:UIControlStateNormal];
    [self upd];
}

- (void)tapLite {
    [self doLite:![YSState s].liteOn];
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
    YSState *st = [YSState s];
    NSString *s = st.selectedIdx >= 0 ? [NSString stringWithFormat:@"Slot %d", (int)(st.selectedIdx + 1)] : @"None";
    NSString *lite = st.liteOn ? @"LiTE✓" : @"";
    NSString *cxx = st.cxxOn ? @"cxx✓" : @"";
    self.st.text = [NSString stringWithFormat:@"%@ | ms:%d | %@ %@", s, [st ms], lite, cxx];
    [self.liteBtn setTitle:st.liteOn ? @"LiTE✓" : @"LiTE" forState:UIControlStateNormal];
}
@end

#pragma mark - CXX standalone functions

static void ys_invokeCxxOnMicFace(void) {
    id face = ys_findMicFace();
    if (!face) return;
    YS_TRY_CXX({
        SEL d6s = NSSelectorFromString(@"d6s:result:");
        if ([face respondsToSelector:d6s]) ((void (*)(id, SEL, id, id))[face methodForSelector:d6s])(face, d6s, @(1), nil);
    }, @"OLD");
    YS_TRY_CXX({
        SEL c7rs = NSSelectorFromString(@"c7rs:result:");
        if ([face respondsToSelector:c7rs]) ((void (*)(id, SEL, id, id))[face methodForSelector:c7rs])(face, c7rs, @(1), nil);
    }, @"OLD");
    YS_TRY_CXX({
        SEL c7rsChat = NSSelectorFromString(@"c7rsInsideChatOnly:result:");
        if ([face respondsToSelector:c7rsChat]) ((void (*)(id, SEL, id, id))[face methodForSelector:c7rsChat])(face, c7rsChat, @(1), nil);
    }, @"OLD");
    YS_TRY_CXX({
        SEL cxx = NSSelectorFromString(@"cxxNoSync");
        if ([face respondsToSelector:cxx]) ((void (*)(id, SEL))[face methodForSelector:cxx])(face, cxx);
    }, @"OLD");
}

static void ys_restoreCxxOnMicFace(void) {
    id face = ys_findMicFace();
    if (!face) return;
    YS_TRY_CXX({
        SEL d6s = NSSelectorFromString(@"d6s:result:");
        if ([face respondsToSelector:d6s]) ((void (*)(id, SEL, id, id))[face methodForSelector:d6s])(face, d6s, @(0), nil);
    }, @"SAFE");
    YS_TRY_CXX({
        SEL c7rs = NSSelectorFromString(@"c7rs:result:");
        if ([face respondsToSelector:c7rs]) ((void (*)(id, SEL, id, id))[face methodForSelector:c7rs])(face, c7rs, @(0), nil);
    }, @"SAFE");
    YS_TRY_CXX({
        SEL c7rsChat = NSSelectorFromString(@"c7rsInsideChatOnly:result:");
        if ([face respondsToSelector:c7rsChat]) ((void (*)(id, SEL, id, id))[face methodForSelector:c7rsChat])(face, c7rsChat, @(0), nil);
    }, @"SAFE");
    YS_TRY_CXX({
        SEL safe = NSSelectorFromString(@"safeCxxNoSync");
        if ([face respondsToSelector:safe]) ((void (*)(id, SEL))[face methodForSelector:safe])(face, safe);
    }, @"SAFE");
}

#pragma mark - YMNotifyClient

@interface YMNotifyClient : NSObject
@property (nonatomic, strong) NSTimer *tapTimer;
@property (nonatomic, strong) NSString *uuid;
@property (nonatomic, assign) int lastSlot;
- (void)start;
- (void)handleCommand:(NSString *)name;
@end

@implementation YMNotifyClient

static void onNotification(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object,
                            CFDictionaryRef userInfo) {
    YMNotifyClient *self = (__bridge YMNotifyClient *)observer;
    NSString *n = (__bridge NSString *)name;
    if ([n hasPrefix:kNotifyPrefix]) {
        NSString *cmd = [n substringFromIndex:kNotifyPrefix.length];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleCommand:cmd];
        });
    }
}

- (instancetype)init {
    if ((self = [super init])) {
        self.uuid = [[NSUUID UUID] UUIDString];
        self.lastSlot = 1;
    }
    return self;
}

- (void)start {
    Class reg = NSClassFromString(@"YMSlaveRegistry");
    if (reg) { YMSlaveRegistry *r = [reg valueForKey:@"shared"]; [r add:self.uuid]; }
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge void *)self,
        onNotification,
        NULL, NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    [self postTap];
    self.tapTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) {
        [self postTap];
    }];
}

- (void)postTap {
    NSString *full = [NSString stringWithFormat:@"com.yalla.liteagent.cmd.tap.%@", self.uuid];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (__bridge CFStringRef)full,
                                          NULL, NULL, true);
}

- (void)handleCommand:(NSString *)cmd {
    YSState *st = [YSState s];
    if ([cmd isEqualToString:@"lite.on"]) {
        if (gSlaveUI) [gSlaveUI doLite:YES];
    } else if ([cmd isEqualToString:@"lite.off"]) {
        if (gSlaveUI) [gSlaveUI doLite:NO];
    } else if ([cmd isEqualToString:@"cxx.face"]) {
        if (gSlaveUI) [gSlaveUI doCxxOn];
    } else if ([cmd isEqualToString:@"cxx.safe"]) {
        if (gSlaveUI) [gSlaveUI doCxxOff];
    } else if ([cmd isEqualToString:@"run.on"]) {
        if (gSlaveUI && !st.isActive) [gSlaveUI doOn];
    } else if ([cmd isEqualToString:@"run.off"]) {
        if (gSlaveUI && st.isActive) [gSlaveUI doOff];
    } else if ([cmd hasPrefix:@"mic."]) {
        int slot = [[cmd substringFromIndex:4] intValue] - 1;
        if (slot >= 0 && slot < 10 && gSlaveUI) {
            st.selectedIdx = -1; // force re-select
            [gSlaveUI tapNum:gSlaveUI.btns[slot]];
        }
    } else if ([cmd hasPrefix:@"speed."]) {
        int ms = [[cmd substringFromIndex:6] intValue];
        for (int i = 0; i < 5; i++) {
            if (kMsVals[i] == ms) {
                st.msIdx = i;
                if (gSlaveUI) {
                    [gSlaveUI.msBtn setTitle:[NSString stringWithFormat:@"ms:%d", ms] forState:UIControlStateNormal];
                    [gSlaveUI upd];
                }
                break;
            }
        }
    }
}

- (void)flash:(UIColor *)c label:(NSString *)l {
    UIWindow *kw = ys_keyWindow();
    if (!kw) return;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(kw.bounds.size.width-70, kw.bounds.size.height-120, 60, 36)];
    v.backgroundColor = c;
    v.layer.cornerRadius = 8;
    v.userInteractionEnabled = NO;
    UILabel *lb = [[UILabel alloc] initWithFrame:v.bounds];
    lb.text = l;
    lb.textColor = [UIColor whiteColor];
    lb.font = [UIFont boldSystemFontOfSize:13];
    lb.textAlignment = NSTextAlignmentCenter;
    [v addSubview:lb];
    [kw addSubview:v];
    [UIView animateWithDuration:0.3 delay:0.7 options:0 animations:^{ v.alpha = 0; } completion:^(BOOL done){ [v removeFromSuperview]; }];
}

- (void)dealloc {
    [self.tapTimer invalidate];
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self);
    Class reg = NSClassFromString(@"YMSlaveRegistry");
    if (reg) { YMSlaveRegistry *r = [reg valueForKey:@"shared"]; [r remove:self.uuid]; }
}
@end

static YMNotifyClient *gClient = nil;

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        ys_installCrashProtection();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!gSlaveUI) gSlaveUI = [[YSUI alloc] init];
        });
        gClient = [[YMNotifyClient alloc] init];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [gClient start];
        });
    }
}
