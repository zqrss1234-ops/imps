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
static int kMsValsLen = 5;

// === State ===
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
static int s_slvMsVal = 10;
static BOOL s_slvLite = NO;
static BOOL s_slvCxx = NO;
static BOOL s_slvSafeCxx = NO;
static __weak UIView *s_micFace = nil;
static dispatch_source_t s_timer = NULL;

// UI
static UIView *s_panel;
static UIView *s_passView;
static UITextField *s_passField;
static UILabel *s_st, *s_msL, *s_cxxL, *s_liteL;
static UIButton *s_onBtn;
static NSMutableArray *s_nums;
static UIView *s_circle;
static BOOL s_visible = YES;

// === Helpers ===
static UIColor *clr(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a];
}

static void postCmd(NSString *cmd) {
    NSString *name = [kNotifyPrefix stringByAppendingString:cmd];
    NSLog(@"postCommand %@", name);
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)name, NULL, NULL, YES);
}

static int getInstanceId(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    if ([bid isEqualToString:kYallaBundle]) return 0;
    return [[bid substringFromIndex:kYallaBundle.length] intValue];
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

// === Master UI ===
static UILabel *mkLab(CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSString *t, CGFloat fs) {
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, h)];
    lb.text = t;
    lb.textColor = [UIColor whiteColor];
    lb.font = [UIFont boldSystemFontOfSize:fs];
    lb.textAlignment = NSTextAlignmentCenter;
    lb.userInteractionEnabled = NO;
    return lb;
}

static UIView *mkSep(CGFloat x, CGFloat y, CGFloat w) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, 1)];
    v.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
    v.userInteractionEnabled = NO;
    return v;
}

@interface _YM : NSObject @end
@implementation _YM

+ (void)upd {
    NSString *s = s_sel >= 0 ? kNames[s_sel] : @"None";
    NSString *status = s_on ? @"ON" : @"OFF";
    NSString *liteSuf = s_lite ? [NSString stringWithFormat:@" | LiTE✓ %d/%d", s_slaveCount, s_totalEver] : @"";
    NSString *cxxSuf = s_cxx ? [NSString stringWithFormat:@" | cxx✓ %d", s_cxxCount] : @"";
    s_st.text = [NSString stringWithFormat:@"%@ | %@ | Mic %d | %dms%@%@",
        s, status, s_sel + 1, kMsVals[s_msIdx], liteSuf, cxxSuf];

    if (s_lite) s_liteL.text = [NSString stringWithFormat:@"LiTE %d/%d", s_slaveCount, s_totalEver];
    else s_liteL.text = @"LiTE";
    if (s_cxx) s_cxxL.text = [NSString stringWithFormat:@"cxx %d", s_cxxCount];
    else s_cxxL.text = @"cxx";
}

+ (void)num:(UIButton *)b {
    if (s_on) return;
    int idx = (int)b.tag;
    s_sel = idx;
    for (UIButton *nb in s_nums) nb.selected = (nb.tag == idx);
    [self upd];
}

+ (void)onT {
    if (s_sel < 0) return;
    s_on = !s_on;
    [s_onBtn setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
    s_onBtn.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
    s_onBtn.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
    postCmd(s_on ? @"run.on" : @"run.off");
    [self upd];
}

+ (void)msT {
    s_msIdx = s_msIdx >= 4 ? 0 : s_msIdx + 1;
    s_msL.text = [NSString stringWithFormat:@"ms:%d", kMsVals[s_msIdx]];
    postCmd([NSString stringWithFormat:@"speed.%d", kMsVals[s_msIdx]]);
    postCmd(@"P.M.S");
    [self upd];
}

+ (void)cxxT {
    s_cxx = !s_cxx;
    s_cxxL.textColor = s_cxx ? clr(200,50,200,1) : [UIColor whiteColor];
    s_cxxL.backgroundColor = s_cxx ? clr(100,20,100,0.9) : [UIColor clearColor];
    s_cxxL.layer.borderColor = s_cxx ? clr(200,50,200,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    if (s_cxx) s_cxxCount = s_slaveCount;
    postCmd(s_cxx ? @"cxx.face" : @"cxx.safe");
    [self upd];
}

+ (void)liteT {
    s_lite = !s_lite;
    s_liteL.textColor = s_lite ? clr(50,50,255,1) : [UIColor whiteColor];
    s_liteL.backgroundColor = s_lite ? clr(26,26,150,0.9) : [UIColor clearColor];
    s_liteL.layer.borderColor = s_lite ? clr(50,50,255,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    postCmd(s_lite ? @"lite.on" : @"lite.off");
    [self upd];
}

+ (void)showPanel {
    s_panel.hidden = NO;
    s_circle.hidden = YES;
    s_visible = YES;
}

+ (void)hideT {
    s_visible = NO;
    s_panel.hidden = YES;
    s_circle.hidden = NO;
}

+ (void)submitPass {
    NSString *code = s_passField.text ?: @"";
    if (![code isEqualToString:@"515"]) {
        UIColor *orig = s_passField.backgroundColor;
        s_passField.backgroundColor = clr(255,51,51,0.5);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
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

static void onHeartbeat(CFNotificationCenterRef c, void *o, CFStringRef n, const void *o2, CFDictionaryRef d) {
    dispatch_async(dispatch_get_main_queue(), ^{
        s_slaveCount++;
        if (s_slaveCount > s_totalEver) s_totalEver = s_slaveCount;
        if (s_cxx) s_cxxCount = s_slaveCount;
        [_YM upd];
    });
}

+ (void)buildUI {
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (!kw) return;
    UIView *cv = kw.rootViewController.view;
    if (!cv) return;

    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat PW = 340;
    if (sw < PW + 16) PW = sw - 16;
    CGFloat PX = (sw - PW) / 2;
    CGFloat PY = 120;

    s_panel = [[UIView alloc] initWithFrame:CGRectMake(PX, PY, PW, 230)];
    s_panel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    s_panel.layer.cornerRadius = 18;
    s_panel.layer.borderWidth = 2;
    s_panel.layer.borderColor = [UIColor blackColor].CGColor;
    s_panel.clipsToBounds = YES;
    s_panel.tag = 999;

    // Names row
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];
    for (int i = 0; i < kNamesCount; i++) {
        if (i > 0) [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"  "]];
        [as appendAttributedString:[[NSAttributedString alloc]
            initWithString:kNames[i]
            attributes:@{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:10],
                NSForegroundColorAttributeName: [UIColor whiteColor]
            }]];
    }
    UILabel *nl = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, PW - 20, 20)];
    nl.attributedText = as;
    nl.textAlignment = NSTextAlignmentCenter;
    nl.adjustsFontSizeToFitWidth = YES;
    nl.minimumScaleFactor = 0.4;
    nl.userInteractionEnabled = NO;
    [s_panel addSubview:nl];

    [s_panel addSubview:mkSep(0, 32, PW)];

    // Numbers 1-10
    CGFloat numStartX = 12;
    CGFloat numTotalW = PW - 24;
    CGFloat numSpacing = numTotalW / 9;
    s_nums = [NSMutableArray array];
    for (int i = 1; i <= 10; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        CGFloat bx = numStartX + (i - 1) * numSpacing;
        CGFloat bw = numSpacing - 4;
        if (bw < 22) bw = 22;
        b.frame = CGRectMake(bx, 40, bw, 28);
        [b setTitle:[@(i) stringValue] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleColor:clr(0,255,68,1) forState:UIControlStateSelected];
        b.backgroundColor = [UIColor blackColor];
        b.layer.cornerRadius = 7;
        b.layer.borderWidth = 1.5;
        b.layer.borderColor = clr(26,26,26,0.6).CGColor;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        b.tag = i;
        [b addTarget:self action:@selector(num:) forControlEvents:UIControlEventTouchUpInside];
        [s_panel addSubview:b];
        [s_nums addObject:b];
    }

    [s_panel addSubview:mkSep(0, 74, PW)];

    // Controls
    CGFloat cw = (PW - 24 - 4 * 4) / 5;
    if (cw > 62) cw = 62;
    CGFloat cTotalW = cw * 5 + 4 * 4;
    CGFloat cStartX = (PW - cTotalW) / 2;

    s_onBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    s_onBtn.frame = CGRectMake(cStartX, 82, cw, 30);
    [s_onBtn setTitle:@"ON" forState:UIControlStateNormal];
    [s_onBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    s_onBtn.backgroundColor = clr(0,100,0,0.9);
    s_onBtn.layer.cornerRadius = 8;
    s_onBtn.layer.borderWidth = 1.5;
    s_onBtn.layer.borderColor = clr(0,255,0,0.9).CGColor;
    s_onBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [s_onBtn addTarget:self action:@selector(onT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:s_onBtn];

    CGFloat msX = cStartX + (cw + 4);
    s_msL = mkLab(msX, 82, cw, 30, @"ms:50", 11);
    s_msL.layer.borderWidth = 1.5;
    s_msL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_msL.layer.cornerRadius = 8;
    [s_panel addSubview:s_msL];
    UIButton *msBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    msBtn.frame = CGRectMake(msX, 82, cw, 30);
    msBtn.backgroundColor = [UIColor clearColor];
    [msBtn addTarget:self action:@selector(msT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:msBtn];

    CGFloat cxxX = cStartX + 2 * (cw + 4);
    s_cxxL = mkLab(cxxX, 82, cw, 30, @"cxx", 11);
    s_cxxL.layer.borderWidth = 1.5;
    s_cxxL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_cxxL.layer.cornerRadius = 8;
    [s_panel addSubview:s_cxxL];
    UIButton *cxxBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cxxBtn.frame = CGRectMake(cxxX, 82, cw, 30);
    cxxBtn.backgroundColor = [UIColor clearColor];
    [cxxBtn addTarget:self action:@selector(cxxT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:cxxBtn];

    CGFloat liteX = cStartX + 3 * (cw + 4);
    s_liteL = mkLab(liteX, 82, cw, 30, @"LiTE", 11);
    s_liteL.layer.borderWidth = 1.5;
    s_liteL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_liteL.layer.cornerRadius = 8;
    [s_panel addSubview:s_liteL];
    UIButton *liteBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    liteBtn.frame = CGRectMake(liteX, 82, cw, 30);
    liteBtn.backgroundColor = [UIColor clearColor];
    [liteBtn addTarget:self action:@selector(liteT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:liteBtn];

    CGFloat hideX = cStartX + 4 * (cw + 4);
    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    hideBtn.frame = CGRectMake(hideX, 82, cw, 30);
    [hideBtn setTitle:@"Hide" forState:UIControlStateNormal];
    [hideBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    hideBtn.backgroundColor = [UIColor blackColor];
    hideBtn.layer.cornerRadius = 8;
    hideBtn.layer.borderWidth = 1.5;
    hideBtn.layer.borderColor = clr(26,26,26,0.6).CGColor;
    hideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [hideBtn addTarget:self action:@selector(hideT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:hideBtn];

    // Status
    s_st = [[UILabel alloc] initWithFrame:CGRectMake(8, 118, PW - 16, 16)];
    s_st.textColor = [UIColor whiteColor];
    s_st.font = [UIFont systemFontOfSize:10];
    s_st.textAlignment = NSTextAlignmentCenter;
    s_st.text = @"None | OFF | Mic 0 | 50ms";
    [s_panel addSubview:s_st];

    // Info text
    UILabel *infoL = [[UILabel alloc] initWithFrame:CGRectMake(8, 136, PW - 16, 16)];
    infoL.textColor = [UIColor whiteColor];
    infoL.font = [UIFont systemFontOfSize:10];
    infoL.textAlignment = NSTextAlignmentCenter;
    infoL.text = @"اختر رقم | LiTE لربط الحسابات | cxx قلتش";
    [s_panel addSubview:infoL];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    [s_panel addGestureRecognizer:pan];

    [cv addSubview:s_panel];

    // Circle
    CGFloat cs = 48;
    CGFloat cx2 = sw - cs - 20;
    CGFloat cy2 = [UIScreen mainScreen].bounds.size.height / 2 - cs / 2;
    s_circle = [[UIView alloc] initWithFrame:CGRectMake(cx2, cy2, cs, cs)];
    s_circle.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    s_circle.layer.cornerRadius = cs / 2;
    s_circle.layer.borderWidth = 2.5;
    s_circle.layer.borderColor = [UIColor blackColor].CGColor;
    s_circle.hidden = YES;
    s_circle.userInteractionEnabled = YES;

    UILabel *cl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, cs, cs)];
    cl.text = @"515";
    cl.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    cl.font = [UIFont boldSystemFontOfSize:13];
    cl.textAlignment = NSTextAlignmentCenter;
    cl.userInteractionEnabled = NO;
    [s_circle addSubview:cl];

    UITapGestureRecognizer *ctap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showPanel)];
    [s_circle addGestureRecognizer:ctap];

    UIPanGestureRecognizer *cpan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panCircle:)];
    [s_circle addGestureRecognizer:cpan];

    [cv addSubview:s_circle];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        onHeartbeat,
        (__bridge CFStringRef)@"com.yalla.liteagent.slave.heartbeat",
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);

    [self upd];
}

+ (void)panPanel:(UIPanGestureRecognizer *)g {
    static CGPoint startCenter;
    UIView *v = g.view;
    if (g.state == UIGestureRecognizerStateBegan) startCenter = v.center;
    if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(startCenter.x + t.x, startCenter.y + t.y);
    }
}

+ (void)panCircle:(UIPanGestureRecognizer *)g {
    static CGPoint startCenter;
    UIView *v = g.view;
    if (g.state == UIGestureRecognizerStateBegan) startCenter = v.center;
    if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(startCenter.x + t.x, startCenter.y + t.y);
    }
}

+ (void)showPass {
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (!kw) return;
    UIView *cv = kw.rootViewController.view;
    if (!cv) return;

    s_passView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    s_passView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 150)];
    box.center = CGPointMake(s_passView.center.x, s_passView.center.y - 60);
    box.backgroundColor = [UIColor blackColor];
    box.layer.cornerRadius = 16;
    box.layer.borderWidth = 2;
    box.layer.borderColor = clr(26,26,26,0.8).CGColor;

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
    s_passField.layer.borderWidth = 1;
    s_passField.layer.borderColor = clr(50,50,50,0.8).CGColor;
    [box addSubview:s_passField];

    UIButton *unlockBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    unlockBtn.frame = CGRectMake(30, 96, 160, 34);
    [unlockBtn setTitle:@"Unlock" forState:UIControlStateNormal];
    [unlockBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    unlockBtn.backgroundColor = clr(20,20,80,0.9);
    unlockBtn.layer.cornerRadius = 8;
    unlockBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [unlockBtn addTarget:self action:@selector(submitPass) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:unlockBtn];

    [s_passView addSubview:box];
    [cv addSubview:s_passView];
    [s_passField becomeFirstResponder];
}

// === Slave handlers ===
+ (void)slvToggleLite:(BOOL)on {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *face = findLiveMikeFace();
        if (!face) return;
        face.hidden = on;
        for (UIView *sv in face.subviews) sv.hidden = on;
        callSel(face, @"lt_rippleButtonAction:", @(on ? 1 : 0), nil);
        callSel(face, @"a9xView", nil, nil);
        callSel(face, @"findLiveMikeFace", nil, nil);
    });
}

+ (void)slvCxxFreeze {
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

+ (void)slvCxxSafeFreeze {
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

+ (void)slvCxxUnfreeze {
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

+ (void)slvSetMicOn:(int)slot {
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"selectMic:", @(slot), nil);
        callSel(face, @"setm6b:", @(1), nil);
        callSel(face, @"masterSetRunUIOnly:", @(1), nil);
        callSel(face, @"tapMic", nil, nil);
        callSel(face, @"tapOnce", nil, nil);
        callSel(face, @"normalizedDigits:", [NSString stringWithFormat:@"%d", slot], nil);
    });
}

+ (void)slvSetMicOff:(int)slot {
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"selectMic:", @(slot), nil);
        callSel(face, @"setm6b:", @(0), nil);
        callSel(face, @"masterSetRunUIOnly:", @(0), nil);
    });
}

+ (void)slvSetSpeed:(int)ms {
    s_slvMsVal = ms;
    for (int i = 0; i < 5; i++) {
        if (kMsVals[i] == ms) { s_slvMsIdx = i; break; }
    }
    if (s_timer) { dispatch_source_cancel(s_timer); s_timer = NULL; }
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"setSpeed:", @(ms), nil);
        callSel(face, @"changeSpeed", nil, nil);
        callSel(face, @"setStatus", nil, nil);
    });
}

+ (void)slvStartTimer:(int)ms {
    if (s_timer) { dispatch_source_cancel(s_timer); s_timer = NULL; }
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

+ (void)slvRunOn {
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
}

+ (void)slvRunOff {
    dispatch_async(dispatch_get_main_queue(), ^{
        id face = findLiveMikeFace();
        if (!face) return;
        callSel(face, @"setm6b:", @(0), nil);
        callSel(face, @"masterSetRunUIOnly:", @(0), nil);
        callSel(face, @"toggleRun", nil, nil);
    });
}

+ (void)slvHandleCmd:(NSString *)cmd {
    if ([cmd isEqualToString:@"lite.on"]) { s_slvLite = YES; [self slvToggleLite:YES]; }
    else if ([cmd isEqualToString:@"lite.off"]) { s_slvLite = NO; [self slvToggleLite:NO]; }
    else if ([cmd isEqualToString:@"run.on"]) { [self slvRunOn]; }
    else if ([cmd isEqualToString:@"run.off"]) { [self slvRunOff]; }
    else if ([cmd isEqualToString:@"cxx.face"]) { s_slvCxx = YES; s_slvSafeCxx = NO; [self slvCxxFreeze]; }
    else if ([cmd isEqualToString:@"cxx.safe"]) { s_slvCxx = YES; s_slvSafeCxx = YES; [self slvCxxSafeFreeze]; }
    else if ([cmd hasPrefix:@"speed."]) {
        int ms = [[cmd substringFromIndex:6] intValue];
        [self slvSetSpeed:ms];
        [self slvStartTimer:ms];
    } else if ([cmd isEqualToString:@"P.M.S"]) {
        s_slvMsIdx = s_slvMsIdx >= 4 ? 0 : s_slvMsIdx + 1;
        s_slvMsVal = kMsVals[s_slvMsIdx];
        [self slvSetSpeed:s_slvMsVal];
        [self slvStartTimer:s_slvMsVal];
    }
}
@end

// === Notification handler ===
static void onNotify(CFNotificationCenterRef c, void *o, CFStringRef n, const void *o2, CFDictionaryRef d) {
    NSString *name = (__bridge NSString *)n;
    if ([name hasPrefix:kNotifyPrefix]) {
        NSString *cmd = [name substringFromIndex:kNotifyPrefix.length];
        dispatch_async(dispatch_get_main_queue(), ^{ [_YM slvHandleCmd:cmd]; });
    }
}

// === Crash handler ===
static void ysExceptionHandler(NSException *e) {
    NSLog(@"[YallaAgent] %@: %@", e.name, e.reason);
}

// === Entry point ===
__attribute__((constructor)) static void init() {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:kYallaBundle] && ![bid hasPrefix:kYallaBundle]) return;
        s_instanceId = getInstanceId();
        s_isMain = [bid isEqualToString:kYallaBundle];

        NSSetUncaughtExceptionHandler(&ysExceptionHandler);

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL, onNotify,
            NULL, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        if (s_isMain) {
            dispatch_async(dispatch_get_main_queue(), ^{
#ifdef YM_DIRECT
                [_YM buildUI];
#else
                [_YM showPass];
#endif
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
