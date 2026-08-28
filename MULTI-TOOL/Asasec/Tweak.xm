#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../Imgui/Gui/AsasecImgui.h"

%ctor
{
    dispatch_async(dispatch_get_main_queue(), ^{
        ASASECImGuiStart();
    });
}
