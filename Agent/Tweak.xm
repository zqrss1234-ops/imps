#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define kYallaBundle @"com.yalla.yallalite"
#define kNotifyPrefix @"com.yalla.liteagent.cmd."
#define kNotifyHeartbeat @"com.yalla.liteagent.slave.heartbeat"

static NSString *const kNames[] = {
    @"Abdulilah", @"Lahlouh", @"Charo", @"Abu Mutab",
    @"Saeed", @"Al-Kaed", @"Al-Shammarah", @"Al-Habbas"
};
#define kNamesCount 8
static const int kMsVals[] = {50, 25, 10, 5, 1};

static int s_instanceId = 0;
static BOOL s_isMain = NO;

// Master state
static int s_sel = -1;
static int s_msIdx = 0;
static BOOL s_on = NO;
static BOOL s_cxx = NO;
static BOOL s_lite = NO;
static int s_slaveCount = 0;
static int s_totalEver = 0;
static int s_cxxCount = 0;

// Slave state
static int s_slvMsIdx = 2;
static BOOL s_slvLite = NO;
static BOOL s_slvCxx = NO;
static __weak UIView *s_micFace = nil;
static dispatch_source_t s_timer = NULL;

// UI
static UIWindow *s_overlay = nil;
static UIView *s_panel = nil;
static UIView *s_passView = nil;
static UITextField *s_passField = nil;
static UILabel *s_st = nil, *s_msL = nil, *s_cxxL = nil, *s_liteL = nil;
static UIButton *s_onBtn = nil;
static NSMutableArray *s_nums = nil;
static UIView *s_circle = nil;

static UIColor *clr(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a];
}

// Method hooks (no Substrate needed)
static UIWindow *findKeyWindow(void);
static IMP s_orig_didMoveToWindow = NULL;
static IMP s_orig_viewDidAppear = NULL;

static void hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    ((void(*)(id,SEL,BOOL))s_orig_viewDidAppear)(self, _cmd, animated);
    if (!s_overlay) s_overlay = findKeyWindow();
}

static void hook_didMoveToWindow(id self, SEL _cmd) {
    ((void(*)(id,SEL))s_orig_didMoveToWindow)(self, _cmd);
    if (!self) return;
    NSString *cn = NSStringFromClass([self class]);
    if ([cn containsString:@"LTLiveMikeFace"] || [cn containsString:@"LiveMikeFace"])
        s_micFace = self;
}

static void setupHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method m1 = class_getInstanceMethod([UIView class], @selector(didMoveToWindow));
        if (m1) { s_orig_didMoveToWindow = method_getImplementation(m1); method_setImplementation(m1, (IMP)hook_didMoveToWindow); }
        Method m2 = class_getInstanceMethod([UIViewController class], @selector(viewDidAppear:));
        if (m2) { s_orig_viewDidAppear = method_getImplementation(m2); method_setImplementation(m2, (IMP)hook_viewDidAppear); }
    });
}

static void postCmd(NSString *cmd) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)[kNotifyPrefix stringByAppendingString:cmd],
        NULL, NULL, YES);
}

static int getInstanceId(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if ([bid isEqualToString:kYallaBundle]) return 0;
    return [[bid substringFromIndex:kYallaBundle.length] intValue];
}

static UIView *findLiveMikeFace(void) {
    if (s_micFace) return s_micFace;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w || w.hidden) continue;
        __block UIView *found = nil;
        void (^search)(UIView *) = ^(UIView *v) {
            if (found) return;
            NSString *cn = NSStringFromClass([v class]);
            if ([cn containsString:@"LTLiveMikeFace"] || [cn containsString:@"LiveMikeFace"]) { found = v; return; }
            for (UIView *sv in v.subviews) search(sv);
        };
        search(w);
        if (found) { s_micFace = found; return found; }
    }
    return nil;
}

static void callSel(id obj, NSString *selName, id a1, id a2) {
    @try {
        SEL s = NSSelectorFromString(selName);
        if ([obj respondsToSelector:s]) {
            if (a2) ((void(*)(id,SEL,id,id))[obj methodForSelector:s])(obj,s,a1,a2);
            else if (a1) ((void(*)(id,SEL,id))[obj methodForSelector:s])(obj,s,a1);
            else ((void(*)(id,SEL))[obj methodForSelector:s])(obj,s);
        }
    } @catch(NSException *e) {}
}

@interface YA : NSObject @end
@implementation YA

- (void)upd {
    NSString *s = (s_sel >= 1 && s_sel <= kNamesCount) ? kNames[s_sel - 1] : @"None";
    NSString *status = s_on ? @"ON" : @"OFF";
    NSMutableString *m = [NSMutableString stringWithFormat:@"%@ | %@ | Mic %d | %dms",
        s, status, s_sel, kMsVals[s_msIdx]];
    if (s_lite) [m appendFormat:@" | LiTEG�� %d/%d", s_slaveCount, s_totalEver];
    if (s_cxx) [m appendFormat:@" | cxxG�� %d", s_cxxCount];
    s_st.text = m;
    s_liteL.text = s_lite ? [NSString stringWithFormat:@"LiTE %d/%d", s_slaveCount, s_totalEver] : @"LiTE";
    s_cxxL.text = s_cxx ? [NSString stringWithFormat:@"cxx %d", s_cxxCount] : @"cxx";
}

- (void)num:(UIButton *)b {
    if (s_on) return;
    s_sel = (int)b.tag;
    for (UIButton *nb in s_nums) nb.selected = (nb.tag == s_sel);
    [self upd];
}

- (void)onT {
    if (s_sel < 0) return;
    s_on = !s_on;
    [s_onBtn setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
    s_onBtn.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
    s_onBtn.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
    postCmd(s_on ? @"run.on" : @"run.off");
    [self upd];
}

- (void)msT {
    s_msIdx = s_msIdx >= 4 ? 0 : s_msIdx + 1;
    s_msL.text = [NSString stringWithFormat:@"ms:%d", kMsVals[s_msIdx]];
    postCmd([NSString stringWithFormat:@"speed.%d", kMsVals[s_msIdx]]);
    postCmd(@"P.M.S");
    [self upd];
}

- (void)cxxT {
    s_cxx = !s_cxx;
    s_cxxL.textColor = s_cxx ? clr(200,100,255,1) : [UIColor whiteColor];
    s_cxxL.backgroundColor = s_cxx ? clr(60,20,120,0.9) : [UIColor clearColor];
    s_cxxL.layer.borderColor = s_cxx ? clr(200,100,255,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    if (s_cxx) s_cxxCount = s_slaveCount;
    postCmd(s_cxx ? @"cxx.face" : @"cxx.safe");
    [self upd];
}

- (void)liteT {
    s_lite = !s_lite;
    s_liteL.textColor = s_lite ? clr(80,200,255,1) : [UIColor whiteColor];
    s_liteL.backgroundColor = s_lite ? clr(20,60,120,0.9) : [UIColor clearColor];
    s_liteL.layer.borderColor = s_lite ? clr(80,200,255,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    postCmd(s_lite ? @"lite.on" : @"lite.off");
    [self upd];
}

- (void)hideT {
    s_panel.hidden = YES;
    s_circle.hidden = NO;
}

- (void)showPanel {
    s_panel.hidden = NO;
    s_circle.hidden = YES;
}

- (void)submitPass {
    NSString *code = s_passField.text ?: @"";
    if (code.length == 0) return;
    
    if (![code isEqualToString:@"515"]) {
        UIColor *orig = clr(30, 45, 90, 0.9);
        s_passField.backgroundColor = clr(255,51,51,0.5);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300000000), dispatch_get_main_queue(), ^{
            s_passField.backgroundColor = orig;
        });
        s_passField.text = @"";
        return;
    }
    [s_passField resignFirstResponder];
    s_passField = nil;
    [s_passView removeFromSuperview];
    s_passView = nil;
    [self buildUI];
}

- (void)buildUI {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    CGFloat PW = sw < 356 ? sw - 16 : 340;
    CGFloat PX = (sw - PW) / 2;
    CGFloat PY = 120;

    s_panel = [[UIView alloc] initWithFrame:CGRectMake(PX, PY, PW, 230)];
    s_panel.backgroundColor = clr(10, 15, 55, 0.95);
    s_panel.layer.cornerRadius = 18;
    s_panel.layer.borderWidth = 1;
    s_panel.layer.borderColor = clr(40, 70, 150, 0.6).CGColor;
    s_panel.clipsToBounds = YES;
    s_panel.tag = 999;

    // Names
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];
    for (int i = 0; i < kNamesCount; i++) {
        if (i > 0) [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
        [as appendAttributedString:[[NSAttributedString alloc]
            initWithString:kNames[i] attributes:@{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:10],
                NSForegroundColorAttributeName: [UIColor whiteColor]
            }]];
    }
    UILabel *nl = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, PW-20, 20)];
    nl.attributedText = as;
    nl.textAlignment = NSTextAlignmentCenter;
    nl.adjustsFontSizeToFitWidth = YES;
    nl.minimumScaleFactor = 0.4;
    [s_panel addSubview:nl];

    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(0, 32, PW, 1)];
    sep1.backgroundColor = clr(40, 70, 150, 0.4);
    [s_panel addSubview:sep1];

    // Numbers 1-10
    CGFloat ns = (PW - 24) / 9;
    s_nums = [NSMutableArray array];
    for (int i = 1; i <= 10; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        CGFloat bw = ns - 4; if (bw < 22) bw = 22;
        b.frame = CGRectMake(12 + (i-1)*ns, 40, bw, 28);
        [b setTitle:[@(i) stringValue] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleColor:clr(0,255,68,1) forState:UIControlStateSelected];
        b.backgroundColor = clr(20, 30, 70, 0.9);
        b.layer.cornerRadius = 7;
        b.tintColor = [UIColor clearColor];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        b.tag = i;
        [b addTarget:self action:@selector(num:) forControlEvents:UIControlEventTouchUpInside];
        [s_panel addSubview:b];
        [s_nums addObject:b];
    }

    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(0, 74, PW, 1)];
    sep2.backgroundColor = clr(40, 70, 150, 0.4);
    [s_panel addSubview:sep2];

    // Controls
    CGFloat cw = (PW - 24 - 16) / 5;
    if (cw > 62) cw = 62;
    CGFloat ctw = cw * 5 + 16;
    CGFloat csx = (PW - ctw) / 2;

    s_onBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    s_onBtn.frame = CGRectMake(csx, 82, cw, 30);
    [s_onBtn setTitle:@"ON" forState:UIControlStateNormal];
    [s_onBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    s_onBtn.backgroundColor = clr(0,100,0,0.9);
    s_onBtn.layer.cornerRadius = 8;
    s_onBtn.layer.borderWidth = 1;
    s_onBtn.layer.borderColor = clr(0,200,0,0.6).CGColor;
    s_onBtn.tintColor = [UIColor clearColor];
    s_onBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [s_onBtn addTarget:self action:@selector(onT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:s_onBtn];

    CGFloat msx = csx + cw + 4;
    s_msL = [self mkL:msx y:82 w:cw h:30 t:@"ms:50" fs:11];
    s_msL.backgroundColor = clr(20, 30, 70, 0.9);
    s_msL.layer.cornerRadius = 8;
    s_msL.layer.borderWidth = 1;
    s_msL.layer.borderColor = clr(40, 70, 150, 0.5).CGColor;
    [s_panel addSubview:s_msL];
    UIButton *msB = [UIButton buttonWithType:UIButtonTypeSystem];
    msB.frame = s_msL.frame;
    msB.tintColor = [UIColor clearColor];
    [msB addTarget:self action:@selector(msT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:msB];

    CGFloat cxx = csx + 2*(cw+4);
    s_cxxL = [self mkL:cxx y:82 w:cw h:30 t:@"cxx" fs:11];
    s_cxxL.backgroundColor = [UIColor clearColor];
    s_cxxL.layer.cornerRadius = 8;
    s_cxxL.layer.borderWidth = 1;
    s_cxxL.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    [s_panel addSubview:s_cxxL];
    UIButton *cxxB = [UIButton buttonWithType:UIButtonTypeSystem];
    cxxB.frame = s_cxxL.frame;
    cxxB.tintColor = [UIColor clearColor];
    [cxxB addTarget:self action:@selector(cxxT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:cxxB];

    CGFloat lx = csx + 3*(cw+4);
    s_liteL = [self mkL:lx y:82 w:cw h:30 t:@"LiTE" fs:11];
    s_liteL.backgroundColor = [UIColor clearColor];
    s_liteL.layer.cornerRadius = 8;
    s_liteL.layer.borderWidth = 1;
    s_liteL.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    [s_panel addSubview:s_liteL];
    UIButton *liteB = [UIButton buttonWithType:UIButtonTypeSystem];
    liteB.frame = s_liteL.frame;
    liteB.tintColor = [UIColor clearColor];
    [liteB addTarget:self action:@selector(liteT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:liteB];

    CGFloat hx = csx + 4*(cw+4);
    UIButton *hideB = [UIButton buttonWithType:UIButtonTypeSystem];
    hideB.frame = CGRectMake(hx, 82, cw, 30);
    [hideB setTitle:@"Hide" forState:UIControlStateNormal];
    [hideB setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    hideB.backgroundColor = clr(40, 40, 80, 0.9);
    hideB.layer.cornerRadius = 8;
    hideB.layer.borderWidth = 1;
    hideB.layer.borderColor = clr(60, 80, 160, 0.5).CGColor;
    hideB.tintColor = [UIColor clearColor];
    hideB.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [hideB addTarget:self action:@selector(hideT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:hideB];

    // Status
    s_st = [[UILabel alloc] initWithFrame:CGRectMake(8, 118, PW-16, 16)];
    s_st.textColor = clr(150, 180, 255, 1);
    s_st.font = [UIFont systemFontOfSize:10];
    s_st.textAlignment = NSTextAlignmentCenter;
    s_st.text = @"None | OFF | Mic 0 | 50ms";
    [s_panel addSubview:s_st];

    // Info
    UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(8, 136, PW-16, 16)];
    info.textColor = clr(130, 150, 200, 1);
    info.font = [UIFont systemFontOfSize:10];
    info.textAlignment = NSTextAlignmentCenter;
    info.text = @"+�+�+�+� +�+�+� | LiTE +�+�+�++ +�+�+�+�+�+�+�+� | cxx +�+�+�+�";
    [s_panel addSubview:info];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panP:)];
    [s_panel addGestureRecognizer:pan];

    [s_overlay addSubview:s_panel];

    // Circle
    CGFloat cs2 = 48;
    s_circle = [[UIView alloc] initWithFrame:CGRectMake(sw-cs2-20, sh/2-cs2/2, cs2, cs2)];
    s_circle.backgroundColor = clr(10, 15, 55, 0.9);
    s_circle.layer.cornerRadius = cs2/2;
    s_circle.layer.borderWidth = 1;
    s_circle.layer.borderColor = clr(40, 70, 150, 0.6).CGColor;
    s_circle.hidden = YES;

    UILabel *cl = [[UILabel alloc] initWithFrame:s_circle.bounds];
    cl.text = @"515";
    cl.textColor = [UIColor whiteColor];
    cl.font = [UIFont boldSystemFontOfSize:13];
    cl.textAlignment = NSTextAlignmentCenter;
    [s_circle addSubview:cl];

    UITapGestureRecognizer *ct = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showPanel)];
    [s_circle addGestureRecognizer:ct];
    UIPanGestureRecognizer *cp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panC:)];
    [s_circle addGestureRecognizer:cp];

    [s_overlay addSubview:s_circle];
    [self upd];
}

- (UILabel *)mkL:(CGFloat)x y:(CGFloat)y w:(CGFloat)w h:(CGFloat)h t:(NSString *)t fs:(CGFloat)fs {
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, h)];
    lb.text = t;
    lb.textColor = [UIColor whiteColor];
    lb.font = [UIFont boldSystemFontOfSize:fs];
    lb.textAlignment = NSTextAlignmentCenter;
    return lb;
}

- (void)panP:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x+t.x, sc.y+t.y);
    }
}

- (void)panC:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x+t.x, sc.y+t.y);
    }
}

- (void)showPass {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;

    s_passView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, sh)];
    s_passView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    s_passView.userInteractionEnabled = YES;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 150)];
    box.center = CGPointMake(sw/2, sh/2 - 60);
    box.backgroundColor = clr(15, 25, 60, 1);
    box.layer.cornerRadius = 16;
    box.layer.borderWidth = 1;
    box.layer.borderColor = clr(40, 70, 150, 0.6).CGColor;

    UILabel *pt = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, 220, 20)];
    pt.text = @"YallaAgent";
    pt.textColor = [UIColor whiteColor];
    pt.font = [UIFont boldSystemFontOfSize:15];
    pt.textAlignment = NSTextAlignmentCenter;
    [box addSubview:pt];

    s_passField = [[UITextField alloc] initWithFrame:CGRectMake(30, 50, 160, 34)];
    s_passField.placeholder = @"515";
    s_passField.textAlignment = NSTextAlignmentCenter;
    s_passField.keyboardType = UIKeyboardTypeNumberPad;
    s_passField.secureTextEntry = YES;
    s_passField.textColor = [UIColor whiteColor];
    s_passField.font = [UIFont boldSystemFontOfSize:18];
    s_passField.backgroundColor = clr(30, 45, 90, 0.9);
    s_passField.layer.cornerRadius = 8;
    [box addSubview:s_passField];

    UIButton *ub = [UIButton buttonWithType:UIButtonTypeSystem];
    ub.frame = CGRectMake(30, 96, 160, 34);
    [ub setTitle:@"Unlock" forState:UIControlStateNormal];
    [ub setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ub.backgroundColor = clr(30, 60, 140, 0.9);
    ub.layer.cornerRadius = 8;
    ub.tintColor = [UIColor clearColor];
    ub.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [ub addTarget:self action:@selector(submitPass) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:ub];

    [s_passView addSubview:box];
    [s_overlay addSubview:s_passView];
    [s_passField becomeFirstResponder];
}

// Slave
- (void)slvLite:(BOOL)on {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *f = findLiveMikeFace();
        if (!f) return;
        f.hidden = on;
        for (UIView *sv in f.subviews) sv.hidden = on;
        callSel(f, @"lt_rippleButtonAction:", @(on?1:0), nil);
        callSel(f, @"a9xView", nil, nil);
        callSel(f, @"findLiveMikeFace", nil, nil);
    });
}

- (void)slvCxxF {
    dispatch_async(dispatch_get_main_queue(), ^{
        id f = findLiveMikeFace(); if (!f) return;
        callSel(f, @"d6s:result:", @(1), nil);
        callSel(f, @"c7rs:result:", @(1), nil);
        callSel(f, @"c7rsInsideChatOnly:result:", @(1), nil);
        callSel(f, @"cxxNoSync", nil, nil);
        callSel(f, @"g3v:", @(1), nil);
        callSel(f, @"q2f:", @(1), nil);
        callSel(f, @"u8k:", @(1), nil);
        callSel(f, @"scan:result:", @(1), nil);
    });
}

- (void)slvCxxS {
    dispatch_async(dispatch_get_main_queue(), ^{
        id f = findLiveMikeFace(); if (!f) return;
        callSel(f, @"d6s:result:", @(1), nil);
        callSel(f, @"c7rs:result:", @(1), nil);
        callSel(f, @"c7rsInsideChatOnly:result:", @(1), nil);
        callSel(f, @"safeCxxNoSync", nil, nil);
        callSel(f, @"v7l:", @(1), nil);
    });
}

- (void)slvCxxU {
    dispatch_async(dispatch_get_main_queue(), ^{
        id f = findLiveMikeFace(); if (!f) return;
        callSel(f, @"d6s:result:", @(0), nil);
        callSel(f, @"c7rs:result:", @(0), nil);
        callSel(f, @"c7rsInsideChatOnly:result:", @(0), nil);
        callSel(f, @"safeCxxNoSync", nil, nil);
        callSel(f, @"g3v:", @(0), nil);
        callSel(f, @"q2f:", @(0), nil);
        callSel(f, @"u8k:", @(0), nil);
        callSel(f, @"scan:result:", @(0), nil);
        callSel(f, @"v7l:", @(0), nil);
    });
}

- (void)slvMic:(int)s on:(BOOL)a {
    dispatch_async(dispatch_get_main_queue(), ^{
        id f = findLiveMikeFace(); if (!f) return;
        callSel(f, @"selectMic:", @(s), nil);
        callSel(f, @"setm6b:", @(a?1:0), nil);
        callSel(f, @"masterSetRunUIOnly:", @(a?1:0), nil);
        if (a) { callSel(f, @"tapMic", nil, nil); callSel(f, @"tapOnce", nil, nil); }
        callSel(f, @"normalizedDigits:", [NSString stringWithFormat:@"%d", s], nil);
    });
}

- (void)slvSpd:(int)ms {
    s_slvMsIdx = 2;
    for (int i = 0; i < 5; i++) if (kMsVals[i] == ms) { s_slvMsIdx = i; break; }
    if (s_timer) { dispatch_source_cancel(s_timer); s_timer = NULL; }
    dispatch_async(dispatch_get_main_queue(), ^{
        id f = findLiveMikeFace(); if (!f) return;
        callSel(f, @"setSpeed:", @(ms), nil);
        callSel(f, @"changeSpeed", nil, nil);
        callSel(f, @"setStatus", nil, nil);
    });
}

- (void)slvTimer:(int)ms {
    if (s_timer) { dispatch_source_cancel(s_timer); s_timer = NULL; }
    s_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!s_timer) return;
    dispatch_source_set_timer(s_timer, dispatch_time(DISPATCH_TIME_NOW, ms*NSEC_PER_MSEC), ms*NSEC_PER_MSEC, 0);
    dispatch_source_set_event_handler(s_timer, ^{
        id f = findLiveMikeFace(); if (!f) return;
        callSel(f, @"timerTick", nil, nil);
    });
    dispatch_resume(s_timer);
}

- (void)slvRunOn {
    dispatch_async(dispatch_get_main_queue(), ^{
        id f = findLiveMikeFace(); if (!f) return;
        callSel(f, @"selectMic:", @(s_instanceId+1), nil);
        callSel(f, @"setm6b:", @(1), nil);
        callSel(f, @"masterSetRunUIOnly:", @(1), nil);
        callSel(f, @"tapMic", nil, nil);
        callSel(f, @"tapOnce", nil, nil);
        callSel(f, @"isChatRoomTable:", f, nil);
        callSel(f, @"toggleRun", nil, nil);
    });
}

- (void)slvRunOff {
    dispatch_async(dispatch_get_main_queue(), ^{
        id f = findLiveMikeFace(); if (!f) return;
        callSel(f, @"setm6b:", @(0), nil);
        callSel(f, @"masterSetRunUIOnly:", @(0), nil);
        callSel(f, @"toggleRun", nil, nil);
    });
}

- (void)slvCmd:(NSString *)c {
    if ([c isEqualToString:@"lite.on"]) { s_slvLite = YES; [self slvLite:YES]; }
    else if ([c isEqualToString:@"lite.off"]) { s_slvLite = NO; [self slvLite:NO]; }
    else if ([c isEqualToString:@"run.on"]) { [self slvRunOn]; }
    else if ([c isEqualToString:@"run.off"]) { [self slvRunOff]; }
    else if ([c isEqualToString:@"cxx.face"]) { s_slvCxx = YES; [self slvCxxF]; }
    else if ([c isEqualToString:@"cxx.safe"]) { s_slvCxx = YES; [self slvCxxS]; }
    else if ([c hasPrefix:@"speed."]) {
        int ms = [[c substringFromIndex:6] intValue];
        [self slvSpd:ms]; [self slvTimer:ms];
    } else if ([c isEqualToString:@"P.M.S"]) {
        s_slvMsIdx = s_slvMsIdx >= 4 ? 0 : s_slvMsIdx + 1;
        [self slvSpd:kMsVals[s_slvMsIdx]];
        [self slvTimer:kMsVals[s_slvMsIdx]];
    }
}

@end

static YA *s_agent = nil;

static void onNotify(CFNotificationCenterRef c, void *o, CFStringRef n, const void *o2, CFDictionaryRef d) {
    NSString *name = (__bridge NSString *)n;
    if ([name hasPrefix:kNotifyPrefix]) {
        NSString *cmd = [name substringFromIndex:kNotifyPrefix.length];
        dispatch_async(dispatch_get_main_queue(), ^{ [s_agent slvCmd:cmd]; });
    }
}

static void onHeartbeat(CFNotificationCenterRef c, void *o, CFStringRef n, const void *o2, CFDictionaryRef d) {
    NSString *name = (__bridge NSString *)n;
    if ([name hasPrefix:kNotifyHeartbeat]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            s_slaveCount++;
            if (s_slaveCount > s_totalEver) s_totalEver = s_slaveCount;
            if (s_cxx) s_cxxCount = s_slaveCount;
            [s_agent upd];
        });
    }
}

static void ysHandler(NSException *e) {
    NSLog(@"[YA] %@: %@", e.name, e.reason);
}

// ==================== LTLiveMikeFace methods ====================
// These are added via class_addMethod so the Slave code's callSel works.
// Associated object keys
static const char kMicsKey = 0;
static const char kCxxKey = 0;
static const char kRunKey = 0;
static const char kMicKey = 0;
static const char kSpdKey = 0;

// tapMic - find the mic button inside LTLiveMikeFace and simulate tap
static void _tapMic(id self, SEL _cmd) {
    UIView *best = nil;
    for (UIView *sv in [self subviews]) {
        if ([sv isKindOfClass:[UIButton class]]) { best = sv; break; }
        if ([sv isKindOfClass:[UIControl class]]) { best = sv; }
    }
    if (!best) {
        // deeper search
        __block UIView *btn = nil;
        void (^search)(UIView *) = ^(UIView *v) {
            if (btn) return;
            if ([v isKindOfClass:[UIButton class]]) { btn = v; return; }
            for (UIView *sv in v.subviews) search(sv);
        };
        search(self);
        best = btn;
    }
    if (best && [best respondsToSelector:@selector(sendActionsForControlEvents:)]) {
        [(UIControl *)best sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
}

static void _tapOnce(id self, SEL _cmd) {
    objc_setAssociatedObject(self, &kMicKey, @(1), OBJC_ASSOCIATION_RETAIN);
}

static void _selectMic(id self, SEL _cmd, id arg) {
    objc_setAssociatedObject(self, &kMicKey, arg, OBJC_ASSOCIATION_RETAIN);
}

static void _setm6b(id self, SEL _cmd, id arg) {
    objc_setAssociatedObject(self, &kRunKey, arg, OBJC_ASSOCIATION_RETAIN);
}

static void _masterSetRunUIOnly(id self, SEL _cmd, id arg) {
    objc_setAssociatedObject(self, &kRunKey, arg, OBJC_ASSOCIATION_RETAIN);
}

static void _toggleRun(id self, SEL _cmd) {
    id val = objc_getAssociatedObject(self, &kRunKey);
    BOOL on = [val boolValue];
    objc_setAssociatedObject(self, &kRunKey, @(!on), OBJC_ASSOCIATION_RETAIN);
}

static id _isChatRoomTable(id self, SEL _cmd, id arg) {
    UIView *v = self;
    while (v) {
        if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]])
            return @(YES);
        if ([NSStringFromClass([v class]) containsString:@"ChatRoom"])
            return @(YES);
        v = [v superview];
    }
    return @(NO);
}

static void _lt_rippleButtonAction(id self, SEL _cmd, id arg) {
    BOOL on = [arg boolValue];
    UIView *v = (UIView *)self;
    [UIView animateWithDuration:0.25 animations:^{
        if (on) {
            v.transform = CGAffineTransformMakeScale(1.08, 1.08);
            v.alpha = 0.7;
        } else {
            v.transform = CGAffineTransformIdentity;
            v.alpha = 1.0;
        }
    }];
}

static id _a9xView(id self, SEL _cmd) {
    for (UIView *sv in [self subviews]) {
        NSString *cn = NSStringFromClass([sv class]);
        if ([cn containsString:@"A9X"] || [cn containsString:@"Avatar"] || [cn containsString:@"Face"])
            return sv;
    }
    return nil;
}

// scan:result: - scan hierarchy for mic faces, store in associated array
static void _scanResult(id self, SEL _cmd, id arg1, id arg2) {
    NSMutableArray *mics = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w || w.hidden) continue;
        void (^search)(UIView *) = ^(UIView *v) {
            if (!v) return;
            if (v != self && ([NSStringFromClass([v class]) containsString:@"LTLiveMikeFace"] ||
                [NSStringFromClass([v class]) containsString:@"LiveMikeFace"]))
                [mics addObject:v];
            for (UIView *sv in v.subviews) search(sv);
        };
        search(w);
    }
    objc_setAssociatedObject(self, &kMicsKey, mics, OBJC_ASSOCIATION_RETAIN);
}

// d6s:result: - toggle cxx on stored mics
static void _d6sResult(id self, SEL _cmd, id arg1, id arg2) {
    BOOL on = [arg1 boolValue];
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    CGFloat a = on ? 0.3 : 1.0;
    for (UIView *v in mics) {
        v.alpha = a;
        v.userInteractionEnabled = !on;
    }
    objc_setAssociatedObject(self, &kCxxKey, @(on), OBJC_ASSOCIATION_RETAIN);
}

static void _c7rsResult(id self, SEL _cmd, id arg1, id arg2) {
    BOOL on = [arg1 boolValue];
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    for (UIView *v in mics) {
        v.alpha = on ? 0.2 : 1.0;
        v.userInteractionEnabled = !on;
    }
}

static void _cxxNoSync(id self, SEL _cmd) {
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    for (UIView *v in mics) {
        v.userInteractionEnabled = NO;
        v.alpha = 0.15;
    }
}

static void _safeCxxNoSync(id self, SEL _cmd) {
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    for (UIView *v in mics) {
        v.userInteractionEnabled = NO;
        v.alpha = 0.25;
    }
}

// Two-letter property methods - store/retrieve from associated objects
static id _w6m(id self, SEL _cmd) { return objc_getAssociatedObject(self, sel_getName(_cmd)); }
static void _setW6m(id self, SEL _cmd, id val) { objc_setAssociatedObject(self, sel_getName(_cmd), val, OBJC_ASSOCIATION_RETAIN); }
static id _x5n(id self, SEL _cmd) { return objc_getAssociatedObject(self, sel_getName(_cmd)); }
static void _setX5n(id self, SEL _cmd, id val) { objc_setAssociatedObject(self, sel_getName(_cmd), val, OBJC_ASSOCIATION_RETAIN); }
static id _y4o(id self, SEL _cmd) { return objc_getAssociatedObject(self, sel_getName(_cmd)); }
static void _setY4o(id self, SEL _cmd, id val) { objc_setAssociatedObject(self, sel_getName(_cmd), val, OBJC_ASSOCIATION_RETAIN); }
static id _e5t(id self, SEL _cmd) { return objc_getAssociatedObject(self, sel_getName(_cmd)); }
static void _setE5t(id self, SEL _cmd, id val) { objc_setAssociatedObject(self, sel_getName(_cmd), val, OBJC_ASSOCIATION_RETAIN); }
static id _f4u(id self, SEL _cmd) { return objc_getAssociatedObject(self, sel_getName(_cmd)); }
static void _setF4u(id self, SEL _cmd, id val) { objc_setAssociatedObject(self, sel_getName(_cmd), val, OBJC_ASSOCIATION_RETAIN); }

// g3v: / q2f: / u8k: / v7l: - state methods
static id _g3v(id self, SEL _cmd, id arg) { return objc_getAssociatedObject(self, @selector(g3v:)); }
static void _setG3v(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(g3v:), arg, OBJC_ASSOCIATION_RETAIN); }
static id _q2f(id self, SEL _cmd, id arg) { return objc_getAssociatedObject(self, @selector(q2f:)); }
static void _setQ2f(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(q2f:), arg, OBJC_ASSOCIATION_RETAIN); }
static id _u8k(id self, SEL _cmd, id arg) { return objc_getAssociatedObject(self, @selector(u8k:)); }
static void _setU8k(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(u8k:), arg, OBJC_ASSOCIATION_RETAIN); }
static id _v7l(id self, SEL _cmd, id arg) { return objc_getAssociatedObject(self, @selector(v7l:)); }
static void _setV7l(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(v7l:), arg, OBJC_ASSOCIATION_RETAIN); }

static void _setSpeed(id self, SEL _cmd, id arg) {
    objc_setAssociatedObject(self, &kSpdKey, arg, OBJC_ASSOCIATION_RETAIN);
}

static void _changeSpeed(id self, SEL _cmd) {
    // just a trigger - state already stored
}

static void _setStatus(id self, SEL _cmd) {
    // no-op
}

static void _timerTick(id self, SEL _cmd) {
    id val = objc_getAssociatedObject(self, &kCxxKey);
    if ([val boolValue]) {
        NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
        for (UIView *v in mics) {
            v.alpha = 0.15;
        }
    }
}

static id _normalizedDigits(id self, SEL _cmd, id arg) {
    NSString *s = arg;
    s = [s stringByReplacingOccurrencesOfString:@"-" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@""];
    return s;
}

static void setupMFMethods(Class mf) {
    // Each add: (SEL name, IMP func, type encoding)
    #define ADDM(_sel, _imp, _enc) class_addMethod(mf, @selector(_sel), (IMP)_imp, _enc)

    // Two-letter property accessors
    ADDM(w6m, _w6m, "@@:");
    ADDM(setW6m:, _setW6m, "v@:@");
    ADDM(x5n, _x5n, "@@:");
    ADDM(setX5n:, _setX5n, "v@:@");
    ADDM(y4o, _y4o, "@@:");
    ADDM(setY4o:, _setY4o, "v@:@");
    ADDM(e5t, _e5t, "@@:");
    ADDM(setE5t:, _setE5t, "v@:@");
    ADDM(f4u, _f4u, "@@:");
    ADDM(setF4u:, _setF4u, "v@:@");

    // State methods
    ADDM(g3v:, _g3v, "@@:@");
    ADDM(setG3v:, _setG3v, "v@:@");
    ADDM(q2f:, _q2f, "@@:@");
    ADDM(setQ2f:, _setQ2f, "v@:@");
    ADDM(u8k:, _u8k, "@@:@");
    ADDM(setU8k:, _setU8k, "v@:@");
    ADDM(v7l:, _v7l, "@@:@");
    ADDM(setV7l:, _setV7l, "v@:@");

    // Core functionality
    ADDM(tapMic, _tapMic, "v@:");
    ADDM(tapOnce, _tapOnce, "v@:");
    ADDM(selectMic:, _selectMic, "v@:@");
    ADDM(setm6b:, _setm6b, "v@:@");
    ADDM(masterSetRunUIOnly:, _masterSetRunUIOnly, "v@:@");
    ADDM(toggleRun, _toggleRun, "v@:");
    ADDM(isChatRoomTable:, _isChatRoomTable, "@@:@");
    ADDM(lt_rippleButtonAction:, _lt_rippleButtonAction, "v@:@");
    ADDM(a9xView, _a9xView, "@@:");
    ADDM(scan:result:, _scanResult, "v@:@@");
    ADDM(d6s:result:, _d6sResult, "v@:@@");
    ADDM(c7rs:result:, _c7rsResult, "v@:@@");
    ADDM(c7rsInsideChatOnly:result:, _c7rsResult, "v@:@@");
    ADDM(cxxNoSync, _cxxNoSync, "v@:");
    ADDM(safeCxxNoSync, _safeCxxNoSync, "v@:");

    // Speed / status
    ADDM(setSpeed:, _setSpeed, "v@:@");
    ADDM(changeSpeed, _changeSpeed, "v@:");
    ADDM(setStatus, _setStatus, "v@:");
    ADDM(timerTick, _timerTick, "v@:");
    ADDM(normalizedDigits:, _normalizedDigits, "@@:@");
}

static UIWindow *findKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        // iOS 13+: iterate scenes and find first window
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (s.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindowScene *ws = (UIWindowScene *)s;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
            // fallback: first non-hidden full-screen window
            for (UIWindow *w in ws.windows) {
                if (w.hidden || w.windowLevel > UIWindowLevelNormal) continue;
                return w;
            }
            return ws.windows.firstObject;
        }
    }
    // iOS 12 fallback
    if ([UIApplication sharedApplication].keyWindow) return [UIApplication sharedApplication].keyWindow;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) return w;
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

static void setupMasterUI(void) {
    if (s_overlay) return;

    if (@available(iOS 13.0, *)) {
        BOOL found = NO;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                found = YES;
                break;
            }
        }
        if (!found) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{ setupMasterUI(); });
            return;
        }
    }

    s_overlay = findKeyWindow();
    if (!s_overlay) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ setupMasterUI(); });
        return;
    }

#ifdef YM_DIRECT
    [s_agent buildUI];
#else
    [s_agent showPass];
#endif
}

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:kYallaBundle] && ![bid hasPrefix:kYallaBundle]) return;

        // Add LTLiveMikeFace methods so Slave code can call them
        Class mf = NSClassFromString(@"LTLiveMikeFace");
        if (mf) setupMFMethods(mf);

        s_instanceId = getInstanceId();
        s_isMain = [bid isEqualToString:kYallaBundle];

        NSSetUncaughtExceptionHandler(&ysHandler);

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL, onNotify,
            NULL, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL, onHeartbeat,
            NULL, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        setupHooks();

        s_agent = [[YA alloc] init];

        if (s_isMain) {
            dispatch_async(dispatch_get_main_queue(), ^{
                s_overlay = findKeyWindow();
                if (s_overlay) {
                    [s_agent showPass];
                } else {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                        s_overlay = findKeyWindow();
                        if (s_overlay) [s_agent showPass];
                    });
                }
            });
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSString *hb = [NSString stringWithFormat:@"%@.%d", kNotifyHeartbeat, s_instanceId];
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                (__bridge CFStringRef)hb, NULL, NULL, YES);
        });
    }
}
