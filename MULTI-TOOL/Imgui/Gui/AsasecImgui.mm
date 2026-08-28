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
    if (!gInitialized)
        return;

    UITouch *touch = touches.anyObject;

    if (!touch)
        return;

    CGPoint point = [touch locationInView:self];

    ImGuiIO &io = ImGui::GetIO();

    io.MousePos = ImVec2(
        point.x,
        point.y
    );

    io.MouseDown[0] = true;

    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    UITouch *touch = touches.anyObject;

    if (!touch)
        return;

    CGPoint point = [touch locationInView:self];

    ImGuiIO &io = ImGui::GetIO();

    io.MousePos = ImVec2(
        point.x,
        point.y
    );

    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    UITouch *touch = touches.anyObject;

    if (touch)
    {
        CGPoint point = [touch locationInView:self];

        ImGuiIO &io = ImGui::GetIO();

        io.MousePos = ImVec2(
            point.x,
            point.y
        );
    }

    ImGui::GetIO().MouseDown[0] = false;

    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
                withEvent:(UIEvent *)event
{
    if (gInitialized)
    {
        ImGui::GetIO().MouseDown[0] = false;
    }

    [super touchesCancelled:touches withEvent:event];
}

@end


@interface ASASECImGuiRenderer : NSObject <MTKViewDelegate>
@end

@implementation ASASECImGuiRenderer

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    if (!gInitialized)
        return;

    ImGuiIO &io = ImGui::GetIO();

    io.DisplaySize = ImVec2(
        view.bounds.size.width,
        view.bounds.size.height
    );

    io.DisplayFramebufferScale = ImVec2(
        view.contentScaleFactor,
        view.contentScaleFactor
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

    if (!commandBuffer)
        return;

    ImGui_ImplMetal_NewFrame(passDescriptor);

    ImGuiIO &io = ImGui::GetIO();

    io.DisplaySize = ImVec2(
        view.bounds.size.width,
        view.bounds.size.height
    );

    io.DisplayFramebufferScale = ImVec2(
        view.contentScaleFactor,
        view.contentScaleFactor
    );

    ImGui::NewFrame();

    ImGui::SetNextWindowSize(
        ImVec2(340.0f, 420.0f),
        ImGuiCond_FirstUseEver
    );

    ImGui::SetNextWindowPos(
        ImVec2(40.0f, 80.0f),
        ImGuiCond_FirstUseEver
    );

    ImGui::Begin(
        "ASASEC MOD",
        nullptr,
        ImGuiWindowFlags_NoCollapse
    );

    ImGui::Text(
        "ASASEC ImGui"
    );

    ImGui::Separator();

    static bool option1 = false;
    static bool option2 = false;
    static bool option3 = false;

    static float value = 5.0f;

    ImGui::Spacing();

    if (ImGui::Checkbox(
        "Option 1",
        &option1))
    {
        NSLog(
            @"[ASASEC] Option 1: %s",
            option1 ? "ON" : "OFF"
        );
    }

    if (ImGui::Checkbox(
        "Option 2",
        &option2))
    {
        NSLog(
            @"[ASASEC] Option 2: %s",
            option2 ? "ON" : "OFF"
        );
    }

    if (ImGui::Checkbox(
        "Option 3",
        &option3))
    {
        NSLog(
            @"[ASASEC] Option 3: %s",
            option3 ? "ON" : "OFF"
        );
    }

    ImGui::Spacing();

    ImGui::Text(
        "Value"
    );

    ImGui::SliderFloat(
        "##value",
        &value,
        0.0f,
        10.0f,
        "%.1f"
    );

    ImGui::Spacing();

    if (ImGui::Button(
        "TEST",
        ImVec2(120.0f, 50.0f)))
    {
        NSLog(
            @"[ASASEC] TEST button pressed"
        );
    }

    ImGui::Spacing();

    ImGui::Separator();

    ImGui::Text(
        "Screen: %.0f x %.0f",
        io.DisplaySize.x,
        io.DisplaySize.y
    );

    ImGui::Text(
        "Scale: %.2f",
        view.contentScaleFactor
    );

    ImGui::End();

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer
            renderCommandEncoderWithDescriptor:
                passDescriptor];

    if (!encoder)
        return;

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

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

        UIWindow *window = nil;

        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes)
        {
            if (scene.activationState !=
                UISceneActivationStateForegroundActive)
            {
                continue;
            }

            if (![scene isKindOfClass:
                    [UIWindowScene class]])
            {
                continue;
            }

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

            if (window)
                break;
        }

        if (!window)
        {
            NSLog(
                @"[ASASEC] Window not found"
            );

            return;
        }

        id<MTLDevice> device =
            MTLCreateSystemDefaultDevice();

        if (!device)
        {
            NSLog(
                @"[ASASEC] Metal device unavailable"
            );

            return;
        }

        gCommandQueue =
            [device newCommandQueue];

        if (!gCommandQueue)
        {
            NSLog(
                @"[ASASEC] Command queue unavailable"
            );

            return;
        }

        ImGui::CreateContext();

        ImGuiIO &io = ImGui::GetIO();

        io.IniFilename = nullptr;

        io.FontGlobalScale = 1.5f;

        io.DisplaySize = ImVec2(
            window.bounds.size.width,
            window.bounds.size.height
        );

        io.DisplayFramebufferScale = ImVec2(
            window.screen.scale,
            window.screen.scale
        );

        ImGui::StyleColorsDark();

        ImGuiStyle &style =
            ImGui::GetStyle();

        style.WindowPadding =
            ImVec2(16.0f, 16.0f);

        style.FramePadding =
            ImVec2(12.0f, 10.0f);

        style.ItemSpacing =
            ImVec2(10.0f, 12.0f);

        style.ItemInnerSpacing =
            ImVec2(8.0f, 8.0f);

        style.ScrollbarSize =
            18.0f;

        style.GrabMinSize =
            24.0f;

        style.WindowRounding =
            10.0f;

        style.FrameRounding =
            6.0f;

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

        gImGuiView.preferredFramesPerSecond =
            60;

        gImGuiView.enableSetNeedsDisplay =
            NO;

        gImGuiView.paused =
            NO;

        gRenderer =
            [[ASASECImGuiRenderer alloc] init];

        gImGuiView.delegate =
            gRenderer;

        gImGuiView.multipleTouchEnabled =
            NO;

        [window addSubview:gImGuiView];

        [window bringSubviewToFront:gImGuiView];

        ImGui_ImplMetal_Init(device);

        gInitialized = YES;

        NSLog(
            @"[ASASEC] ImGui overlay started"
        );
    });
}


void ASASECImGuiStop(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

        if (!gInitialized)
            return;

        if (gImGuiView)
        {
            gImGuiView.delegate = nil;

            [gImGuiView removeFromSuperview];

            gImGuiView = nil;
        }

        ImGui_ImplMetal_Shutdown();

        ImGui::DestroyContext();

        gCommandQueue = nil;

        gRenderer = nil;

        gInitialized = NO;

        NSLog(
            @"[ASASEC] ImGui overlay stopped"
        );
    });
}
