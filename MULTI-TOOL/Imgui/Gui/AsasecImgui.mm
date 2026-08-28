#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include "../imgui.h"
#include "../Backends/imgui_impl_metal.h"

static MTKView *gImGuiView = nil;
static id<MTLCommandQueue> gCommandQueue = nil;
static BOOL gInitialized = NO;

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

    id<MTLCommandBuffer> commandBuffer =
        [gCommandQueue commandBuffer];

    MTLRenderPassDescriptor *passDescriptor =
        view.currentRenderPassDescriptor;

    if (!passDescriptor)
        return;

    ImGui_ImplMetal_NewFrame(passDescriptor);

    ImGuiIO &io = ImGui::GetIO();

    io.DisplaySize = ImVec2(
        view.drawableSize.width,
        view.drawableSize.height
    );

    ImGui::NewFrame();

    ImGui::SetNextWindowSize(
        ImVec2(320, 250),
        ImGuiCond_FirstUseEver
    );

    ImGui::Begin("ASASEC MOD");

    ImGui::Text("Hello from Dear ImGui!");

    ImGui::Separator();

    static bool option1 = false;
    static bool option2 = false;
    static float value = 5.0f;

    ImGui::Checkbox("Option 1", &option1);
    ImGui::Checkbox("Option 2", &option2);

    ImGui::SliderFloat(
        "Value",
        &value,
        0.0f,
        10.0f
    );

    if (ImGui::Button("Test"))
    {
        NSLog(@"[ASASEC] ImGui Test");
    }

    ImGui::End();

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
    [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];

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

[commandBuffer presentDrawable:view.currentDrawable];
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

        for (UIScene *scene in
             UIApplication.sharedApplication.connectedScenes)
        {
            if (scene.activationState ==
                UISceneActivationStateForegroundActive)
            {
                if ([scene isKindOfClass:[UIWindowScene class]])
                {
                    UIWindowScene *windowScene =
                        (UIWindowScene *)scene;

                    for (UIWindow *candidate in
                         windowScene.windows)
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
            NSLog(@"[ASASEC] Metal device unavailable");
            return;
        }

        gCommandQueue =
            [device newCommandQueue];

        gImGuiView =
            [[MTKView alloc] initWithFrame:window.bounds
                                    device:device];

        gImGuiView.backgroundColor =
            UIColor.clearColor;

        gImGuiView.opaque = NO;

        gImGuiView.clearColor =
            MTLClearColorMake(0, 0, 0, 0);

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

        ImGui::StyleColorsDark();

        ImGui_ImplMetal_Init(device);

        gInitialized = YES;

        NSLog(@"[ASASEC] ImGui overlay started");
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

        NSLog(@"[ASASEC] ImGui overlay stopped");
    });
}
