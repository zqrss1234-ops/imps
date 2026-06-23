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
        __block UIView *found = nil;
        void (^search)(UIView *) = ^(UIView *v) {
            if (found) return;
            NSString *cn = NSStringFromClass([v class]);
            if ([cn containsString:@"LTLivemikeFace"] || [cn containsString:@"LiveMikeFace"]) { found = v; return; }
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
    if (s_lite) [m appendFormat:@" | LiTE✓ %d/%d", s_slaveCount, s_totalEver];
    if (s_cxx) [m appendFormat:@" | cxx✓ %d", s_cxxCount];
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
    s_cxxL.textColor = s_cxx ? clr(200,50,200,1) : [UIColor whiteColor];
    s_cxxL.backgroundColor = s_cxx ? clr(100,20,100,0.9) : [UIColor clearColor];
    s_cxxL.layer.borderColor = s_cxx ? clr(200,50,200,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    if (s_cxx) s_cxxCount = s_slaveCount;
    postCmd(s_cxx ? @"cxx.face" : @"cxx.safe");
    [self upd];
}

- (void)liteT {
    s_lite = !s_lite;
    s_liteL.textColor = s_lite ? clr(50,50,255,1) : [UIColor whiteColor];
    s_liteL.backgroundColor = s_lite ? clr(26,26,150,0.9) : [UIColor clearColor];
    s_liteL.layer.borderColor = s_lite ? clr(50,50,255,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
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
    if (![code isEqualToString:@"515"]) {
        UIColor *orig = s_passField.backgroundColor;
        s_passField.backgroundColor = clr(255,51,51,0.5);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250000000), dispatch_get_main_queue(), ^{
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
    s_panel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.95];
    s_panel.layer.cornerRadius = 18;
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
    sep1.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
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
        b.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
        b.layer.cornerRadius = 7;
        b.tintColor = [UIColor clearColor];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        b.tag = i;
        [b addTarget:self action:@selector(num:) forControlEvents:UIControlEventTouchUpInside];
        [s_panel addSubview:b];
        [s_nums addObject:b];
    }

    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(0, 74, PW, 1)];
    sep2.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
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
    s_onBtn.tintColor = [UIColor clearColor];
    s_onBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [s_onBtn addTarget:self action:@selector(onT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:s_onBtn];

    CGFloat msx = csx + cw + 4;
    s_msL = [self mkL:msx y:82 w:cw h:30 t:@"ms:50" fs:11];
    s_msL.layer.cornerRadius = 8;
    [s_panel addSubview:s_msL];
    UIButton *msB = [UIButton buttonWithType:UIButtonTypeSystem];
    msB.frame = s_msL.frame;
    msB.tintColor = [UIColor clearColor];
    [msB addTarget:self action:@selector(msT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:msB];

    CGFloat cxx = csx + 2*(cw+4);
    s_cxxL = [self mkL:cxx y:82 w:cw h:30 t:@"cxx" fs:11];
    s_cxxL.layer.cornerRadius = 8;
    [s_panel addSubview:s_cxxL];
    UIButton *cxxB = [UIButton buttonWithType:UIButtonTypeSystem];
    cxxB.frame = s_cxxL.frame;
    cxxB.tintColor = [UIColor clearColor];
    [cxxB addTarget:self action:@selector(cxxT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:cxxB];

    CGFloat lx = csx + 3*(cw+4);
    s_liteL = [self mkL:lx y:82 w:cw h:30 t:@"LiTE" fs:11];
    s_liteL.layer.cornerRadius = 8;
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
    hideB.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    hideB.layer.cornerRadius = 8;
    hideB.tintColor = [UIColor clearColor];
    hideB.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [hideB addTarget:self action:@selector(hideT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:hideB];

    // Status
    s_st = [[UILabel alloc] initWithFrame:CGRectMake(8, 118, PW-16, 16)];
    s_st.textColor = [UIColor whiteColor];
    s_st.font = [UIFont systemFontOfSize:10];
    s_st.textAlignment = NSTextAlignmentCenter;
    s_st.text = @"None | OFF | Mic 0 | 50ms";
    [s_panel addSubview:s_st];

    // Info
    UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(8, 136, PW-16, 16)];
    info.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    info.font = [UIFont systemFontOfSize:10];
    info.textAlignment = NSTextAlignmentCenter;
    info.text = @"اختر رقم | LiTE لربط الحسابات | cxx قلتش";
    [s_panel addSubview:info];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panP:)];
    [s_panel addGestureRecognizer:pan];

    [s_overlay addSubview:s_panel];

    // Circle
    CGFloat cs2 = 48;
    s_circle = [[UIView alloc] initWithFrame:CGRectMake(sw-cs2-20, sh/2-cs2/2, cs2, cs2)];
    s_circle.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    s_circle.layer.cornerRadius = cs2/2;
    s_circle.hidden = YES;

    UILabel *cl = [[UILabel alloc] initWithFrame:s_circle.bounds];
    cl.text = @"515";
    cl.textColor = [UIColor colorWithWhite:1 alpha:0.7];
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
    box.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    box.layer.cornerRadius = 16;

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
    s_passField.backgroundColor = clr(20,20,20,0.9);
    s_passField.layer.cornerRadius = 8;
    [box addSubview:s_passField];

    UIButton *ub = [UIButton buttonWithType:UIButtonTypeSystem];
    ub.frame = CGRectMake(30, 96, 160, 34);
    [ub setTitle:@"Unlock" forState:UIControlStateNormal];
    [ub setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ub.backgroundColor = clr(20,20,80,0.9);
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

    s_overlay = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    s_overlay.windowLevel = UIWindowLevelAlert;
    s_overlay.backgroundColor = [UIColor clearColor];
    s_overlay.userInteractionEnabled = YES;
    s_overlay.rootViewController = [[UIViewController alloc] init];
    s_overlay.rootViewController.view.backgroundColor = [UIColor clearColor];
    s_overlay.rootViewController.view.userInteractionEnabled = NO;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                s_overlay.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }
    [s_overlay makeKeyAndVisible];

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

        s_agent = [[YA alloc] init];

        if (s_isMain) {
            dispatch_async(dispatch_get_main_queue(), ^{
                setupMasterUI();
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
