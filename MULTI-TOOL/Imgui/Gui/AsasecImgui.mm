#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <dispatch/dispatch.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include "../imgui.h"
#include "../imgui_internal.h"
#include "../Backends/imgui_impl_metal.h"

static MTKView *gImGuiView = nil;
static id<MTLCommandQueue> gCommandQueue = nil;
static BOOL gInitialized = NO;

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(50.0f, 80.0f);
static ImVec2 gMenuSize = ImVec2(520.0f, 400.0f);

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible) return NO;
    float x = (float)point.x;
    float y = (float)point.y;
    float left = gMenuPosition.x;
    float top = gMenuPosition.y;
    float right = left + gMenuSize.x;
    
    float activeHeight = gMenuCollapsed ? 46.0f : gMenuSize.y;
    float bottom = top + activeHeight;
    
    return (x >= left && x <= right && y >= top && y <= bottom);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (!gInitialized || !gMenuVisible) return nil;
    if ([self pointInsideMenu:point]) {
        return self;
    }
    return nil;
}

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    UITouch *anyTouch = event.allTouches.anyObject;
    if (!anyTouch) return;
    
    CGPoint touchLocation = [anyTouch locationInView:self];
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(touchLocation.x, touchLocation.y);

    BOOL hasActiveTouch = NO;
    for (UITouch *touch in event.allTouches)
    {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled)
        {
            hasActiveTouch = YES;
            break;
        }
    }
    io.MouseDown[0] = hasActiveTouch;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if (gInitialized) [self updateIOWithTouchEvent:event]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if (gInitialized) [self updateIOWithTouchEvent:event]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if (gInitialized) [self updateIOWithTouchEvent:event]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if (gInitialized) [self updateIOWithTouchEvent:event]; }

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
    io.DeltaTime = 1.0f / (view.preferredFramesPerSecond ?: 60.0f);

    ImGui::NewFrame();

    if (gMenuVisible)
    {
        float currentHeight = gMenuCollapsed ? 46.0f : gMenuSize.y;
        
        ImGui::SetNextWindowPos(gMenuPosition, ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSize(ImVec2(gMenuSize.x, currentHeight), ImGuiCond_Always);

        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0.0f, 0.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 14.0f);

        ImGuiWindowFlags flags = ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse;

        if (ImGui::Begin("ASASEC_MODERN_UI", &gMenuVisible, flags))
        {
            gMenuPosition = ImGui::GetWindowPos();
            if (!gMenuCollapsed) {
                gMenuSize.y = ImGui::GetWindowSize().y;
            }

            // --- ULTRA ŞIK BAŞLIK ÇUBUĞU ---
            ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.08f, 0.10f, 0.15f, 1.0f));
            ImGui::BeginChild("HeaderBar", ImVec2(0, 46.0f), false, ImGuiWindowFlags_NoScrollbar);

            ImGui::SetCursorPos(ImVec2(14.0f, 9.0f));

            // Küçültme Butonu
            const char* arrowText = gMenuCollapsed ? "+" : "-";
            if (ImGui::Button(arrowText, ImVec2(30.0f, 30.0f)))
            {
                gMenuCollapsed = !gMenuCollapsed;
            }

            ImGui::SameLine();
            ImGui::SetCursorPosY(ImGui::GetCursorPosY() + 7.0f);
            
            // Başlık Yazısı
            ImGui::TextColored(ImVec4(0.35f, 0.55f, 1.0f, 1.0f), "ASASEC");
            ImGui::SameLine();
            ImGui::TextColored(ImVec4(0.92f, 0.95f, 1.0f, 1.0f), "CONTROL PANEL");

            // Kapatma Butonu (X)
            ImGui::SameLine(gMenuSize.x - 44.0f);
            ImGui::SetCursorPosY(8.0f);
            
            ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.90f, 0.22f, 0.28f, 0.9f));
            ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(1.0f, 0.30f, 0.38f, 1.0f));
            if (ImGui::Button("X", ImVec2(30.0f, 30.0f)))
            {
                gMenuVisible = false;
            }
            ImGui::PopStyleColor(2);

            ImGui::EndChild();
            ImGui::PopStyleColor();

            // Sürükleme Özelliği
            if (ImGui::IsItemHovered() && ImGui::IsMouseDragging(0))
            {
                ImVec2 delta = ImGui::GetIO().MouseDelta;
                gMenuPosition.x += delta.x;
                gMenuPosition.y += delta.y;
            }

            // --- İÇERİK ALANI ---
            if (!gMenuCollapsed)
            {
                ImGui::Dummy(ImVec2(0.0f, 8.0f));
                ImGui::SetCursorPosX(14.0f);
                
                ImGui::BeginChild("ContentArea", ImVec2(gMenuSize.x - 28.0f, gMenuSize.y - 58.0f), false, ImGuiWindowFlags_NoScrollbar);
                
                if (ImGui::BeginTabBar("ToolTabBar", ImGuiTabBarFlags_FittingPolicyResizeDown))
                {
                    if (ImGui::BeginTabItem("Aimbot"))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("AimbotScroll", ImVec2(0, 270.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        
                        ImGui::TextColored(ImVec4(0.35f, 0.65f, 1.0f, 1.0f), "COMBAT SETTINGS");
                        ImGui::Separator();
                        ImGui::Spacing();

                        static bool aimbotActive = false;
                        static bool espBoxes = true;
                        static float fovSize = 90.0f;

                        ImGui::Checkbox("Enable Aimbot", &aimbotActive);
                        ImGui::Spacing();
                        ImGui::Checkbox("Show Box ESP", &espBoxes);
                        
                        ImGui::Spacing();
                        ImGui::SetNextItemWidth(220.0f);
                        ImGui::SliderFloat("FOV Radius", &fovSize, 10.0f, 180.0f, "%.1f");

                        ImGui::Spacing();
                        if (ImGui::Button("Reset Defaults", ImVec2(140.0f, 34.0f)))
                        {
                            aimbotActive = false;
                            espBoxes = true;
                            fovSize = 90.0f;
                        }

                        ImGui::EndChild();
                        ImGui::EndTabItem();
                    }

                    if (ImGui::BeginTabItem("Visuals"))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("VisualsScroll", ImVec2(0, 270.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextColored(ImVec4(0.25f, 0.95f, 0.55f, 1.0f), "VISUAL ESP SETTINGS");
                        ImGui::Separator();
                        ImGui::Spacing();
                        
                        static bool wallhack = false;
                        ImGui::Checkbox("Wallhack Feature", &wallhack);

                        ImGui::EndChild();
                        ImGui::EndTabItem();
                    }

                    if (ImGui::BeginTabItem("Settings"))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("SettingsScroll", ImVec2(0, 270.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextColored(ImVec4(1.0f, 0.65f, 0.25f, 1.0f), "SYSTEM INFO");
                        ImGui::Separator();
                        ImGui::Spacing();
                        ImGui::Text("Client: Asasec iOS Menu v2.0");
                        ImGui::Text("Status: Secure & Undetected");
                        ImGui::EndChild();
                        ImGui::EndTabItem();
                    }

                    ImGui::EndTabBar();
                }
                
                ImGui::EndChild();
            }
        }

        ImGui::End();
        ImGui::PopStyleVar(2);
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

        if (!window) return;

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) return;

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
        style.FramePadding = ImVec2(8.0f, 6.0f);
        style.ItemSpacing = ImVec2(8.0f, 8.0f);
        style.ScrollbarSize = 8.0f;
        style.WindowRounding = 14.0f;
        style.FrameRounding = 7.0f;

        // --- MODERN PREMIUM DARK GLASS RENK PALETİ ---
        ImVec4* colors = style.Colors;
        colors[ImGuiCol_WindowBg] = ImVec4(0.05f, 0.06f, 0.09f, 0.96f);
        colors[ImGuiCol_Header] = ImVec4(0.14f, 0.20f, 0.32f, 0.85f);
        colors[ImGuiCol_HeaderHovered] = ImVec4(0.18f, 0.26f, 0.42f, 1.0f);
        colors[ImGuiCol_HeaderActive] = ImVec4(0.22f, 0.32f, 0.52f, 1.0f);
        colors[ImGuiCol_Button] = ImVec4(0.13f, 0.17f, 0.26f, 1.0f);
        colors[ImGuiCol_ButtonHovered] = ImVec4(0.18f, 0.25f, 0.38f, 1.0f);
        colors[ImGuiCol_ButtonActive] = ImVec4(0.25f, 0.35f, 0.55f, 1.0f);
        colors[ImGuiCol_FrameBg] = ImVec4(0.09f, 0.12f, 0.18f, 1.0f);
        colors[ImGuiCol_FrameBgHovered] = ImVec4(0.13f, 0.17f, 0.25f, 1.0f);
        colors[ImGuiCol_FrameBgActive] = ImVec4(0.16f, 0.22f, 0.32f, 1.0f);
        colors[ImGuiCol_Tab] = ImVec4(0.07f, 0.09f, 0.13f, 1.0f);
        colors[ImGuiCol_TabHovered] = ImVec4(0.16f, 0.24f, 0.38f, 1.0f);
        colors[ImGuiCol_TabActive] = ImVec4(0.14f, 0.28f, 0.52f, 1.0f);
        colors[ImGuiCol_ChildBg] = ImVec4(0.03f, 0.04f, 0.06f, 1.0f);
        colors[ImGuiCol_SliderGrab] = ImVec4(0.22f, 0.48f, 0.90f, 1.0f);
        colors[ImGuiCol_SliderGrabActive] = ImVec4(0.32f, 0.62f, 1.0f, 1.0f);
        colors[ImGuiCol_CheckMark] = ImVec4(0.25f, 0.68f, 1.0f, 1.0f);

        gImGuiView = [[ASASECImGuiView alloc] initWithFrame:window.bounds device:device];
        gImGuiView.backgroundColor = UIColor.clearColor;
        gImGuiView.opaque = NO;
        gImGuiView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        gImGuiView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        gImGuiView.preferredFramesPerSecond = 60;
        gImGuiView.enableSetNeedsDisplay = NO;
        gImGuiView.paused = NO;
        gImGuiView.multipleTouchEnabled = YES;

        gRenderer = [[ASASECImGuiRenderer alloc] init];
        gImGuiView.delegate = gRenderer;

        [window addSubview:gImGuiView];
        [window bringSubviewToFront:gImGuiView];

        ImGui_ImplMetal_Init(device);
        gInitialized = YES;
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
        gMenuPosition = ImVec2(50.0f, 80.0f);
        gMenuSize = ImVec2(520.0f, 400.0f);
    });
}
