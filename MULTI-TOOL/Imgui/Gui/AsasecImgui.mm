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

static ImVec2 gMenuPosition = ImVec2(40.0f, 80.0f);
static ImVec2 gMenuSize = ImVec2(480.0f, 360.0f);

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
    
    float activeHeight = gMenuCollapsed ? 42.0f : gMenuSize.y;
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
        float currentHeight = gMenuCollapsed ? 42.0f : gMenuSize.y;
        
        ImGui::SetNextWindowPos(gMenuPosition, ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSize(ImVec2(gMenuSize.x, currentHeight), ImGuiCond_Always);

        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0.0f, 0.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 8.0f); // Modern yuvarlatılmış köşeler

        ImGuiWindowFlags flags = ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse;

        if (ImGui::Begin("My First Tool", &gMenuVisible, flags))
        {
            gMenuPosition = ImGui::GetWindowPos();
            if (!gMenuCollapsed) {
                gMenuSize.y = ImGui::GetWindowSize().y;
            }

            // --- ÜST DÜZEY PROFESYONEL BAŞLIK ÇUBUĞU ---
            ImGui::PushStyleColor(ImGuiCol_ChildBg, ImVec4(0.10f, 0.18f, 0.32f, 1.0f)); // Derin Karbon Mavi
            ImGui::BeginChild("HeaderBar", ImVec2(0, 42.0f), false, ImGuiWindowFlags_NoScrollbar);

            ImGui::SetCursorPos(ImVec2(10.0f, 7.0f));

            // Küçültme Butonu (< / v)
            const char* arrowText = gMenuCollapsed ? ">" : "v";
            if (ImGui::Button(arrowText, ImVec2(28.0f, 28.0f)))
            {
                gMenuCollapsed = !gMenuCollapsed;
            }

            ImGui::SameLine();
            ImGui::SetCursorPosY(ImGui::GetCursorPosY() + 5.0f);
            
            // Başlık Yazısı Kalın ve Şık
            ImGui::TextColored(ImVec4(0.9f, 0.95f, 1.0f, 1.0f), "ASASEC MULTI-TOOL");

            // Kapatma Butonu (X)
            ImGui::SameLine(gMenuSize.x - 38.0f);
            ImGui::SetCursorPosY(7.0f);
            
            // Kapatma butonuna özel kırmızımsı vurgu
            ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.8f, 0.2f, 0.2f, 0.8f));
            ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.9f, 0.3f, 0.3f, 1.0f));
            if (ImGui::Button("X", ImVec2(28.0f, 28.0f)))
            {
                gMenuVisible = false;
            }
            ImGui::PopStyleColor(2);

            ImGui::EndChild();
            ImGui::PopStyleColor();

            // Sürükleme Algılama
            if (ImGui::IsItemHovered() && ImGui::IsMouseDragging(0))
            {
                ImVec2 delta = ImGui::GetIO().MouseDelta;
                gMenuPosition.x += delta.x;
                gMenuPosition.y += delta.y;
            }

            // --- İÇERİK ALANI ---
            if (!gMenuCollapsed)
            {
                ImGui::Dummy(ImVec2(0.0f, 6.0f));
                
                // İçerik paneli sol/sağ boşluklu
                ImGui::SetCursorPosX(10.0f);
                ImGui::BeginChild("ContentArea", ImVec2(gMenuSize.x - 20.0f, gMenuSize.y - 54.0f), false, ImGuiWindowFlags_NoScrollbar);
                
                if (ImGui::BeginTabBar("ToolTabBar", ImGuiTabBarFlags_FittingPolicyResizeDown))
                {
                    if (ImGui::BeginTabItem("Aimbot"))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("AimbotScroll", ImVec2(0, 240.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        
                        ImGui::TextColored(ImVec4(0.3f, 0.8f, 1.0f, 1.0f), ">> AIMBOT KONTROL MERKEZI");
                        ImGui::Separator();
                        ImGui::Spacing();

                        static bool aimbotActive = false;
                        static bool espBoxes = true;
                        static float fovSize = 90.0f;

                        ImGui::Checkbox("Aimbot Aktif Et", &aimbotActive);
                        ImGui::Spacing();
                        ImGui::Checkbox("Kutu ESP Goster", &espBoxes);
                        
                        ImGui::Spacing();
                        ImGui::SetNextItemWidth(220.0f); // Slider uzunluğunu ayarla
                        ImGui::SliderFloat("FOV Boyutu", &fovSize, 10.0f, 180.0f, "%.1f px");

                        ImGui::Spacing();
                        if (ImGui::Button("Sifirla", ImVec2(120.0f, 32.0f)))
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
                        ImGui::BeginChild("VisualsScroll", ImVec2(0, 240.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextColored(ImVec4(0.3f, 1.0f, 0.6f, 1.0f), ">> GORSEL OZELLIKLER");
                        ImGui::Separator();
                        ImGui::Spacing();
                        
                        static bool wallhack = false;
                        ImGui::Checkbox("Wallhack (ESP)", &wallhack);

                        ImGui::EndChild();
                        ImGui::EndTabItem();
                    }

                    if (ImGui::BeginTabItem("Other"))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("OtherScroll", ImVec2(0, 240.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextColored(ImVec4(1.0f, 0.7f, 0.3f, 1.0f), ">> DIGER AYARLAR");
                        ImGui::Separator();
                        ImGui::Spacing();
                        ImGui::Text("Gelistirici: Asasec");
                        ImGui::Text("Durum: Calisiyor (Stable)");
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
        style.ScrollbarSize = 10.0f;
        style.WindowRounding = 10.0f;
        style.FrameRounding = 6.0f; // Buton ve kutu köşelerini yumuşattık

        // Üst Düzey Modern Renk Paleti
        ImVec4* colors = style.Colors;
        colors[ImGuiCol_WindowBg] = ImVec4(0.08f, 0.10f, 0.14f, 0.96f); // Şık koyu zemin
        colors[ImGuiCol_Header] = ImVec4(0.18f, 0.30f, 0.50f, 0.8f);
        colors[ImGuiCol_HeaderHovered] = ImVec4(0.22f, 0.38f, 0.65f, 1.0f);
        colors[ImGuiCol_HeaderActive] = ImVec4(0.25f, 0.45f, 0.75f, 1.0f);
        colors[ImGuiCol_Button] = ImVec4(0.16f, 0.24f, 0.38f, 1.0f);
        colors[ImGuiCol_ButtonHovered] = ImVec4(0.22f, 0.34f, 0.54f, 1.0f);
        colors[ImGuiCol_ButtonActive] = ImVec4(0.28f, 0.44f, 0.70f, 1.0f);
        colors[ImGuiCol_FrameBg] = ImVec4(0.12f, 0.15f, 0.22f, 1.0f);
        colors[ImGuiCol_FrameBgHovered] = ImVec4(0.16f, 0.22f, 0.32f, 1.0f);
        colors[ImGuiCol_FrameBgActive] = ImVec4(0.20f, 0.28f, 0.42f, 1.0f);
        colors[ImGuiCol_Tab] = ImVec4(0.12f, 0.16f, 0.24f, 1.0f);
        colors[ImGuiCol_TabHovered] = ImVec4(0.20f, 0.32f, 0.52f, 1.0f);
        colors[ImGuiCol_TabActive] = ImVec4(0.18f, 0.35f, 0.65f, 1.0f);
        colors[ImGuiCol_ChildBg] = ImVec4(0.06f, 0.08f, 0.11f, 1.0f);
        colors[ImGuiCol_SliderGrab] = ImVec4(0.25f, 0.50f, 0.90f, 1.0f);
        colors[ImGuiCol_SliderGrabActive] = ImVec4(0.35f, 0.65f, 1.0f, 1.0f);

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
        gMenuPosition = ImVec2(40.0f, 80.0f);
        gMenuSize = ImVec2(480.0f, 360.0f);
    });
}
