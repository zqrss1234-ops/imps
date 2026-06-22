#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define kYallaBundle @"com.yalla.yallalite"

static void postDarwin(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (__bridge CFStringRef)name, NULL, NULL, true);
}

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:kYallaBundle]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *kw = [UIApplication sharedApplication].keyWindow;
            if (!kw) return;
            UIViewController *vc = kw.rootViewController;
            while (vc.presentedViewController) vc = vc.presentedViewController;
            if (!vc || !vc.view) return;
            UIView *cv = vc.view;

            UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(60, 150, 220, 120)];
            panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
            panel.layer.cornerRadius = 18;
            panel.layer.borderWidth = 2;
            panel.layer.borderColor = [UIColor blackColor].CGColor;
            panel.clipsToBounds = YES;

            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 200, 20)];
            l.text = @"YallaMaster Active";
            l.textColor = [UIColor whiteColor];
            l.font = [UIFont boldSystemFontOfSize:12];
            [panel addSubview:l];

            UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
            btn.frame = CGRectMake(10, 40, 200, 36);
            btn.layer.cornerRadius = 8;
            btn.backgroundColor = [UIColor blackColor];
            btn.layer.borderWidth = 1;
            btn.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
            [btn setTitle:@"Hide" forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            btn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            [panel addSubview:btn];

            UILabel *st = [[UILabel alloc] initWithFrame:CGRectMake(10, 85, 200, 16)];
            st.textAlignment = NSTextAlignmentCenter;
            st.textColor = [UIColor whiteColor];
            st.font = [UIFont systemFontOfSize:9];
            st.text = @"Ready";
            [panel addSubview:st];

            [cv addSubview:panel];
        });
    }
}
