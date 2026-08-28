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

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(40.0f, 80.0f);
static ImVec2 gMenuSize = ImVec2(480.0f, 360.0f);

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    float x = (float)point.x;
    float y = (float)point.y;

    float left = gMenuPosition.x;
    float top = gMenuPosition.y;
    float right = left + gMenuSize.x;
    float bottom = top + gMenuSize.y;

    return (x >= left && x <= right && y >= top && y <= bottom);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (!gInitialized || !gMenuVisible)
        return nil;

    if ([self pointInsideMenu:point])
    {
        return self;
    }

    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (!gInitialized) return;
    UITouch *touch = touches.anyObject;
    if (!touch) return;
    CGPoint point = [touch locationInView:self];
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(point.x, point.y);
    io.MouseDown[0] = true;
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (!gInitialized) return;
    UITouch *touch = touches.anyObject;
    if (!touch) return;
    CGPoint point = [touch locationInView:self];
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(point.x, point.y);
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (!gInitialized) return;
    UITouch *touch = touches.anyObject;
    if (touch)
    {
        CGPoint point = [touch locationInView:self];
        ImGui::GetIO().MousePos = ImVec2(point.x, point.y);
    }
    ImGui::GetIO().MouseDown[0] = false;
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
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

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    if (!gInitialized) return;
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(view.bounds.size.width, view.bounds.size.height);
    io.DisplayFramebufferScale = ImVec2(view.contentScaleFactor, view.contentScaleFactor);
}

- (void)drawInMTKView:(MTKView *)view
{
    if (!gInitialized) return;

    MTLRenderPassDescriptor *passDescriptor = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;

    if (!passDescriptor || !drawable) return;

    id<MTLCommandBuffer> commandBuffer = [gCommandQueue commandBuffer];
    if (!commandBuffer) return;

    ImGui_ImplMetal_NewFrame(passDescriptor);

    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(view.bounds.size.width, view.bounds.size.height);
    io.DisplayFramebufferScale = ImVec2(view.contentScaleFactor, view.contentScaleFactor);

    ImGui::NewFrame();

    if (gMenuVisible)
    {
        ImGui::SetNextWindowPos(gMenuPosition, ImGuiCond_Always);
        ImGui::SetNextWindowSize(gMenuSize, ImGuiCond_Always);

        // Standart başlık çubuğu kullanıyoruz (Sürükleme ve sağ üstte 'X' kapatma butonu aktif)
        ImGuiWindowFlags flags = ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse;

        // p_open parametresi (&gMenuVisible) sağ üstteki X tuşuna basıldığında menüyü kapatır
        if (ImGui::Begin("My First Tool", &gMenuVisible, flags))
        {
            gMenuPosition = ImGui::GetWindowPos();
            gMenuSize = ImGui::GetWindowSize();

            // Başlık satırının başına gidip küçültme okunu ekliyoruz (Yazının solunda yer alır)
            ImGui::SameLine(8.0f);
            
            const char* arrowText = gMenuCollapsed ? ">" : "v";
            if (ImGui::Button(arrowText, ImVec2(18.0f, 16.0f)))
            {
                gMenuCollapsed = !gMenuCollapsed;
                if (gMenuCollapsed)
                {
                    gMenuSize.y = 35.0f; // Sadece başlık yüksekliği
                }
                else
                {
                    gMenuSize.y = 360.0f; // Normal yükseklik
                }
            }

            // Menü daraltılmadıysa sekmeleri ve içerikleri göster
            if (!gMenuCollapsed)
            {
                ImGui::Spacing();

                // Sekmeler Arası Tek Basışta Akıcı Geçiş
                if (ImGui::BeginTabBar("ToolTabBar", ImGuiTabBarFlags_FittingPolicyResizeDown))
                {
                    // --- AIMBOT KATEGORİSİ ---
                    if (ImGui::BeginTabItem("Aimbot"))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("AimbotScroll", ImVec2(0, 220.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.2f, 1.0f), "Important Stuff");
                        ImGui::Separator();
                        ImGui::Text("0000: Some text");
                        ImGui::Text("0001: Some text");
                        ImGui::Text("0002: Some text");
                        ImGui::Text("0003: Some text");
                        ImGui::Text("0004: Some text");
                        ImGui::Text("0005: Some text");
                        ImGui::Text("0006: Some text");
                        ImGui::Text("0007: Some text");
                        ImGui::Text("0008: Some text");
                        ImGui::Text("0009: Some text");
                        ImGui::EndChild();
                        ImGui::EndTabItem();
                    }

                    // --- VISUALS KATEGORİSİ ---
                    if (ImGui::BeginTabItem("Visuals"))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("VisualsScroll", ImVec2(0, 220.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextColored(ImVec4(0.2f, 1.0f, 0.5f, 1.0f), "Visuals Content");
                        ImGui::Separator();
                        ImGui::Text("ESP Configs & Objects");
                        ImGui::EndChild();
                        ImGui::EndTabItem();
                    }

                    // --- OTHER KATEGORİSİ ---
                    if (ImGui::BeginTabItem("Other"))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("OtherScroll", ImVec2(0, 220.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextColored(ImVec4(0.4f, 0.7f, 1.0f, 1.0f), "Miscellaneous");
                        ImGui::Separator();
                        ImGui::Text("Other settings & info");
                        ImGui::EndChild();
                        ImGui::EndTabItem();
                    }

                    ImGui::EndTabBar();
                }
            }
        }

        ImGui::End();
    }

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
    if (!encoder) return;

    [encoder setViewport:(MTLViewport){
        0.0, 0.0,
        (double)view.drawableSize.width,
        (double)view.drawableSize.height,
        0.0, 1.0
    }];

    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);

    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end

static ASASECImGuiRenderer *gRenderer = nil;

void ASASECImGuiStart(void)
{
    if (gInitialized) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;

        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *candidate in windowScene.windows)
            {
                if (candidate.isKeyWindow)
                {
                    window = candidate;
                    break;
                }
            }
            if (window) break;
        }

        if (!window)
        {
            NSLog(@"[ASASEC] Window not found");
            return;
        }

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device)
        {
            NSLog(@"[ASASEC] Metal unavailable");
            return;
        }

        gCommandQueue = [device newCommandQueue];
        if (!gCommandQueue) return;

        ImGui::CreateContext();
        ImGuiIO &io = ImGui::GetIO();
        io.IniFilename = nullptr;
        io.FontGlobalScale = 1.15f;

        io.DisplaySize = ImVec2(window.bounds.size.width, window.bounds.size.height);
        io.DisplayFramebufferScale = ImVec2(window.screen.scale, window.screen.scale);

        ImGui::StyleColorsDark();
        ImGuiStyle &style = ImGui::GetStyle();
        style.WindowPadding = ImVec2(10.0f, 10.0f);
        style.FramePadding = ImVec2(6.0f, 5.0f);
        style.ItemSpacing = ImVec2(6.0f, 6.0f);
        style.ScrollbarSize = 12.0f;
        style.WindowRounding = 8.0f;
        style.FrameRounding = 4.0f;

        // Koyu gri / mavi şık tema renkleri
        ImVec4* colors = style.Colors;
        colors[ImGuiCol_WindowBg] = ImVec4(0.12f, 0.14f, 0.18f, 0.95f);
        colors[ImGuiCol_TitleBg] = ImVec4(0.16f, 0.20f, 0.26f, 1.0f);
        colors[ImGuiCol_TitleBgActive] = ImVec4(0.20f, 0.26f, 0.35f, 1.0f);
        colors[ImGuiCol_Tab] = ImVec4(0.15f, 0.18f, 0.24f, 1.0f);
        colors[ImGuiCol_TabHovered] = ImVec4(0.25f, 0.35f, 0.50f, 1.0f);
        colors[ImGuiCol_TabActive] = ImVec4(0.20f, 0.45f, 0.80f, 1.0f);
        colors[ImGuiCol_ChildBg] = ImVec4(0.09f, 0.11f, 0.14f, 1.0f);

        gImGuiView = [[ASASECImGuiView alloc] initWithFrame:window.bounds device:device];
        gImGuiView.backgroundColor = UIColor.clearColor;
        gImGuiView.opaque = NO;
        gImGuiView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        gImGuiView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        gImGuiView.preferredFramesPerSecond = 60;
        gImGuiView.enableSetNeedsDisplay = NO;
        gImGuiView.paused = NO;
        gImGuiView.multipleTouchEnabled = NO;

        gRenderer = [[ASASECImGuiRenderer alloc] init];
        gImGuiView.delegate = gRenderer;

        [window addSubview:gImGuiView];
        [window bringSubviewToFront:gImGuiView];

        ImGui_ImplMetal_Init(device);
        gInitialized = YES;

        NSLog(@"[ASASEC] Collapse button moved to the left of the title successfully");
    });
}

void ASASECImGuiStop(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gInitialized) return;

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
        gMenuVisible = YES;
        gMenuCollapsed = NO;
        gMenuPosition = ImVec2(40.0f, 80.0f);
        gMenuSize = ImVec2(480.0f, 360.0f);
    });
}
