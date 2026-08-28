#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../Imgui/Gui/AsasecImgui.h"
#include "../Imgui/imgui.h"

// UIWindow hook ile dokunma olaylarını ve sürüklemeyi ImGui'ye aktarıyoruz
%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches) {
        NSSet *allTouches = [event allTouches];
        if (allTouches && allTouches.count > 0) {
            UITouch *touch = allTouches.anyObject;
            CGPoint point = [touch locationInView:nil];
            
            ImGuiIO &io = ImGui::GetIO();
            io.MousePos = ImVec2(point.x, point.y);
            
            if (touch.phase == UITouchPhaseBegan) {
                io.MouseDown[0] = true;
            } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                io.MouseDown[0] = false;
            }
        }
    }
    %orig;
}
%end

%ctor
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ASASECImGuiStart();
    });
}
