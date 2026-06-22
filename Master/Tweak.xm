#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static void postDarwin(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (__bridge CFStringRef)name, NULL, NULL, true);
}

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:@"com.yalla.yallalite"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIWindow *kw = [UIApplication sharedApplication].keyWindow;
            if (!kw) return;
            UIViewController *vc = kw.rootViewController;
            while (vc.presentedViewController) vc = vc.presentedViewController;
            if (!vc || !vc.view) return;

            UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(60, 200, 200, 60)];
            panel.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
            panel.layer.cornerRadius = 12;
            panel.layer.borderWidth = 2;
            panel.layer.borderColor = [UIColor blackColor].CGColor;

            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 60)];
            l.text = @"YallaMaster Loaded";
            l.textColor = [UIColor whiteColor];
            l.textAlignment = NSTextAlignmentCenter;
            l.font = [UIFont boldSystemFontOfSize:14];
            [panel addSubview:l];

            [vc.view addSubview:panel];
        });
    }
}
