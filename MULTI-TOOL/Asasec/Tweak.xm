#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../Imgui/Gui/AsasecImgui.h"
#include "../Imgui/imgui.h"

%ctor
{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Pencerenin var olduğundan emin olun
        UIWindow *mainWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                mainWindow = window;
                break;
            }
        }
        
        if (mainWindow) {
            ASASECImGuiStart();
        } else {
            // Pencere hala yoksa alternatif olarak keyWindow deneyebilirsiniz
            ASASECImGuiStart();
        }
    });
}

