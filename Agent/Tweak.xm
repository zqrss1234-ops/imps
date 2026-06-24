#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define kYallaBundle @"com.yalla.yallalite"
#define kNotifyPrefix @"com.yalla.liteagent.cmd."
#define kNotifyHeartbeat @"com.yalla.liteagent.slave.heartbeat"

static const int kMsVals[] = {50, 25, 10, 5, 1};
static NSString *const kNames[] = {
    @"Abdulilah", @"Lahlouh", @"Charo", @"Abu Mutab",
    @"Saeed", @"Al-Kaed", @"Al-Shammarah", @"Al-Habbas",
    @"Al-Anzi", @"Al-Otaibi"
};
#define kNamesCount 10

static int s_sel = -1;
static int s_instanceId = 0;
static BOOL s_isMain = NO;

// Master state
static int s_msIdx = 0;
static BOOL s_on = NO;
static BOOL s_cxx = NO;
static BOOL s_lite = NO;
static int s_slaveCount = 0;
static int s_totalEver = 0;
static int s_cxxCount = 0;
static BOOL s_panelVisible = YES;

// Slave state
static int s_slvMsIdx = 2;
static BOOL s_slvLite = NO;
static BOOL s_slvCxx = NO;
static BOOL s_slvSafe = NO;
static __weak UIView *s_micFace = nil;
static dispatch_source_t s_timer = NULL;

// AST/Link state
static BOOL s_linked = NO;
static CGFloat s_astBXs[10] = {-1,-1,-1,-1,-1,-1,-1,-1,-1,-1};
static CGFloat s_astBYs[10] = {-1,-1,-1,-1,-1,-1,-1,-1,-1,-1};
static CGFloat s_astPX = -1, s_astPY = -1;

// UI
static UIWindow *s_overlay = nil;
static UIView *s_panel = nil;
static UIView *s_passView = nil;
static UITextField *s_passField = nil;
static UILabel *s_st = nil, *s_msL = nil, *s_cxxL = nil, *s_liteL = nil;
static UIButton *s_onBtn = nil;
static NSMutableArray *s_nums = nil;
static UIView *s_circle = nil;

// Country tool
static BOOL s_showCountryView = NO;
static UIView *s_countryPanel = nil;
static NSArray *s_countries = nil;

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
    NSString *s = s_sel >= 0 ? kNames[s_sel] : @"None";
    NSString *status = s_on ? @"ON" : @"OFF";
    NSString *liteSuf = s_lite ? [NSString stringWithFormat:@" | LiTE✓ %d/%d", s_slaveCount, s_totalEver] : @"";
    NSString *cxxSuf = s_cxx ? [NSString stringWithFormat:@" | cxx✓ %d", s_cxxCount] : @"";
    NSString *linkSuf = s_linked ? @" | Link✓" : @"";
    s_st.text = [NSString stringWithFormat:@"%@ | %@ | Mic %d | %dms%@%@%@",
        s, status, s_sel + 1, kMsVals[s_msIdx], liteSuf, cxxSuf, linkSuf];

    if (s_lite) s_liteL.text = [NSString stringWithFormat:@"LiTE %d/%d", s_slaveCount, s_totalEver];
    else s_liteL.text = @"LiTE";
    if (s_cxx) s_cxxL.text = [NSString stringWithFormat:@"cxx %d", s_cxxCount];
    else s_cxxL.text = @"cxx";
}

- (void)num:(UIButton *)b {
    if (s_on) return;
    int idx = (int)b.tag;
    s_sel = idx;
    for (UIButton *nb in s_nums) nb.selected = (nb.tag == idx);
    [self upd];
}

- (void)onT {
    if (s_sel < 0) return;
    s_on = !s_on;
    [s_onBtn setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
    s_onBtn.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
    s_onBtn.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
    id f = findLiveMikeFace();
    if (s_on) {
        callSel(f, @"selectMic:", @(s_sel+1), nil);
        callSel(f, @"setm6b:", @(1), nil);
        callSel(f, @"masterSetRunUIOnly:", @(1), nil);
        callSel(f, @"tapMic", nil, nil);
        callSel(f, @"tapOnce", nil, nil);
        callSel(f, @"isChatRoomTable:", f, nil);
    } else {
        callSel(f, @"setm6b:", @(0), nil);
        callSel(f, @"masterSetRunUIOnly:", @(0), nil);
    }
    postCmd(s_on ? @"run.on" : @"run.off");
    [self upd];
}

- (void)msT {
    s_msIdx = s_msIdx >= 4 ? 0 : s_msIdx + 1;
    s_msL.text = [NSString stringWithFormat:@"ms:%d", kMsVals[s_msIdx]];
    int ms = kMsVals[s_msIdx];
    [self slvSpd:ms];
    [self slvTimer:ms];
    postCmd([NSString stringWithFormat:@"speed.%d", ms]);
    [self upd];
}

- (void)cxxT {
    s_cxx = !s_cxx;
    s_cxxL.textColor = s_cxx ? clr(200,50,200,1) : [UIColor whiteColor];
    s_cxxL.backgroundColor = s_cxx ? clr(100,20,100,0.9) : [UIColor clearColor];
    s_cxxL.layer.borderColor = s_cxx ? clr(200,50,200,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    if (s_cxx) {
        s_cxxCount = s_slaveCount;
        [self slvCxxF];
        [self glitchOn];
    } else {
        [self slvCxxU];
    }
    postCmd(s_cxx ? @"cxx.face" : @"cxx.off");
    [self upd];
}

- (void)liteT {
    s_lite = !s_lite;
    s_liteL.textColor = s_lite ? clr(50,50,255,1) : [UIColor whiteColor];
    s_liteL.backgroundColor = s_lite ? clr(26,26,150,0.9) : [UIColor clearColor];
    s_liteL.layer.borderColor = s_lite ? clr(50,50,255,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    if (s_lite) s_linked = YES;
    else s_linked = NO;
    [self slvLite:s_lite];
    postCmd(s_lite ? @"lite.on" : @"lite.off");
    [self upd];
}

- (void)showPanel {
    s_panelVisible = YES;
    s_panel.hidden = NO;
    s_circle.hidden = YES;
}

- (void)hideT {
    s_panelVisible = NO;
    s_panel.hidden = YES;
    s_circle.hidden = NO;
}



- (void)submitPass {
    NSString *code = s_passField.text ?: @"";
    if (![code isEqualToString:@"515"]) {
        UIColor *orig = clr(20,20,20,0.9);
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

- (void)showPass {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    s_passView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, sh)];
    s_passView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    s_passView.userInteractionEnabled = YES;
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 150)];
    box.center = CGPointMake(sw/2, sh/2 - 60);
    box.backgroundColor = [UIColor blackColor];
    box.layer.cornerRadius = 16;
    box.layer.borderWidth = 2;
    box.layer.borderColor = clr(26,26,26,0.8).CGColor;
    UILabel *pt = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, 220, 20)];
    pt.text = @"YallaAgentMaster";
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
    UIButton *ub = [UIButton buttonWithType:UIButtonTypeCustom];
    ub.frame = CGRectMake(30, 96, 160, 34);
    [ub setTitle:@"Unlock" forState:UIControlStateNormal];
    [ub setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    ub.backgroundColor = clr(20,20,80,0.9);
    ub.layer.cornerRadius = 8;
    ub.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [ub addTarget:self action:@selector(submitPass) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:ub];
    [s_passView addSubview:box];
    [s_overlay addSubview:s_passView];
    [s_passField becomeFirstResponder];
}



// ==================== AsT7aLh (mic coordinates from ASTEngine) ====================
- (NSString *)AsT7aLh {
    int idx = s_sel >= 0 ? s_sel : 0;
    CGFloat bx = s_astBXs[idx] > 0 ? s_astBXs[idx] : 0;
    CGFloat by = s_astBYs[idx] > 0 ? s_astBYs[idx] : 0;
    NSString *fmt = [NSString stringWithFormat:@"AST7ALH-10TH-%04X-%04X",
        (uint16_t)((int)bx & 0xFFFF), (uint16_t)((int)by & 0xFFFF)];
    return fmt;
}

- (NSString *)AsT7aLhForMic:(int)mic {
    int idx = mic - 1;
    if (idx < 0 || idx >= 10) idx = 0;
    CGFloat bx = s_astBXs[idx] > 0 ? s_astBXs[idx] : 0;
    CGFloat by = s_astBYs[idx] > 0 ? s_astBYs[idx] : 0;
    return [NSString stringWithFormat:@"AST7ALH-10TH-%04X-%04X",
        (uint16_t)((int)bx & 0xFFFF), (uint16_t)((int)by & 0xFFFF)];
}

- (void)saveASTCoords {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (int i = 0; i < 10; i++) {
        [ud setDouble:s_astBXs[i] forKey:[NSString stringWithFormat:@"AST_bubbleX_%d", i]];
        [ud setDouble:s_astBYs[i] forKey:[NSString stringWithFormat:@"AST_bubbleY_%d", i]];
    }
    [ud setDouble:s_astPX forKey:@"AST_panelX"];
    [ud setDouble:s_astPY forKey:@"AST_panelY"];
    [ud synchronize];
}

- (void)loadASTCoords {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (int i = 0; i < 10; i++) {
        s_astBXs[i] = [ud doubleForKey:[NSString stringWithFormat:@"AST_bubbleX_%d", i]];
        s_astBYs[i] = [ud doubleForKey:[NSString stringWithFormat:@"AST_bubbleY_%d", i]];
    }
    s_astPX = [ud doubleForKey:@"AST_panelX"];
    s_astPY = [ud doubleForKey:@"AST_panelY"];
}

- (void)buildUI {
    [self loadASTCoords];
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

    // Separator
    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(0, 32, PW, 1)];
    sep1.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
    [s_panel addSubview:sep1];

    // Numbers 1-10
    CGFloat numStartX = 12;
    CGFloat numTotalW = PW - 24;
    CGFloat numSpacing = numTotalW / 9;
    s_nums = [NSMutableArray array];
    for (int i = 0; i < 10; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        CGFloat bx = numStartX + i * numSpacing;
        CGFloat bw = numSpacing - 4;
        if (bw < 22) bw = 22;
        b.frame = CGRectMake(bx, 40, bw, 28);
        [b setTitle:[@(i+1) stringValue] forState:UIControlStateNormal];
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

    // Separator
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(0, 74, PW, 1)];
    sep2.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
    [s_panel addSubview:sep2];

    // Controls: ON, ms, cxx, LiTE, Hide, Data
    CGFloat cw = (PW - 24 - 5 * 4) / 6;
    if (cw > 52) cw = 52;
    CGFloat cTotalW = cw * 6 + 5 * 4;
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
    s_msL = [[UILabel alloc] initWithFrame:CGRectMake(msX, 82, cw, 30)];
    s_msL.text = @"ms:50";
    s_msL.textColor = [UIColor whiteColor];
    s_msL.font = [UIFont boldSystemFontOfSize:11];
    s_msL.textAlignment = NSTextAlignmentCenter;
    s_msL.layer.borderWidth = 1.5;
    s_msL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_msL.layer.cornerRadius = 8;
    s_msL.clipsToBounds = YES;
    [s_panel addSubview:s_msL];
    UIButton *msBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    msBtn.frame = CGRectMake(msX, 82, cw, 30);
    msBtn.backgroundColor = [UIColor clearColor];
    [msBtn addTarget:self action:@selector(msT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:msBtn];

    CGFloat cxxX = cStartX + 2 * (cw + 4);
    s_cxxL = [[UILabel alloc] initWithFrame:CGRectMake(cxxX, 82, cw, 30)];
    s_cxxL.text = @"cxx";
    s_cxxL.textColor = [UIColor whiteColor];
    s_cxxL.font = [UIFont boldSystemFontOfSize:11];
    s_cxxL.textAlignment = NSTextAlignmentCenter;
    s_cxxL.layer.borderWidth = 1.5;
    s_cxxL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_cxxL.layer.cornerRadius = 8;
    s_cxxL.clipsToBounds = YES;
    [s_panel addSubview:s_cxxL];
    UIButton *cxxBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cxxBtn.frame = CGRectMake(cxxX, 82, cw, 30);
    cxxBtn.backgroundColor = [UIColor clearColor];
    [cxxBtn addTarget:self action:@selector(cxxT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:cxxBtn];

    CGFloat liteX = cStartX + 3 * (cw + 4);
    s_liteL = [[UILabel alloc] initWithFrame:CGRectMake(liteX, 82, cw, 30)];
    s_liteL.text = @"LiTE";
    s_liteL.textColor = [UIColor whiteColor];
    s_liteL.font = [UIFont boldSystemFontOfSize:11];
    s_liteL.textAlignment = NSTextAlignmentCenter;
    s_liteL.layer.borderWidth = 1.5;
    s_liteL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_liteL.layer.cornerRadius = 8;
    s_liteL.clipsToBounds = YES;
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

    CGFloat dataX = cStartX + 5 * (cw + 4);
    UIButton *dataBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    dataBtn.frame = CGRectMake(dataX, 82, cw, 30);
    [dataBtn setTitle:@"Data" forState:UIControlStateNormal];
    [dataBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    dataBtn.backgroundColor = clr(40,40,40,0.9);
    dataBtn.layer.cornerRadius = 8;
    dataBtn.layer.borderWidth = 1.5;
    dataBtn.layer.borderColor = clr(60,60,60,0.6).CGColor;
    dataBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [dataBtn addTarget:self action:@selector(showCountryPanel) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:dataBtn];

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
    infoL.text = @"اختر رقم | LiTE لربط الحسابات | cxx قلتش | AsT7aLh";
    [s_panel addSubview:infoL];

    // Draggable panel
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panP:)];
    [s_panel addGestureRecognizer:pan];

    [s_overlay addSubview:s_panel];

    // Floating circle
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
    UIPanGestureRecognizer *cpan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panC:)];
    [s_circle addGestureRecognizer:cpan];
    [s_overlay addSubview:s_circle];

    [self upd];
}

- (UILabel *)mkL:(CGFloat)x y:(CGFloat)y w:(CGFloat)w h:(CGFloat)h t:(NSString *)t fs:(CGFloat)fs {
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, h)];
    lb.text = t;
    lb.textColor = [UIColor whiteColor];
    lb.font = [UIFont boldSystemFontOfSize:fs];
    lb.textAlignment = NSTextAlignmentCenter;
    lb.clipsToBounds = YES;
    return lb;
}

- (void)panP:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x + t.x, sc.y + t.y);
    }
    if (g.state == 3 || g.state == 4) {
        s_astPX = v.center.x;
        s_astPY = v.center.y;
        [self saveASTCoords];
    }
}

- (void)panC:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x + t.x, sc.y + t.y);
    }
    if (g.state == 3 || g.state == 4) {
        int idx = s_sel >= 0 ? s_sel : 0;
        s_astBXs[idx] = v.center.x;
        s_astBYs[idx] = v.center.y;
        [self saveASTCoords];
    }
}

// ==================== Slave commands ====================
- (void)slvLite:(BOOL)on {
    s_linked = on;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *f = findLiveMikeFace();
        if (!f) return;
        f.hidden = on;
        for (UIView *sv in f.subviews) sv.hidden = on;
        callSel(f, @"lt_rippleButtonAction:", @(on?1:0), nil);
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
    [self glitchOff];
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
        int mic = s_isMain ? (s_sel >= 0 ? s_sel+1 : s_instanceId+1) : s_instanceId+1;
        callSel(f, @"selectMic:", @(mic), nil);
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
    else if ([c isEqualToString:@"cxx.face"]) { s_slvCxx = YES; s_slvSafe = NO; [self slvCxxF]; [self glitchOn]; }
    else if ([c isEqualToString:@"cxx.safe"]) { s_slvCxx = YES; s_slvSafe = YES; [self slvCxxS]; [self glitchOn]; }
    else if ([c hasPrefix:@"speed."]) {
        int ms = [[c substringFromIndex:6] intValue];
        [self slvSpd:ms]; [self slvTimer:ms];
    } else if ([c isEqualToString:@"P.M.S"]) {
        s_slvMsIdx = s_slvMsIdx >= 4 ? 0 : s_slvMsIdx + 1;
        [self slvSpd:kMsVals[s_slvMsIdx]];
        [self slvTimer:kMsVals[s_slvMsIdx]];
    } else if ([c isEqualToString:@"cxx.off"]) {
        s_slvCxx = NO; s_slvSafe = NO;
        [self slvCxxU];
    } else if ([c isEqualToString:@"link.on"]) {
        s_linked = YES; [self slvLite:YES];
    } else if ([c isEqualToString:@"link.off"]) {
        s_linked = NO; [self slvLite:NO];
    }
}

// ==================== Glitch integration (native) ====================
static UIView *s_glitchOverlay = nil;
static UILabel *s_glitchLabel = nil;
static void *s_soundID = NULL;

- (UIView *)findMicInstanceInView:(UIView *)v {
    if (!v) return nil;
    NSString *cn = NSStringFromClass([v class]);
    if ([cn containsString:@"LTLiveMikeFace"] || [cn containsString:@"LiveMikeFace"]) return v;
    for (UIView *sv in v.subviews) {
        UIView *found = [self findMicInstanceInView:sv];
        if (found) return found;
    }
    return nil;
}

- (void)createOverlay {
    if (s_glitchOverlay) return;
    UIWindow *kw = findKeyWindow();
    if (!kw) kw = s_overlay;
    if (!kw) return;
    CGFloat sw = kw.bounds.size.width;
    CGFloat ow = 200, oh = 120;
    s_glitchOverlay = [[UIView alloc] initWithFrame:CGRectMake((sw-ow)/2, 80, ow, oh)];
    s_glitchOverlay.backgroundColor = clr(200,0,0,0.85);
    s_glitchOverlay.layer.cornerRadius = 14;
    s_glitchOverlay.layer.borderWidth = 2;
    s_glitchOverlay.layer.borderColor = clr(255,200,0,0.9).CGColor;
    s_glitchOverlay.clipsToBounds = YES;
    s_glitchOverlay.alpha = 0;
    s_glitchOverlay.tag = 1001;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, ow, 24)];
    title.text = @"⚠️ GLITCH";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:18];
    title.textAlignment = NSTextAlignmentCenter;
    [s_glitchOverlay addSubview:title];

    s_glitchLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 48, ow, 20)];
    s_glitchLabel.text = @"TARGET LOCKED";
    s_glitchLabel.textColor = clr(255,200,0,1);
    s_glitchLabel.font = [UIFont boldSystemFontOfSize:13];
    s_glitchLabel.textAlignment = NSTextAlignmentCenter;
    [s_glitchOverlay addSubview:s_glitchLabel];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(0, 72, ow, 16)];
    sub.text = @"cxx glitch active";
    sub.textColor = [UIColor whiteColor];
    sub.font = [UIFont systemFontOfSize:10];
    sub.textAlignment = NSTextAlignmentCenter;
    [s_glitchOverlay addSubview:sub];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [s_glitchOverlay addGestureRecognizer:pan];

    [kw addSubview:s_glitchOverlay];
    [UIView animateWithDuration:0.3 animations:^{
        s_glitchOverlay.alpha = 1;
        s_glitchOverlay.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            s_glitchOverlay.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x + t.x, sc.y + t.y);
    }
}

- (void)executeCommandsOnView:(UIView *)f {
    if (!f) return;
    callSel(f, @"d6s:result:", @(1), nil);
    callSel(f, @"c7rs:result:", @(1), nil);
    callSel(f, @"c7rsInsideChatOnly:result:", @(1), nil);
    callSel(f, @"cxxNoSync", nil, nil);
    callSel(f, @"g3v:", @(1), nil);
    callSel(f, @"q2f:", @(1), nil);
    callSel(f, @"u8k:", @(1), nil);
    callSel(f, @"scan:result:", @(1), nil);
}

- (void)glitchOn {
    @try {
        [self createOverlay];
    } @catch(NSException *e) {
        NSLog(@"[YA] glitchOn error: %@", e.reason);
    }
}

- (void)glitchOff {
    @try {
        if (s_glitchOverlay) {
            [UIView animateWithDuration:0.2 animations:^{
                s_glitchOverlay.alpha = 0;
                s_glitchOverlay.transform = CGAffineTransformMakeScale(0.8, 0.8);
            } completion:^(BOOL finished) {
                [s_glitchOverlay removeFromSuperview];
                s_glitchOverlay = nil;
                s_glitchLabel = nil;
            }];
        }
    } @catch(NSException *e) {
        NSLog(@"[YA] glitchOff error: %@", e.reason);
    }
}

// ==================== Country tool (from ASTEngine format) ====================
- (void)loadCountries {
    if (s_countries) return;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"nationEn" ofType:@"json"];
    if (!path) path = [[NSBundle mainBundle] pathForResource:@"nationAr" ofType:@"json"];
    if (!path) { s_countries = @[]; return; }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) { s_countries = @[]; return; }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!dict) { s_countries = @[]; return; }
    s_countries = dict[@"all"];
}

- (NSString *)astFormatForMic:(int)idx {
    CGFloat bx = s_astBXs[idx] > 0 ? s_astBXs[idx] : 0;
    CGFloat by = s_astBYs[idx] > 0 ? s_astBYs[idx] : 0;
    return [NSString stringWithFormat:@"AST7ALH-10TH-%04X-%04X",
        (uint16_t)((int)bx & 0xFFFF), (uint16_t)((int)by & 0xFFFF)];
}

- (void)showMainPanel {
    s_showCountryView = NO;
    s_countryPanel.hidden = YES;
    s_panel.hidden = NO;
}

- (void)showCountryPanel {
    [self loadCountries];
    s_showCountryView = YES;
    s_panel.hidden = YES;
    [self buildCountryUI];
    [self updCountryUI];
}

- (void)buildCountryUI {
    if (s_countryPanel) { s_countryPanel.hidden = NO; return; }
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat PW = 340;
    if (sw < PW + 16) PW = sw - 16;
    CGFloat PX = (sw - PW) / 2;
    CGFloat PY = 100;

    s_countryPanel = [[UIView alloc] initWithFrame:CGRectMake(PX, PY, PW, 320)];
    s_countryPanel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    s_countryPanel.layer.cornerRadius = 18;
    s_countryPanel.layer.borderWidth = 2;
    s_countryPanel.layer.borderColor = [UIColor blackColor].CGColor;
    s_countryPanel.clipsToBounds = YES;
    s_countryPanel.tag = 1000;

    // Title
    UILabel *titleL = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, PW, 20)];
    titleL.text = @"AST7ALH - Countries";
    titleL.textColor = [UIColor whiteColor];
    titleL.font = [UIFont boldSystemFontOfSize:14];
    titleL.textAlignment = NSTextAlignmentCenter;
    [s_countryPanel addSubview:titleL];

    // Subtitle
    UILabel *subL = [[UILabel alloc] initWithFrame:CGRectMake(0, 26, PW, 14)];
    subL.text = @"Mic Coordinates per Country";
    subL.textColor = clr(150,150,150,1);
    subL.font = [UIFont systemFontOfSize:10];
    subL.textAlignment = NSTextAlignmentCenter;
    [s_countryPanel addSubview:subL];

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(8, 44, PW-16, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.5];
    [s_countryPanel addSubview:sep];

    // Country list - scrollable
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 48, PW, 190)];
    scroll.backgroundColor = [UIColor clearColor];
    scroll.showsVerticalScrollIndicator = YES;

    CGFloat yOff = 0;
    CGFloat rowH = 36;
    int maxCountries = (int)MIN(s_countries.count, 10);
    for (int i = 0; i < maxCountries; i++) {
        NSDictionary *c = s_countries[i];
        NSString *name = c[@"countryName"] ?: @"";
        NSString *iso = c[@"isoCode"] ?: @"";
        NSNumber *cc = c[@"countryCode"] ?: @(0);
        NSString *ast = [self astFormatForMic:i];

        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, yOff, PW-16, rowH-2)];
        row.backgroundColor = clr(15,15,15,0.6);
        row.layer.cornerRadius = 6;

        // Mic number
        UILabel *micL = [[UILabel alloc] initWithFrame:CGRectMake(4, 0, 24, rowH-2)];
        micL.text = [@(i+1) stringValue];
        micL.textColor = clr(0,255,68,1);
        micL.font = [UIFont boldSystemFontOfSize:11];
        micL.textAlignment = NSTextAlignmentCenter;
        [row addSubview:micL];

        // ISO code
        UILabel *isoL = [[UILabel alloc] initWithFrame:CGRectMake(30, 0, 30, rowH-2)];
        isoL.text = iso;
        isoL.textColor = clr(200,200,200,1);
        isoL.font = [UIFont boldSystemFontOfSize:10];
        isoL.textAlignment = NSTextAlignmentCenter;
        [row addSubview:isoL];

        // Country name
        UILabel *nameL = [[UILabel alloc] initWithFrame:CGRectMake(62, 0, 100, rowH-2)];
        nameL.text = name;
        nameL.textColor = [UIColor whiteColor];
        nameL.font = [UIFont systemFontOfSize:10];
        nameL.textAlignment = NSTextAlignmentLeft;
        [row addSubview:nameL];

        // Phone code
        UILabel *codeL = [[UILabel alloc] initWithFrame:CGRectMake(164, 0, 50, rowH-2)];
        codeL.text = [NSString stringWithFormat:@"+%@", cc];
        codeL.textColor = clr(100,180,255,1);
        codeL.font = [UIFont systemFontOfSize:9];
        codeL.textAlignment = NSTextAlignmentCenter;
        [row addSubview:codeL];

        // AST7ALH coordinate
        UILabel *astL = [[UILabel alloc] initWithFrame:CGRectMake(210, 0, PW-220, rowH-2)];
        astL.text = ast;
        astL.textColor = clr(255,200,0,1);
        astL.font = [UIFont systemFontOfSize:9];
        astL.textAlignment = NSTextAlignmentRight;
        [row addSubview:astL];

        // Select button
        UIButton *selBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        selBtn.frame = CGRectMake(0, 0, PW-16, rowH-2);
        selBtn.backgroundColor = [UIColor clearColor];
        selBtn.tag = i;
        [selBtn addTarget:self action:@selector(countrySel:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:selBtn];

        [scroll addSubview:row];
        yOff += rowH;
    }

    scroll.contentSize = CGSizeMake(PW-16, yOff + 4);
    [s_countryPanel addSubview:scroll];

    // Bottom bar: On/Off, Link, Back
    CGFloat btnW = (PW - 32) / 3;
    CGFloat btnY = 246;
    CGFloat btnH = 30;

    // On/Off
    UIButton *onOffBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    onOffBtn.frame = CGRectMake(8, btnY, btnW, btnH);
    [onOffBtn setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
    [onOffBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    onOffBtn.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
    onOffBtn.layer.cornerRadius = 8;
    onOffBtn.layer.borderWidth = 1.5;
    onOffBtn.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
    onOffBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [onOffBtn addTarget:self action:@selector(countryOnOff) forControlEvents:UIControlEventTouchUpInside];
    [s_countryPanel addSubview:onOffBtn];

    // Account Linking (ربط الحسابات)
    UIButton *linkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    linkBtn.frame = CGRectMake(8 + (btnW + 8), btnY, btnW, btnH);
    [linkBtn setTitle:s_linked ? @"ربط✓" : @"ربط" forState:UIControlStateNormal];
    [linkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    linkBtn.backgroundColor = s_linked ? clr(26,26,150,0.9) : clr(10,10,50,0.9);
    linkBtn.layer.cornerRadius = 8;
    linkBtn.layer.borderWidth = 1.5;
    linkBtn.layer.borderColor = s_linked ? clr(50,50,255,0.9).CGColor : clr(26,26,26,0.6).CGColor;
    linkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [linkBtn addTarget:self action:@selector(countryLink) forControlEvents:UIControlEventTouchUpInside];
    [s_countryPanel addSubview:linkBtn];

    // Back to main
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(8 + 2*(btnW + 8), btnY, btnW, btnH);
    [backBtn setTitle:@"Back" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    backBtn.backgroundColor = [UIColor blackColor];
    backBtn.layer.cornerRadius = 8;
    backBtn.layer.borderWidth = 1.5;
    backBtn.layer.borderColor = clr(26,26,26,0.6).CGColor;
    backBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [backBtn addTarget:self action:@selector(showMainPanel) forControlEvents:UIControlEventTouchUpInside];
    [s_countryPanel addSubview:backBtn];

    // Status label
    UILabel *stL = [[UILabel alloc] initWithFrame:CGRectMake(8, 280, PW-16, 14)];
    stL.textColor = [UIColor whiteColor];
    stL.font = [UIFont systemFontOfSize:9];
    stL.textAlignment = NSTextAlignmentCenter;
    stL.text = [NSString stringWithFormat:@"%d countries | AST7ALH-10TH-XXXX-XXXX", (int)s_countries.count];
    [s_countryPanel addSubview:stL];

    // Draggable
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panP:)];
    [s_countryPanel addGestureRecognizer:pan];

    [s_overlay addSubview:s_countryPanel];
}

- (void)countrySel:(UIButton *)b {
    int idx = (int)b.tag;
    if (idx >= 0 && idx < 10) {
        s_sel = idx;
        for (int i = 0; i < (int)s_nums.count; i++) {
            UIButton *nb = s_nums[i];
            nb.selected = (i == idx);
        }
    }
    [self upd];
}

- (void)countryOnOff {
    if (s_sel < 0) return;
    s_on = !s_on;
    id f = findLiveMikeFace();
    if (s_on) {
        callSel(f, @"selectMic:", @(s_sel+1), nil);
        callSel(f, @"setm6b:", @(1), nil);
        callSel(f, @"masterSetRunUIOnly:", @(1), nil);
        callSel(f, @"tapMic", nil, nil);
        callSel(f, @"tapOnce", nil, nil);
        callSel(f, @"isChatRoomTable:", f, nil);
    } else {
        callSel(f, @"setm6b:", @(0), nil);
        callSel(f, @"masterSetRunUIOnly:", @(0), nil);
    }
    postCmd(s_on ? @"run.on" : @"run.off");
    [self updCountryUI];
}

- (void)countryLink {
    s_linked = !s_linked;
    s_lite = s_linked;
    [self slvLite:s_linked];
    postCmd(s_linked ? @"link.on" : @"link.off");
    [self updCountryUI];
}

- (void)updCountryUI {
    for (UIView *sv in s_countryPanel.subviews) {
        if ([sv isKindOfClass:[UIButton class]]) {
            UIButton *b = (UIButton *)sv;
            NSString *t = [b titleForState:UIControlStateNormal];
            if ([t isEqualToString:@"ON"] || [t isEqualToString:@"OFF"]) {
                [b setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
                b.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
                b.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
            } else if ([t hasPrefix:@"ربط"]) {
                [b setTitle:s_linked ? @"ربط✓" : @"ربط" forState:UIControlStateNormal];
                b.backgroundColor = s_linked ? clr(26,26,150,0.9) : clr(10,10,50,0.9);
                b.layer.borderColor = s_linked ? clr(50,50,255,0.9).CGColor : clr(26,26,26,0.6).CGColor;
            }
        }
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
static const char kMicsKey = 0;
static const char kCxxKey = 0;
static const char kRunKey = 0;
static const char kMicKey = 0;
static const char kSpdKey = 0;
static const char kProfKey = 0;

// prof - returns profile identifier string (PROF-XXXX-XXXX format)
static id _prof(id self, SEL _cmd) {
    id val = objc_getAssociatedObject(self, &kProfKey);
    if (!val) {
        val = [NSString stringWithFormat:@"PROF-%04X-%04X", arc4random_uniform(0x10000), arc4random_uniform(0x10000)];
        objc_setAssociatedObject(self, &kProfKey, val, OBJC_ASSOCIATION_RETAIN);
    }
    return val;
}

// tapMic - try lt_mikeButtonAction: (real app method), fallback to mikeButton property
static void _tapMic(id self, SEL _cmd) {
    SEL s = NSSelectorFromString(@"lt_mikeButtonAction:");
    if ([self respondsToSelector:s]) {
        ((void(*)(id,SEL,id))[self methodForSelector:s])(self, s, nil);
        return;
    }
    SEL propS = NSSelectorFromString(@"mikeButton");
    if ([self respondsToSelector:propS]) {
        id btn = ((id(*)(id,SEL))[self methodForSelector:propS])(self, propS);
        if (btn && [btn respondsToSelector:@selector(sendActionsForControlEvents:)]) {
            [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
            return;
        }
    }
    __block UIControl *found = nil;
    void (^search)(UIView *) = ^(UIView *v) {
        if (found) return;
        if ([v isKindOfClass:[UIControl class]] && v != self && ((UIControl *)v).allTargets.count > 0) {
            found = (UIControl *)v;
            return;
        }
        for (UIView *sv in v.subviews) search(sv);
    };
    search(self);
    [found sendActionsForControlEvents:UIControlEventTouchUpInside];
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
    SEL s = NSSelectorFromString(@"mikeView");
    if ([self respondsToSelector:s]) {
        return ((id(*)(id,SEL))[self methodForSelector:s])(self, s);
    }
    return nil;
}

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

static NSArray *ensureMics(id self) {
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    if (!mics || mics.count == 0) {
        _scanResult(self, NULL, nil, nil);
        mics = objc_getAssociatedObject(self, &kMicsKey);
    }
    return mics ?: @[];
}

static void _d6sResult(id self, SEL _cmd, id arg1, id arg2) {
    BOOL on = [arg1 boolValue];
    NSArray *mics = ensureMics(self);
    for (UIView *v in mics) {
        v.alpha = on ? 0.3 : 1.0;
        v.userInteractionEnabled = !on;
    }
    objc_setAssociatedObject(self, &kCxxKey, @(on), OBJC_ASSOCIATION_RETAIN);
}

static void _c7rsResult(id self, SEL _cmd, id arg1, id arg2) {
    BOOL on = [arg1 boolValue];
    NSArray *mics = ensureMics(self);
    for (UIView *v in mics) {
        v.alpha = on ? 0.2 : 1.0;
        v.userInteractionEnabled = !on;
    }
}

static void _cxxNoSync(id self, SEL _cmd) {
    NSArray *mics = ensureMics(self);
    for (UIView *v in mics) {
        v.userInteractionEnabled = NO;
        v.alpha = 0.15;
    }
}

static void _safeCxxNoSync(id self, SEL _cmd) {
    NSArray *mics = ensureMics(self);
    for (UIView *v in mics) {
        v.userInteractionEnabled = NO;
        v.alpha = 0.25;
    }
}

// Two-letter property accessors - store/retrieve from associated objects
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
}

static void _setStatus(id self, SEL _cmd) {
}

static void _timerTick(id self, SEL _cmd) {
    SEL s = NSSelectorFromString(@"lt_timerTick:");
    if ([self respondsToSelector:s]) {
        ((void(*)(id,SEL,id))[self methodForSelector:s])(self, s, nil);
    }
    id val = objc_getAssociatedObject(self, &kCxxKey);
    if ([val boolValue]) {
        NSArray *mics = ensureMics(self);
        for (UIView *v in mics) v.alpha = 0.15;
    }
}

// AsT7aLh - returns formatted mic coordinates string (from ASTEngine)
static id _AsT7aLh(id self, SEL _cmd) {
    int idx = s_sel >= 0 ? s_sel : 0;
    CGFloat bx = s_astBXs[idx] > 0 ? s_astBXs[idx] : 0;
    CGFloat by = s_astBYs[idx] > 0 ? s_astBYs[idx] : 0;
    NSString *fmt = [NSString stringWithFormat:@"AST7ALH-10TH-%04X-%04X",
        (uint16_t)((int)bx & 0xFFFF), (uint16_t)((int)by & 0xFFFF)];
    id val = objc_getAssociatedObject(self, sel_getName(_cmd));
    if (!val) {
        val = fmt;
        objc_setAssociatedObject(self, sel_getName(_cmd), val, OBJC_ASSOCIATION_RETAIN);
    }
    return val;
}

static id _normalizedDigits(id self, SEL _cmd, id arg) {
    NSString *s = arg;
    s = [s stringByReplacingOccurrencesOfString:@"-" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@""];
    return s;
}

static void setupMFMethods(Class mf) {
    #define ADDM(_sel, _imp, _enc) class_addMethod(mf, @selector(_sel), (IMP)_imp, _enc)

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

    ADDM(g3v:, _g3v, "@@:@");
    ADDM(setG3v:, _setG3v, "v@:@");
    ADDM(q2f:, _q2f, "@@:@");
    ADDM(setQ2f:, _setQ2f, "v@:@");
    ADDM(u8k:, _u8k, "@@:@");
    ADDM(setU8k:, _setU8k, "v@:@");
    ADDM(v7l:, _v7l, "@@:@");
    ADDM(setV7l:, _setV7l, "v@:@");

    ADDM(prof, _prof, "@@:");
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
    ADDM(setSpeed:, _setSpeed, "v@:@");
    ADDM(changeSpeed, _changeSpeed, "v@:");
    ADDM(setStatus, _setStatus, "v@:");
    ADDM(timerTick, _timerTick, "v@:");
    ADDM(normalizedDigits:, _normalizedDigits, "@@:@");
    ADDM(AsT7aLh, _AsT7aLh, "@@:");
}

static UIWindow *findKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if (s.activationState != UISceneActivationStateForegroundActive) continue;
            UIWindowScene *ws = (UIWindowScene *)s;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
            }
            for (UIWindow *w in ws.windows) {
                if (w.hidden || w.windowLevel > UIWindowLevelNormal) continue;
                return w;
            }
            return ws.windows.firstObject;
        }
    }
    if ([UIApplication sharedApplication].keyWindow) return [UIApplication sharedApplication].keyWindow;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) return w;
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:kYallaBundle] && ![bid hasPrefix:kYallaBundle]) return;

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
                if (!s_overlay) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                        s_overlay = findKeyWindow();
                        if (s_overlay) {
#ifdef YM_DIRECT
                            [s_agent buildUI];
#else
                            [s_agent showPass];
#endif
                        }
                    });
                    return;
                }
#ifdef YM_DIRECT
                [s_agent buildUI];
#else
                [s_agent showPass];
#endif
            });
        }

        if (!s_isMain) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSString *hb = [NSString stringWithFormat:@"%@.%d", kNotifyHeartbeat, s_instanceId];
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    (__bridge CFStringRef)hb, NULL, NULL, YES);
            });
        }
    }
}
