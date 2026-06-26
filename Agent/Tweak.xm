#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define kYallaBundle @"com.yalla.yallalite"
#define kNotifyPrefix @"com.yalla.liteagent.cmd."
#define kNotifyHeartbeat @"com.yalla.liteagent.slave.heartbeat"

static const int kMsVals[] = {50, 25, 10, 5, 1};

static int s_sel = 0;
static int s_instanceId = 0;
static BOOL s_isMain = NO;
static int s_msIdx = 0;
static BOOL s_on = NO;
static BOOL s_cxx = NO;
static BOOL s_lite = NO;
static BOOL s_linked = NO;
static int s_slaveCount = 0;
static int s_totalEver = 0;
static int s_cxxCount = 0;
static int s_showData = 0;

static UIView *s_panel = nil;
static UIView *s_passView = nil;
static UITextField *s_passField = nil;
static UILabel *s_st = nil, *s_msL = nil, *s_cxxL = nil, *s_liteL = nil;
static UIButton *s_onBtn = nil;
static dispatch_source_t s_timer = NULL;

// Glitch
static UIView *s_glitchOverlay = nil;
static UILabel *s_glitchLabel = nil;

// Position dot
static CGFloat s_dotX = 160, s_dotY = 300;
static UIView *s_dot = nil;

// Country tool
static UIView *s_dataPanel = nil;
static NSArray *s_countries = nil;

static UIColor *clr(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a];
}

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
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w || w.hidden) continue;
        __block UIView *found = nil;
        void (^search)(UIView *) = ^(UIView *v) {
            if (found) return;
            if (!v) return;
            NSString *cn = NSStringFromClass([v class]);
            if ([cn containsString:@"LTLiveMikeFace"] || [cn containsString:@"LiveMikeFace"]) { found = v; return; }
            for (UIView *sv in v.subviews) search(sv);
        };
        search(w);
        if (found) return found;
    }
    return nil;
}

static void findAllMics(UIView *v, NSMutableArray *mics) {
    if (!v) return;
    NSString *cn = NSStringFromClass([v class]);
    if ([cn containsString:@"LTLiveMikeFace"] || [cn containsString:@"LiveMikeFace"])
        [mics addObject:v];
    for (UIView *sv in v.subviews) findAllMics(sv, mics);
}

static void callSel(id obj, NSString *selName, id arg1, id arg2) {
    @try {
        SEL s = NSSelectorFromString(selName);
        if ([obj respondsToSelector:s]) {
            if (arg2) ((void(*)(id,SEL,id,id))[obj methodForSelector:s])(obj,s,arg1,arg2);
            else if (arg1) ((void(*)(id,SEL,id))[obj methodForSelector:s])(obj,s,arg1);
            else ((void(*)(id,SEL))[obj methodForSelector:s])(obj,s);
        }
    } @catch(NSException *e) {}
}

@interface _YM : NSObject @end
@implementation _YM

+ (UIView *)nearestMicViewAt:(CGFloat)x y:(CGFloat)y {
    NSMutableArray *mics = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w || w.hidden) continue;
        findAllMics(w, mics);
    }
    if (mics.count == 0) return nil;
    CGFloat minDist = CGFLOAT_MAX;
    UIView *nearest = nil;
    for (UIView *m in mics) {
        CGPoint c = [m.superview convertPoint:m.center toView:nil];
        CGFloat dx = c.x - x, dy = c.y - y;
        CGFloat dist = dx*dx + dy*dy;
        if (dist < minDist) { minDist = dist; nearest = m; }
    }
    return nearest;
}

+ (int)indexOfMicView:(UIView *)v {
    if (!v) return 0;
    NSMutableArray *mics = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w || w.hidden) continue;
        findAllMics(w, mics);
    }
    NSUInteger idx = [mics indexOfObject:v];
    return idx == NSNotFound ? 0 : (int)idx;
}

+ (void)upd {
    NSString *status = s_on ? @"ON" : @"OFF";
    NSString *liteSuf = s_lite ? [NSString stringWithFormat:@" | LiTE\u2713 %d/%d", s_slaveCount, s_totalEver] : @"";
    NSString *cxxSuf = s_cxx ? [NSString stringWithFormat:@" | cxx\u2713 %d", s_cxxCount] : @"";
    NSString *linkSuf = s_linked ? @" | Link\u2713" : @"";
    s_st.text = [NSString stringWithFormat:@"(%.0f,%.0f) | %@ | %dms%@%@%@",
        s_dotX, s_dotY, status, kMsVals[s_msIdx], liteSuf, cxxSuf, linkSuf];
    if (s_lite) s_liteL.text = [NSString stringWithFormat:@"LiTE %d/%d", s_slaveCount, s_totalEver];
    else s_liteL.text = @"LiTE";
    if (s_cxx) s_cxxL.text = [NSString stringWithFormat:@"cxx %d", s_cxxCount];
    else s_cxxL.text = @"cxx";
}

+ (void)onT {
    s_on = !s_on;
    [s_onBtn setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
    s_onBtn.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
    s_onBtn.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
    if (s_on) {
        UIView *near = [self nearestMicViewAt:s_dotX y:s_dotY];
        if (near) s_sel = [self indexOfMicView:near];
    }
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
    if (s_cxx) {
        s_cxxCount = s_slaveCount;
        [self glitchOn];
    } else {
        [self glitchOff];
    }
    postCmd(s_cxx ? @"cxx.face" : @"cxx.safe");
    [self upd];
}

+ (void)liteT {
    s_lite = !s_lite;
    s_liteL.textColor = s_lite ? clr(50,50,255,1) : [UIColor whiteColor];
    s_liteL.backgroundColor = s_lite ? clr(26,26,150,0.9) : [UIColor clearColor];
    s_liteL.layer.borderColor = s_lite ? clr(50,50,255,0.9).CGColor : [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    if (s_lite) s_linked = YES;
    else s_linked = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *mics = [NSMutableArray array];
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w || w.hidden) continue;
            findAllMics(w, mics);
        }
        for (UIView *f in mics) {
            f.hidden = s_lite;
            for (UIView *sv in f.subviews) sv.hidden = s_lite;
            callSel(f, @"lt_rippleButtonAction:", @(s_lite?1:0), nil);
        }
    });
    if (s_lite) {
        postCmd([NSString stringWithFormat:@"dot.%.0f.%.0f", s_dotX, s_dotY]);
    }
    postCmd(s_lite ? @"lite.on" : @"lite.off");
    [self upd];
}

+ (void)showPanel {
    if (s_dataPanel && !s_dataPanel.hidden) return;
    s_panel.hidden = NO;
    s_dot.hidden = YES;
}

+ (void)hideT {
    s_panel.hidden = YES;
    s_dot.hidden = NO;
}

// ==================== Glitch ====================

+ (void)createOverlay {
    if (s_glitchOverlay) return;
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
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
    title.text = @"\u26A0\uFE0F GLITCH";
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
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGlitch:)];
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

+ (void)glitchOn {
    @try { [self createOverlay]; } @catch(NSException *e) {}
}

+ (void)glitchOff {
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
    } @catch(NSException *e) {}
}

+ (void)panGlitch:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x + t.x, sc.y + t.y);
    }
}

// ==================== AST7ALH / Country Data ====================

+ (NSString *)astFormat {
    return [NSString stringWithFormat:@"AST7ALH-10TH-%04X-%04X",
        (uint16_t)((int)s_dotX & 0xFFFF), (uint16_t)((int)s_dotY & 0xFFFF)];
}

+ (void)loadCountries {
    if (s_countries) return;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"nationEn" ofType:@"json"];
    if (!path) path = [[NSBundle mainBundle] pathForResource:@"nationAr" ofType:@"json"];
    if (!path) { s_countries = @[]; return; }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) { s_countries = @[]; return; }
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    s_countries = dict[@"all"] ?: @[];
}

+ (void)saveDotCoords {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setDouble:s_dotX forKey:@"AST_dotX"];
    [ud setDouble:s_dotY forKey:@"AST_dotY"];
    [ud synchronize];
}

+ (void)loadDotCoords {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat vx = [ud doubleForKey:@"AST_dotX"];
    CGFloat vy = [ud doubleForKey:@"AST_dotY"];
    if (vx > 0 && vy > 0) { s_dotX = vx; s_dotY = vy; }
}

+ (void)dataT {
    [self loadCountries];
    s_showData = 1;
    s_panel.hidden = YES;
    s_dot.hidden = YES;
    [self buildDataUI];
    [self updDataUI];
}

+ (void)backToMain {
    s_showData = 0;
    s_dataPanel.hidden = YES;
    s_panel.hidden = NO;
}

+ (void)buildDataUI {
    if (s_dataPanel) { s_dataPanel.hidden = NO; return; }
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat PW = 340;
    if (sw < PW + 16) PW = sw - 16;
    CGFloat PX = (sw - PW) / 2;
    CGFloat PY = 100;

    s_dataPanel = [[UIView alloc] initWithFrame:CGRectMake(PX, PY, PW, 320)];
    s_dataPanel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    s_dataPanel.layer.cornerRadius = 18;
    s_dataPanel.layer.borderWidth = 2;
    s_dataPanel.layer.borderColor = [UIColor blackColor].CGColor;
    s_dataPanel.clipsToBounds = YES;
    s_dataPanel.tag = 1000;

    UILabel *titleL = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, PW, 20)];
    titleL.text = @"AST7ALH - Countries";
    titleL.textColor = [UIColor whiteColor];
    titleL.font = [UIFont boldSystemFontOfSize:14];
    titleL.textAlignment = NSTextAlignmentCenter;
    titleL.userInteractionEnabled = NO;
    [s_dataPanel addSubview:titleL];

    UILabel *subL = [[UILabel alloc] initWithFrame:CGRectMake(0, 26, PW, 14)];
    subL.text = [NSString stringWithFormat:@"%lu countries loaded", (unsigned long)s_countries.count];
    subL.textColor = clr(150,150,150,1);
    subL.font = [UIFont systemFontOfSize:10];
    subL.textAlignment = NSTextAlignmentCenter;
    subL.userInteractionEnabled = NO;
    [s_dataPanel addSubview:subL];

    [s_dataPanel addSubview:mkSep(8, 44, PW-16)];

    // Scroll list
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 48, PW, 188)];
    scroll.backgroundColor = [UIColor clearColor];
    scroll.showsVerticalScrollIndicator = YES;

    CGFloat yOff = 0;
    CGFloat rowH = 34;
    int maxCnt = (int)MIN(s_countries.count, 10);
    NSString *ast = [self astFormat];
    for (int i = 0; i < maxCnt; i++) {
        NSDictionary *c = s_countries[i];
        NSString *name = c[@"countryName"] ?: @"";
        NSString *iso = c[@"isoCode"] ?: @"";
        NSNumber *cc = c[@"countryCode"] ?: @(0);

        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(8, yOff, PW-16, rowH-2)];
        row.backgroundColor = clr(15,15,15,0.6);
        row.layer.cornerRadius = 6;

        UILabel *micL = [[UILabel alloc] initWithFrame:CGRectMake(4, 0, 22, rowH-2)];
        micL.text = [@(i+1) stringValue];
        micL.textColor = clr(0,255,68,1);
        micL.font = [UIFont boldSystemFontOfSize:11];
        micL.textAlignment = NSTextAlignmentCenter;
        micL.userInteractionEnabled = NO;
        [row addSubview:micL];

        UILabel *isoL = [[UILabel alloc] initWithFrame:CGRectMake(28, 0, 28, rowH-2)];
        isoL.text = iso;
        isoL.textColor = clr(200,200,200,1);
        isoL.font = [UIFont boldSystemFontOfSize:10];
        isoL.textAlignment = NSTextAlignmentCenter;
        isoL.userInteractionEnabled = NO;
        [row addSubview:isoL];

        UILabel *nameL = [[UILabel alloc] initWithFrame:CGRectMake(58, 0, 90, rowH-2)];
        nameL.text = name;
        nameL.textColor = [UIColor whiteColor];
        nameL.font = [UIFont systemFontOfSize:10];
        nameL.textAlignment = NSTextAlignmentLeft;
        nameL.userInteractionEnabled = NO;
        [row addSubview:nameL];

        UILabel *codeL = [[UILabel alloc] initWithFrame:CGRectMake(150, 0, 40, rowH-2)];
        codeL.text = [NSString stringWithFormat:@"+%@", cc];
        codeL.textColor = clr(100,180,255,1);
        codeL.font = [UIFont systemFontOfSize:9];
        codeL.textAlignment = NSTextAlignmentCenter;
        codeL.userInteractionEnabled = NO;
        [row addSubview:codeL];

        UILabel *astL = [[UILabel alloc] initWithFrame:CGRectMake(192, 0, PW-210, rowH-2)];
        astL.text = ast;
        astL.textColor = clr(255,200,0,1);
        astL.font = [UIFont systemFontOfSize:8];
        astL.textAlignment = NSTextAlignmentRight;
        astL.adjustsFontSizeToFitWidth = YES;
        astL.minimumScaleFactor = 0.6;
        astL.userInteractionEnabled = NO;
        [row addSubview:astL];

        UIButton *selBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        selBtn.frame = CGRectMake(0, 0, PW-16, rowH-2);
        selBtn.backgroundColor = [UIColor clearColor];
        selBtn.tag = i;
        [selBtn addTarget:self action:@selector(dataSel:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:selBtn];

        [scroll addSubview:row];
        yOff += rowH;
    }
    scroll.contentSize = CGSizeMake(PW-16, yOff+4);
    [s_dataPanel addSubview:scroll];

    // Bottom buttons
    CGFloat btnW = (PW - 32) / 3;
    CGFloat btnY = 244;
    CGFloat btnH = 28;
    CGFloat btnF = 10;

    UIButton *onOffBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    onOffBtn.frame = CGRectMake(8, btnY, btnW, btnH);
    [onOffBtn setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
    [onOffBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    onOffBtn.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
    onOffBtn.layer.cornerRadius = 8;
    onOffBtn.layer.borderWidth = 1.5;
    onOffBtn.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
    onOffBtn.titleLabel.font = [UIFont boldSystemFontOfSize:btnF];
    [onOffBtn addTarget:self action:@selector(dataOnOff) forControlEvents:UIControlEventTouchUpInside];
    [s_dataPanel addSubview:onOffBtn];

    UIButton *linkBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    linkBtn.frame = CGRectMake(8 + (btnW+8), btnY, btnW, btnH);
    [linkBtn setTitle:s_linked ? @"\u0631\u0628\u0637\u2713" : @"\u0631\u0628\u0637" forState:UIControlStateNormal];
    [linkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    linkBtn.backgroundColor = s_linked ? clr(26,26,150,0.9) : clr(10,10,50,0.9);
    linkBtn.layer.cornerRadius = 8;
    linkBtn.layer.borderWidth = 1.5;
    linkBtn.layer.borderColor = s_linked ? clr(50,50,255,0.9).CGColor : clr(26,26,26,0.6).CGColor;
    linkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:btnF];
    [linkBtn addTarget:self action:@selector(dataLink) forControlEvents:UIControlEventTouchUpInside];
    [s_dataPanel addSubview:linkBtn];

    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(8+2*(btnW+8), btnY, btnW, btnH);
    [backBtn setTitle:@"Back" forState:UIControlStateNormal];
    [backBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    backBtn.backgroundColor = [UIColor blackColor];
    backBtn.layer.cornerRadius = 8;
    backBtn.layer.borderWidth = 1.5;
    backBtn.layer.borderColor = clr(26,26,26,0.6).CGColor;
    backBtn.titleLabel.font = [UIFont boldSystemFontOfSize:btnF];
    [backBtn addTarget:self action:@selector(backToMain) forControlEvents:UIControlEventTouchUpInside];
    [s_dataPanel addSubview:backBtn];

    // Status line
    UILabel *stL = [[UILabel alloc] initWithFrame:CGRectMake(8, 278, PW-16, 14)];
    stL.textColor = [UIColor whiteColor];
    stL.font = [UIFont systemFontOfSize:9];
    stL.textAlignment = NSTextAlignmentCenter;
    stL.text = [NSString stringWithFormat:@"%lu countries | AST7ALH-10TH-XXXX-XXXX",
        (unsigned long)s_countries.count];
    stL.userInteractionEnabled = NO;
    [s_dataPanel addSubview:stL];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panData:)];
    [s_dataPanel addGestureRecognizer:pan];

    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (kw) [kw addSubview:s_dataPanel];
}

+ (void)dataSel:(UIButton *)b {
    int idx = (int)b.tag;
    if (idx >= 0 && idx < 10) s_sel = idx;
    [self upd];
}

+ (void)dataOnOff {
    s_on = !s_on;
    [s_onBtn setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
    s_onBtn.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
    s_onBtn.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
    postCmd(s_on ? @"run.on" : @"run.off");
    [self updDataUI];
}

+ (void)dataLink {
    s_linked = !s_linked;
    s_lite = s_linked;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *mics = [NSMutableArray array];
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (!w || w.hidden) continue;
            findAllMics(w, mics);
        }
        for (UIView *f in mics) {
            f.hidden = s_linked;
            for (UIView *sv in f.subviews) sv.hidden = s_linked;
            callSel(f, @"lt_rippleButtonAction:", @(s_linked?1:0), nil);
        }
    });
    postCmd(s_linked ? @"link.on" : @"link.off");
    [self updDataUI];
}

+ (void)updDataUI {
    if (!s_dataPanel) return;
    for (UIView *sv in s_dataPanel.subviews) {
        if (![sv isKindOfClass:[UIButton class]]) continue;
        UIButton *b = (UIButton *)sv;
        NSString *t = [b titleForState:UIControlStateNormal];
        if ([t isEqualToString:@"ON"] || [t isEqualToString:@"OFF"]) {
            [b setTitle:s_on ? @"OFF" : @"ON" forState:UIControlStateNormal];
            b.backgroundColor = s_on ? clr(100,0,0,0.9) : clr(0,100,0,0.9);
            b.layer.borderColor = s_on ? clr(255,0,0,0.9).CGColor : clr(0,255,0,0.9).CGColor;
        } else if ([t hasPrefix:@"\u0631\u0628\u0637"]) {
            [b setTitle:s_linked ? @"\u0631\u0628\u0637\u2713" : @"\u0631\u0628\u0637" forState:UIControlStateNormal];
            b.backgroundColor = s_linked ? clr(26,26,150,0.9) : clr(10,10,50,0.9);
            b.layer.borderColor = s_linked ? clr(50,50,255,0.9).CGColor : clr(26,26,26,0.6).CGColor;
        }
    }
}

+ (void)panData:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x + t.x, sc.y + t.y);
    }
}

// ==================== Passcode ====================

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

+ (void)showPass {
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (!kw) return;
    UIView *cv = kw.rootViewController.view;
    if (!cv) return;

    s_passView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    s_passView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    s_passView.userInteractionEnabled = YES;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 150)];
    box.center = CGPointMake(s_passView.center.x, s_passView.center.y - 60);
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

// ==================== Build UI ====================

+ (void)buildUI {
    [self loadDotCoords];
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (!kw) return;
    UIView *cv = kw.rootViewController.view;
    if (!cv) return;

    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat PW = 340;
    if (sw < PW + 16) PW = sw - 16;
    CGFloat PX = (sw - PW) / 2;
    CGFloat PY = 120;

    // Slim panel: controls + status only
    CGFloat panelH = 150;
    s_panel = [[UIView alloc] initWithFrame:CGRectMake(PX, PY, PW, panelH)];
    s_panel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    s_panel.layer.cornerRadius = 18;
    s_panel.layer.borderWidth = 2;
    s_panel.layer.borderColor = [UIColor blackColor].CGColor;
    s_panel.clipsToBounds = YES;
    s_panel.tag = 999;

    // Controls: ON, ms, cxx, LiTE, Hide, Data
    CGFloat cw = (PW - 24 - 5 * 4) / 6;
    if (cw > 52) cw = 52;
    CGFloat cTotalW = cw * 6 + 5 * 4;
    CGFloat cStartX = (PW - cTotalW) / 2;

    s_onBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    s_onBtn.frame = CGRectMake(cStartX, 10, cw, 32);
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
    s_msL = mkLab(msX, 10, cw, 32, @"ms:50", 11);
    s_msL.layer.borderWidth = 1.5;
    s_msL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_msL.layer.cornerRadius = 8;
    [s_panel addSubview:s_msL];
    UIButton *msBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    msBtn.frame = CGRectMake(msX, 10, cw, 32);
    msBtn.backgroundColor = [UIColor clearColor];
    [msBtn addTarget:self action:@selector(msT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:msBtn];

    CGFloat cxxX = cStartX + 2 * (cw + 4);
    s_cxxL = mkLab(cxxX, 10, cw, 32, @"cxx", 11);
    s_cxxL.layer.borderWidth = 1.5;
    s_cxxL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_cxxL.layer.cornerRadius = 8;
    [s_panel addSubview:s_cxxL];
    UIButton *cxxBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cxxBtn.frame = CGRectMake(cxxX, 10, cw, 32);
    cxxBtn.backgroundColor = [UIColor clearColor];
    [cxxBtn addTarget:self action:@selector(cxxT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:cxxBtn];

    CGFloat liteX = cStartX + 3 * (cw + 4);
    s_liteL = mkLab(liteX, 10, cw, 32, @"LiTE", 11);
    s_liteL.layer.borderWidth = 1.5;
    s_liteL.layer.borderColor = clr(26,26,26,0.6).CGColor;
    s_liteL.layer.cornerRadius = 8;
    [s_panel addSubview:s_liteL];
    UIButton *liteBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    liteBtn.frame = CGRectMake(liteX, 10, cw, 32);
    liteBtn.backgroundColor = [UIColor clearColor];
    [liteBtn addTarget:self action:@selector(liteT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:liteBtn];

    CGFloat hideX = cStartX + 4 * (cw + 4);
    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    hideBtn.frame = CGRectMake(hideX, 10, cw, 32);
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
    dataBtn.frame = CGRectMake(dataX, 10, cw, 32);
    [dataBtn setTitle:@"Data" forState:UIControlStateNormal];
    [dataBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    dataBtn.backgroundColor = clr(40,40,40,0.9);
    dataBtn.layer.cornerRadius = 8;
    dataBtn.layer.borderWidth = 1.5;
    dataBtn.layer.borderColor = clr(60,60,60,0.6).CGColor;
    dataBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [dataBtn addTarget:self action:@selector(dataT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:dataBtn];

    [s_panel addSubview:mkSep(8, 48, PW-16)];

    // Status
    s_st = [[UILabel alloc] initWithFrame:CGRectMake(8, 54, PW - 16, 16)];
    s_st.textColor = [UIColor whiteColor];
    s_st.font = [UIFont systemFontOfSize:10];
    s_st.textAlignment = NSTextAlignmentCenter;
    s_st.text = @"(0,0) | OFF | 50ms";
    s_st.userInteractionEnabled = NO;
    [s_panel addSubview:s_st];

    // Info text
    UILabel *infoL = [[UILabel alloc] initWithFrame:CGRectMake(8, 72, PW - 16, 14)];
    infoL.textColor = [UIColor whiteColor];
    infoL.font = [UIFont systemFontOfSize:9];
    infoL.textAlignment = NSTextAlignmentCenter;
    infoL.text = @"\u0627\u0633\u062D\u0628 \u0627\u0644\u0646\u0642\u0637\u0629 | LiTE \u0644\u0631\u0628\u0637 \u0627\u0644\u062D\u0633\u0627\u0628\u0627\u062A | cxx \u0642\u0644\u062A\u0634 | AsT7aLh";
    infoL.userInteractionEnabled = NO;
    [s_panel addSubview:infoL];

    // Status separator + mic index line
    [s_panel addSubview:mkSep(8, 90, PW-16)];
    UILabel *micInfo = [[UILabel alloc] initWithFrame:CGRectMake(8, 94, PW - 16, 16)];
    micInfo.textColor = clr(0,255,68,1);
    micInfo.font = [UIFont systemFontOfSize:10];
    micInfo.textAlignment = NSTextAlignmentCenter;
    int nearest = 0;
    UIView *near = [self nearestMicViewAt:s_dotX y:s_dotY];
    if (near) nearest = [self indexOfMicView:near] + 1;
    micInfo.text = [NSString stringWithFormat:@"\uD83C\uDFCC\uFE0F Mic %d  |  (%.0f, %.0f)", nearest, s_dotX, s_dotY];
    micInfo.userInteractionEnabled = NO;
    micInfo.tag = 998;
    [s_panel addSubview:micInfo];

    // Draggable panel
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    [s_panel addGestureRecognizer:pan];

    [cv addSubview:s_panel];

    // Position dot - replaces numbered buttons and old 515 circle
    CGFloat ds = 40;
    s_dot = [[UIView alloc] initWithFrame:CGRectMake(s_dotX - ds/2, s_dotY - ds/2, ds, ds)];
    s_dot.backgroundColor = [UIColor clearColor];
    s_dot.layer.cornerRadius = ds / 2;
    s_dot.layer.borderWidth = 2.5;
    s_dot.layer.borderColor = clr(0,255,68,0.9).CGColor;
    s_dot.userInteractionEnabled = YES;

    // Inner crosshair
    UIView *inner = [[UIView alloc] initWithFrame:CGRectMake(ds/2 - 1, 4, 2, ds - 8)];
    inner.backgroundColor = clr(0,255,68,0.7);
    inner.userInteractionEnabled = NO;
    [s_dot addSubview:inner];
    UIView *innerH = [[UIView alloc] initWithFrame:CGRectMake(4, ds/2 - 1, ds - 8, 2)];
    innerH.backgroundColor = clr(0,255,68,0.7);
    innerH.userInteractionEnabled = NO;
    [s_dot addSubview:innerH];

    // Center dot
    UIView *center = [[UIView alloc] initWithFrame:CGRectMake(ds/2 - 3, ds/2 - 3, 6, 6)];
    center.backgroundColor = clr(0,255,68,1);
    center.layer.cornerRadius = 3;
    center.userInteractionEnabled = NO;
    [s_dot addSubview:center];

    UITapGestureRecognizer *dtap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showPanel)];
    [s_dot addGestureRecognizer:dtap];
    UIPanGestureRecognizer *dpan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panDot:)];
    [s_dot addGestureRecognizer:dpan];

    [cv addSubview:s_dot];

    [self upd];
}

+ (void)panPanel:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x + t.x, sc.y + t.y);
    }
}

+ (void)panDot:(UIPanGestureRecognizer *)g {
    static CGPoint sc;
    UIView *v = g.view;
    if (g.state == 1) sc = v.center;
    if (g.state == 2) {
        CGPoint t = [g translationInView:v.superview];
        v.center = CGPointMake(sc.x + t.x, sc.y + t.y);
    }
    if (g.state == 3 || g.state == 4) {
        s_dotX = v.center.x;
        s_dotY = v.center.y;
        [self saveDotCoords];
        UIView *near = [self nearestMicViewAt:s_dotX y:s_dotY];
        if (near) s_sel = [self indexOfMicView:near];
        // Update mic info label
        UIView *mi = [s_panel viewWithTag:998];
        if ([mi isKindOfClass:[UILabel class]]) {
            int nn = 0;
            UIView *n = [self nearestMicViewAt:s_dotX y:s_dotY];
            if (n) nn = [self indexOfMicView:n] + 1;
            [(UILabel *)mi setText:[NSString stringWithFormat:@"\U0001F3CC\uFE0F Mic %d  |  (%.0f, %.0f)", nn, s_dotX, s_dotY]];
        }
        [self upd];
    }
}

@end

// ==================== Darwin handlers ====================

static _YM *s_agent = nil;

static void onNotify(CFNotificationCenterRef c, void *o, CFStringRef n, const void *o2, CFDictionaryRef d) {
    NSString *name = (__bridge NSString *)n;
    if (![name hasPrefix:kNotifyPrefix]) return;
    NSString *cmd = [name substringFromIndex:kNotifyPrefix.length];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([cmd isEqualToString:@"run.on"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                id face = findLiveMikeFace();
                if (!face) return;
                int mic = s_isMain ? (s_sel + 1) : (s_instanceId + 1);
                callSel(face, @"selectMic:", @(mic), nil);
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
        } else if ([cmd isEqualToString:@"lite.on"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableArray *mics = [NSMutableArray array];
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    if (!w || w.hidden) continue;
                    findAllMics(w, mics);
                }
                for (UIView *f in mics) {
                    f.hidden = YES;
                    for (UIView *sv in f.subviews) sv.hidden = YES;
                    callSel(f, @"lt_rippleButtonAction:", @(1), nil);
                }
            });
        } else if ([cmd isEqualToString:@"lite.off"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableArray *mics = [NSMutableArray array];
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    if (!w || w.hidden) continue;
                    findAllMics(w, mics);
                }
                for (UIView *f in mics) {
                    f.hidden = NO;
                    for (UIView *sv in f.subviews) sv.hidden = NO;
                    callSel(f, @"lt_rippleButtonAction:", @(0), nil);
                }
            });
        } else if ([cmd isEqualToString:@"cxx.face"]) {
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
            [_YM glitchOn];
        } else if ([cmd isEqualToString:@"cxx.safe"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                id face = findLiveMikeFace();
                if (!face) return;
                callSel(face, @"d6s:result:", @(1), nil);
                callSel(face, @"c7rs:result:", @(1), nil);
                callSel(face, @"c7rsInsideChatOnly:result:", @(1), nil);
                callSel(face, @"safeCxxNoSync", nil, nil);
                callSel(face, @"v7l:", @(1), nil);
            });
            [_YM glitchOn];
        } else if ([cmd hasPrefix:@"speed."]) {
            int ms = [[cmd substringFromIndex:6] intValue];
            dispatch_async(dispatch_get_main_queue(), ^{
                id face = findLiveMikeFace();
                if (!face) return;
                callSel(face, @"setSpeed:", @(ms), nil);
                callSel(face, @"changeSpeed", nil, nil);
                callSel(face, @"setStatus", nil, nil);
            });
            if (s_timer) { dispatch_source_cancel(s_timer); s_timer = NULL; }
            s_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            if (s_timer) {
                dispatch_source_set_timer(s_timer, dispatch_time(DISPATCH_TIME_NOW, ms*NSEC_PER_MSEC), ms*NSEC_PER_MSEC, 0);
                dispatch_source_set_event_handler(s_timer, ^{
                    id face = findLiveMikeFace(); if (!face) return;
                    callSel(face, @"timerTick", nil, nil);
                });
                dispatch_resume(s_timer);
            }
        } else if ([cmd isEqualToString:@"P.M.S"]) {
            s_msIdx = s_msIdx >= 4 ? 0 : s_msIdx + 1;
            int ms = kMsVals[s_msIdx];
            dispatch_async(dispatch_get_main_queue(), ^{
                id face = findLiveMikeFace();
                if (!face) return;
                callSel(face, @"setSpeed:", @(ms), nil);
                callSel(face, @"changeSpeed", nil, nil);
                callSel(face, @"setStatus", nil, nil);
            });
            if (s_timer) { dispatch_source_cancel(s_timer); s_timer = NULL; }
            s_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            if (s_timer) {
                dispatch_source_set_timer(s_timer, dispatch_time(DISPATCH_TIME_NOW, ms*NSEC_PER_MSEC), ms*NSEC_PER_MSEC, 0);
                dispatch_source_set_event_handler(s_timer, ^{
                    id face = findLiveMikeFace(); if (!face) return;
                    callSel(face, @"timerTick", nil, nil);
                });
                dispatch_resume(s_timer);
            }
        } else if ([cmd isEqualToString:@"link.on"]) {
            s_linked = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableArray *mics = [NSMutableArray array];
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    if (!w || w.hidden) continue;
                    findAllMics(w, mics);
                }
                for (UIView *f in mics) {
                    f.hidden = YES;
                    for (UIView *sv in f.subviews) sv.hidden = YES;
                    callSel(f, @"lt_rippleButtonAction:", @(1), nil);
                }
            });
        } else if ([cmd isEqualToString:@"link.off"]) {
            s_linked = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableArray *mics = [NSMutableArray array];
                for (UIWindow *w in [UIApplication sharedApplication].windows) {
                    if (!w || w.hidden) continue;
                    findAllMics(w, mics);
                }
                for (UIView *f in mics) {
                    f.hidden = NO;
                    for (UIView *sv in f.subviews) sv.hidden = NO;
                    callSel(f, @"lt_rippleButtonAction:", @(0), nil);
                }
            });
        } else if ([cmd hasPrefix:@"dot."]) {
            NSString *rest = [cmd substringFromIndex:4];
            NSArray *parts = [rest componentsSeparatedByString:@"."];
            if (parts.count == 2) {
                s_dotX = [parts[0] floatValue];
                s_dotY = [parts[1] floatValue];
            }
        }
    });
}

static void onHeartbeat(CFNotificationCenterRef c, void *o, CFStringRef n, const void *o2, CFDictionaryRef d) {
    dispatch_async(dispatch_get_main_queue(), ^{
        s_slaveCount++;
        if (s_slaveCount > s_totalEver) s_totalEver = s_slaveCount;
        if (s_cxx) s_cxxCount = s_slaveCount;
        [_YM upd];
    });
}

static void ysHandler(NSException *e) {
    NSLog(@"[YA] %@: %@", e.name, e.reason);
}

// ==================== LTLiveMikeFace method hooks ====================

static const char kMicsKey = 0;
static const char kCxxKey = 0;
static const char kRunKey = 0;
static const char kMicKey = 0;
static const char kSpdKey = 0;
static const char kProfKey = 0;

static id _prof(id self, SEL _cmd) {
    id val = objc_getAssociatedObject(self, &kProfKey);
    if (!val) {
        val = [NSString stringWithFormat:@"PROF-%04X-%04X", arc4random_uniform(0x10000), arc4random_uniform(0x10000)];
        objc_setAssociatedObject(self, &kProfKey, val, OBJC_ASSOCIATION_RETAIN);
    }
    return val;
}

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

static void _d6sResult(id self, SEL _cmd, id arg1, id arg2) {
    BOOL on = [arg1 boolValue];
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    if (!mics || mics.count == 0) {
        _scanResult(self, NULL, nil, nil);
        mics = objc_getAssociatedObject(self, &kMicsKey);
    }
    for (UIView *v in mics) {
        v.alpha = on ? 0.3 : 1.0;
        v.userInteractionEnabled = !on;
    }
    objc_setAssociatedObject(self, &kCxxKey, @(on), OBJC_ASSOCIATION_RETAIN);
}

static void _c7rsResult(id self, SEL _cmd, id arg1, id arg2) {
    BOOL on = [arg1 boolValue];
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    if (!mics || mics.count == 0) {
        _scanResult(self, NULL, nil, nil);
        mics = objc_getAssociatedObject(self, &kMicsKey);
    }
    for (UIView *v in mics) {
        v.alpha = on ? 0.2 : 1.0;
        v.userInteractionEnabled = !on;
    }
}

static void _cxxNoSync(id self, SEL _cmd) {
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    if (!mics || mics.count == 0) {
        _scanResult(self, NULL, nil, nil);
        mics = objc_getAssociatedObject(self, &kMicsKey);
    }
    for (UIView *v in mics) {
        v.userInteractionEnabled = NO;
        v.alpha = 0.15;
    }
}

static void _safeCxxNoSync(id self, SEL _cmd) {
    NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
    if (!mics || mics.count == 0) {
        _scanResult(self, NULL, nil, nil);
        mics = objc_getAssociatedObject(self, &kMicsKey);
    }
    for (UIView *v in mics) {
        v.userInteractionEnabled = NO;
        v.alpha = 0.25;
    }
}

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

static void _g3v(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(g3v:), arg, OBJC_ASSOCIATION_RETAIN); }
static id _getG3v(id self, SEL _cmd) { return objc_getAssociatedObject(self, @selector(g3v:)); }
static void _setG3v(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(g3v:), arg, OBJC_ASSOCIATION_RETAIN); }
static void _q2f(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(q2f:), arg, OBJC_ASSOCIATION_RETAIN); }
static id _getQ2f(id self, SEL _cmd) { return objc_getAssociatedObject(self, @selector(q2f:)); }
static void _setQ2f(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(q2f:), arg, OBJC_ASSOCIATION_RETAIN); }
static void _u8k(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(u8k:), arg, OBJC_ASSOCIATION_RETAIN); }
static id _getU8k(id self, SEL _cmd) { return objc_getAssociatedObject(self, @selector(u8k:)); }
static void _setU8k(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(u8k:), arg, OBJC_ASSOCIATION_RETAIN); }
static void _v7l(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(v7l:), arg, OBJC_ASSOCIATION_RETAIN); }
static id _getV7l(id self, SEL _cmd) { return objc_getAssociatedObject(self, @selector(v7l:)); }
static void _setV7l(id self, SEL _cmd, id arg) { objc_setAssociatedObject(self, @selector(v7l:), arg, OBJC_ASSOCIATION_RETAIN); }

static void _setSpeed(id self, SEL _cmd, id arg) {
    objc_setAssociatedObject(self, &kSpdKey, arg, OBJC_ASSOCIATION_RETAIN);
}

static void _changeSpeed(id self, SEL _cmd) {}
static void _setStatus(id self, SEL _cmd) {}

static void _timerTick(id self, SEL _cmd) {
    SEL s = NSSelectorFromString(@"lt_timerTick:");
    if ([self respondsToSelector:s]) {
        ((void(*)(id,SEL,id))[self methodForSelector:s])(self, s, nil);
    }
    id val = objc_getAssociatedObject(self, &kCxxKey);
    if ([val boolValue]) {
        NSArray *mics = objc_getAssociatedObject(self, &kMicsKey);
        if (mics) { for (UIView *v in mics) v.alpha = 0.15; }
    }
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

    ADDM(g3v:, _g3v, "v@:@");
    ADDM(setG3v:, _setG3v, "v@:@");
    ADDM(q2f:, _q2f, "v@:@");
    ADDM(setQ2f:, _setQ2f, "v@:@");
    ADDM(u8k:, _u8k, "v@:@");
    ADDM(setU8k:, _setU8k, "v@:@");
    ADDM(v7l:, _v7l, "v@:@");
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
            (__bridge CFStringRef)kNotifyHeartbeat, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (s_isMain) {
                [_YM showPass];
            } else {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    NSString *hb = [NSString stringWithFormat:@"%@.%d", kNotifyHeartbeat, s_instanceId];
                    CFNotificationCenterPostNotification(
                        CFNotificationCenterGetDarwinNotifyCenter(),
                        (__bridge CFStringRef)hb, NULL, NULL, YES);
                });
            }
        });
    }
}
