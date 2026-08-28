#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <dispatch/dispatch.h>

#include "../imgui.h"
#include "../Backends/imgui_impl_metal.h"

static MTKView *gImGuiView = nil;
static id<MTLCommandQueue> gCommandQueue = nil;
static BOOL gInitialized = NO;

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return nil;

    return [super hitTest:point withEvent:event];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();

    UITouch *touch = touches.anyObject;

    CGPoint p = [touch locationInView:self];

    CGFloat scale = self.contentScaleFactor;

    io.MousePos = ImVec2(
        p.x * scale,
        p.y * scale
    );

    io.MouseDown[0] = true;

    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();

    UITouch *touch = touches.anyObject;

    CGPoint p = [touch locationInView:self];

    CGFloat scale = self.contentScaleFactor;

    io.MousePos = ImVec2(
        p.x * scale,
        p.y * scale
    );

    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();

    UITouch *touch = touches.anyObject;

    CGPoint p = [touch locationInView:self];

    CGFloat scale = self.contentScaleFactor;

    io.MousePos = ImVec2(
        p.x * scale,
        p.y * scale
    );

    io.MouseDown[0] = false;

    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
                withEvent:(UIEvent *)event
{
    ImGuiIO &io = ImGui::GetIO();

    io.MouseDown[0] = false;

    [super touchesCancelled:touches withEvent:event];
}

@end

@interface ASASECImGuiRenderer : NSObject <MTKViewDelegate>
@end

@implementation ASASECImGuiRenderer

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    ImGuiIO &io = ImGui::GetIO();

    io.DisplaySize = ImVec2(
        size.width,
        size.height
    );
}

- (void)drawInMTKView:(MTKView *)view
{
    if (!gInitialized)
        return;

    MTLRenderPassDescriptor *passDescriptor =
        view.currentRenderPassDescriptor;

    id<CAMetalDrawable> drawable =
        view.currentDrawable;

    if (!passDescriptor || !drawable)
        return;

    id<MTLCommandBuffer> commandBuffer =
        [gCommandQueue commandBuffer];

    ImGui_ImplMetal_NewFrame(passDescriptor);

    ImGuiIO &io = ImGui::GetIO();

    io.DisplaySize = ImVec2(
        view.drawableSize.width,
        view.drawableSize.height
    );

    ImGui::NewFrame();

    CGFloat scale = view.contentScaleFactor;

    if (scale <= 0.0)
        scale = 1.0;

    ImGui::SetNextWindowSize(
        ImVec2(
            340.0f * scale,
            420.0f * scale
        ),
        ImGuiCond_FirstUseEver
    );

    ImGui::SetNextWindowPos(
        ImVec2(
            40.0f * scale,
            80.0f * scale
        ),
        ImGuiCond_FirstUseEver
    );

    ImGui::Begin(
        "ASASEC MOD",
        nullptr,
        ImGuiWindowFlags_NoCollapse
    );

    ImGui::Text("ASASEC ImGui");

    ImGui::Separator();

    static bool option1 = false;
    static bool option2 = false;
    static float value = 5.0f;

    ImGui::Checkbox(
        "Option 1",
        &option1
    );

    ImGui::Checkbox(
        "Option 2",
        &option2
    );

    ImGui::SliderFloat(
        "Value",
        &value,
        0.0f,
        10.0f
    );

    if (ImGui::Button("Test"))
    {
        NSLog(@"[ASASEC] Test button pressed");
    }

    ImGui::Text(
        "Screen: %.0f x %.0f",
        io.DisplaySize.x,
        io.DisplaySize.y
    );

    ImGui::End();

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer
            renderCommandEncoderWithDescriptor:passDescriptor];

    [encoder setViewport:(MTLViewport){
        0.0,
        0.0,
        (double)view.drawableSize.width,
        (double)view.drawableSize.height,
        0.0,
        1.0
    }];

    ImGui_ImplMetal_RenderDrawData(
        ImGui::GetDrawData(),
        commandBuffer,
        encoder
    );

    [encoder endEncoding];

    [commandBuffer presentDrawable:drawable];

    [commandBuffer commit];
}

@end

static ASASECImGuiRenderer *gRenderer = nil;

void ASASECImGuiStart(void)
{
    if (gInitialized)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{

        UIWindow *window = nil;

        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes)
        {
            if (scene.activationState ==
                UISceneActivationStateForegroundActive)
            {
                if ([scene isKindOfClass:[UIWindowScene class]])
                {
                    UIWindowScene *windowScene =
                        (UIWindowScene *)scene;

                    for (UIWindow *candidate
                         in windowScene.windows)
                    {
                        if (candidate.isKeyWindow)
                        {
                            window = candidate;
                            break;
                        }
                    }
                }
            }

            if (window)
                break;
        }

        if (!window)
        {
            NSLog(@"[ASASEC] Window not found");
            return;
        }

        id<MTLDevice> device =
            MTLCreateSystemDefaultDevice();

        if (!device)
        {
            NSLog(@"[ASASEC] Metal unavailable");
            return;
        }

        gCommandQueue =
            [device newCommandQueue];

        gImGuiView =
            [[ASASECImGuiView alloc]
                initWithFrame:window.bounds
                device:device];

        gImGuiView.backgroundColor =
            UIColor.clearColor;

        gImGuiView.opaque = NO;

        gImGuiView.clearColor =
            MTLClearColorMake(
                0.0,
                0.0,
                0.0,
                0.0
            );

        gImGuiView.colorPixelFormat =
            MTLPixelFormatBGRA8Unorm;

        gImGuiView.preferredFramesPerSecond = 60;

        gImGuiView.enableSetNeedsDisplay = NO;
        gImGuiView.paused = NO;

        gRenderer =
            [[ASASECImGuiRenderer alloc] init];

        gImGuiView.delegate = gRenderer;

        [window addSubview:gImGuiView];

        ImGui::CreateContext();

        ImGuiIO &io = ImGui::GetIO();

        io.IniFilename = nullptr;

        io.ConfigFlags |=
            ImGuiConfigFlags_NavEnableKeyboard;

        ImGui::StyleColorsDark();

        ImGui_ImplMetal_Init(device);

        gInitialized = YES;

        NSLog(@"[ASASEC] ImGui touch overlay started");
    });
}

void ASASECImGuiStop(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{

        if (!gInitialized)
            return;

        if (gImGuiView)
        {
            [gImGuiView removeFromSuperview];
            gImGuiView = nil;
        }

        ImGui_ImplMetal_Shutdown();

        ImGui::DestroyContext();

        gCommandQueue = nil;
        gRenderer = nil;

        gInitialized = NO;

        NSLog(@"[ASASEC] ImGui stopped");
    });
}
