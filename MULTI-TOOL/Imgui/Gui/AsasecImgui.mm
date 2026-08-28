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
        return [super hitTest:point withEvent:event];
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

        // ImGui pencere flags (NoCollapse kaldırıldı ki kendi özel ok sistemimizi kullanalım)
        ImGuiWindowFlags flags = ImGuiWindowFlags_NoResize;

        // Başlık kısmına tıklandığında veya ok düğmesine basıldığında menünün daraltılması kontrolü
        // ImGui'nin başlık çubuğuna özel buton eklemek için custom bir yapı veya ImGui'nin kendi collapse mekanizması kullanılabilir.
        // Burada başlık yanına koyduğumuz buton ile entegre çalışması için p_open kullanılabilir veya özel satır çizilebilir.
        // En temiz ve stabil yöntem: Pencere başlığını standart tutup, hemen altına ok butonunu koymak VEYA 
        // ImGui'nin yerleşik başlık çubuğu yerine kendi custom başlık çubuğumuzu simüle etmektir.
        // İstediğiniz gibi başlığın en sağına ok koyabilmek için pencere bayraklarına ImGuiWindowFlags_NoTitleBar ekleyip özel başlık yapabiliriz:
        
        flags |= ImGuiWindowFlags_NoTitleBar;

        if (ImGui::Begin("GUIDEDHACKING Menu", nullptr, flags))
        {
            gMenuPosition = ImGui::GetWindowPos();
            gMenuSize = ImGui::GetWindowSize();

            // --- ÖZEL BAŞLIK ÇUBUĞU (GUIDEDHACKING Menu ve Sağda Ok Butonu) ---
            ImGui::Text("GUIDEDHACKING Menu");
            
            // Aynı satırda sağ tarafa yaklaşmak için cursor'ı kaydırıyoruz
            float windowWidth = ImGui::GetWindowWidth();
            ImGui::SameLine(windowWidth - 45.0f);

            // Ok Butonu (Basıldığında yön değiştirecek ve menüyü kapatıp açacak)
            const char* arrowText = gMenuCollapsed ? ">" : "v";
            if (ImGui::Button(arrowText, ImVec2(28.0f, 24.0f)))
            {
                gMenuCollapsed = !gMenuCollapsed;
                // Eğer daraltıldıysa yüksekliği sadece başlık sığacak kadar küçültelim, açıldığında eski boyuta döndürelim
                if (gMenuCollapsed)
                {
                    gMenuSize.y = 50.0f; // Sadece başlık yüksekliği
                }
                else
                {
                    gMenuSize.y = 360.0f; // Orijinal açılmış yükseklik
                }
            }

            ImGui::Separator();

            // Eğer menü daraltılmadıysa sekmeleri ve içeriği göster
            if (!gMenuCollapsed)
            {
                ImGui::Spacing();

                // Üst Yatay Sekmeler (Aimbot, Visuals, Other)
                if (ImGui::BeginTabBar("GHStyleTabBar", ImGuiTabBarFlags_NoReorder))
                {
                    // --- AIMBOT SEKMESI ---
                    if (ImGui::BeginTabItem("  Aimbot  "))
                    {
                        ImGui::Spacing();

                        float contentWidth = ImGui::GetContentRegionAvail().x;
                        float leftPanelWidth = contentWidth * 0.45f;

                        ImGui::BeginChild("AimbotLeftPanel", ImVec2(leftPanelWidth, 180.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextDisabled("Buraya checkbox'lar gelecek");
                        ImGui::EndChild();

                        ImGui::SameLine();

                        ImGui::BeginChild("AimbotRightPanel", ImVec2(0, 180.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextDisabled("Buraya alt özellikler gelecek");
                        ImGui::EndChild();

                        ImGui::EndTabItem();
                    }

                    // --- VISUALS SEKMESI ---
                    if (ImGui::BeginTabItem("  Visuals  "))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("VisualsScrollArea", ImVec2(0, 180.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextDisabled("Visuals içerikleri buraya eklenecek...");
                        ImGui::EndChild();
                        ImGui::EndTabItem();
                    }

                    // --- OTHER SEKMESI ---
                    if (ImGui::BeginTabItem("  Other  "))
                    {
                        ImGui::Spacing();
                        ImGui::BeginChild("OtherScrollArea", ImVec2(0, 180.0f), true, ImGuiWindowFlags_AlwaysVerticalScrollbar);
                        ImGui::TextDisabled("Other içerikleri buraya eklenecek...");
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

        NSLog(@"[ASASEC] GuidedHacking custom header started");
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
