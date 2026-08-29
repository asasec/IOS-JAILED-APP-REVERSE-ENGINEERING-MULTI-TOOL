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

static ImVec2 gMenuPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 390.0f);

static int gSelectedPage = 0;

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    float width = gMenuSize.x;
    float height = gMenuCollapsed ? 50.0f : gMenuSize.y;

    return
        point.x >= gMenuPosition.x &&
        point.x <= gMenuPosition.x + width &&
        point.y >= gMenuPosition.y &&
        point.y <= gMenuPosition.y + height;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (!gInitialized || !gMenuVisible)
        return nil;

    if ([self pointInsideMenu:point])
        return self;

    return nil;
}

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    UITouch *touch = event.allTouches.anyObject;

    if (!touch)
        return;

    CGPoint point = [touch locationInView:self];

    ImGuiIO &io = ImGui::GetIO();

    io.MousePos = ImVec2(
        (float)point.x,
        (float)point.y
    );

    BOOL touching = NO;

    for (UITouch *t in event.allTouches)
    {
        if (t.phase != UITouchPhaseEnded &&
            t.phase != UITouchPhaseCancelled)
        {
            touching = YES;
            break;
        }
    }

    io.MouseDown[0] = touching;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    [self updateIOWithTouchEvent:event];
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

    if (!gCommandQueue)
        return;

    MTLRenderPassDescriptor *pass =
        view.currentRenderPassDescriptor;

    id<CAMetalDrawable> drawable =
        view.currentDrawable;

    if (!pass || !drawable)
        return;

    id<MTLCommandBuffer> commandBuffer =
        [gCommandQueue commandBuffer];

    if (!commandBuffer)
        return;

    ImGui_ImplMetal_NewFrame(pass);

    ImGuiIO &io = ImGui::GetIO();

    io.DisplaySize = ImVec2(
        view.bounds.size.width,
        view.bounds.size.height
    );

    io.DisplayFramebufferScale = ImVec2(
        view.contentScaleFactor,
        view.contentScaleFactor
    );

    float fps = view.preferredFramesPerSecond;

    if (fps <= 0.0f)
        fps = 60.0f;

    io.DeltaTime = 1.0f / fps;

    ImGui::NewFrame();

    if (gMenuVisible)
    {
        const float headerHeight = 50.0f;

        float windowHeight =
            gMenuCollapsed ?
            headerHeight :
            gMenuSize.y;

        ImGui::SetNextWindowPos(
            gMenuPosition,
            ImGuiCond_Always
        );

        ImGui::SetNextWindowSize(
            ImVec2(
                gMenuSize.x,
                windowHeight
            ),
            ImGuiCond_Always
        );

        ImGuiWindowFlags flags =
            ImGuiWindowFlags_NoTitleBar |
            ImGuiWindowFlags_NoResize |
            ImGuiWindowFlags_NoCollapse |
            ImGuiWindowFlags_NoScrollbar |
            ImGuiWindowFlags_NoScrollWithMouse |
            ImGuiWindowFlags_NoSavedSettings;

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowPadding,
            ImVec2(0.0f, 0.0f)
        );

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowRounding,
            18.0f
        );

        ImGui::PushStyleColor(
            ImGuiCol_WindowBg,
            ImVec4(
                0.035f,
                0.045f,
                0.065f,
                0.97f
            )
        );

        ImGui::Begin(
            "##ASASEC_WINDOW",
            NULL,
            flags
        );

        ImVec2 windowPos =
            ImGui::GetWindowPos();

        ImVec2 windowSize =
            ImGui::GetWindowSize();

        gMenuPosition = windowPos;

        if (!gMenuCollapsed)
        {
            gMenuSize = windowSize;
        }

        ImDrawList *draw =
            ImGui::GetWindowDrawList();

        draw->AddRectFilled(
            windowPos,
            ImVec2(
                windowPos.x + windowSize.x,
                windowPos.y + windowSize.y
            ),
            IM_COL32(8, 11, 18, 248),
            18.0f
        );

        if (gMenuCollapsed)
        {
            ImGui::SetCursorPos(
                ImVec2(16.0f, 10.0f)
            );

            ImGui::TextColored(
                ImVec4(
                    0.30f,
                    0.65f,
                    1.0f,
                    1.0f
                ),
                "ASASEC"
            );

            ImGui::SameLine();

            ImGui::TextColored(
                ImVec4(
                    0.50f,
                    0.54f,
                    0.62f,
                    1.0f
                ),
                "CONTROL"
            );

            ImGui::SameLine(
                windowSize.x - 72.0f
            );

            if (ImGui::Button(
                "+",
                ImVec2(28.0f, 30.0f)
            ))
            {
                gMenuCollapsed = NO;
            }

            ImGui::SameLine(0.0f, 5.0f);

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.55f,
                    0.10f,
                    0.14f,
                    1.0f
                )
            );

            if (ImGui::Button(
                "×",
                ImVec2(28.0f, 30.0f)
            ))
            {
                gMenuVisible = NO;
            }

            ImGui::PopStyleColor();
        }
        else
        {
            const float sidebarWidth = 142.0f;

            draw->AddRectFilled(
                windowPos,
                ImVec2(
                    windowPos.x + sidebarWidth,
                    windowPos.y + windowSize.y
                ),
                IM_COL32(12, 16, 25, 255),
                18.0f,
                ImDrawFlags_RoundCornersLeft
            );

            ImGui::SetCursorPos(
                ImVec2(18.0f, 13.0f)
            );

            ImGui::TextColored(
                ImVec4(
                    0.30f,
                    0.65f,
                    1.0f,
                    1.0f
                ),
                "ASASEC"
            );

            ImGui::SameLine();

            ImGui::TextColored(
                ImVec4(
                    0.48f,
                    0.52f,
                    0.60f,
                    1.0f
                ),
                "UI"
            );

            ImGui::SetCursorPos(
                ImVec2(10.0f, 55.0f)
            );

            const char *pages[] =
            {
                "Combat",
                "Visuals",
                "Settings"
            };

            const char *pageIcons[] =
            {
                "A",
                "V",
                "S"
            };

            for (int i = 0; i < 3; i++)
            {
                bool active =
                    gSelectedPage == i;

                if (active)
                {
                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x + 10.0f,
                            windowPos.y + 55.0f +
                            i * 48.0f
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth - 10.0f,
                            windowPos.y + 55.0f +
                            i * 48.0f +
                            40.0f
                        ),
                        IM_COL32(24, 61, 112, 255),
                        9.0f
                    );
                }

                char buttonID[64];

                snprintf(
                    buttonID,
                    sizeof(buttonID),
                    "%s  %s##page_%d",
                    pageIcons[i],
                    pages[i],
                    i
                );

                ImGui::PushStyleColor(
                    ImGuiCol_Button,
                    ImVec4(
                        0.0f,
                        0.0f,
                        0.0f,
                        0.0f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_ButtonHovered,
                    ImVec4(
                        0.10f,
                        0.18f,
                        0.30f,
                        0.8f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_ButtonActive,
                    ImVec4(
                        0.12f,
                        0.25f,
                        0.42f,
                        1.0f
                    )
                );

                if (ImGui::Button(
                    buttonID,
                    ImVec2(
                        sidebarWidth - 20.0f,
                        40.0f
                    )
                ))
                {
                    gSelectedPage = i;
                }

                ImGui::PopStyleColor(3);

                ImGui::SetCursorPosY(
                    ImGui::GetCursorPosY() + 8.0f
                );
            }

            ImGui::SetCursorPos(
                ImVec2(
                    sidebarWidth + 1.0f,
                    0.0f
                )
            );

            ImGui::BeginChild(
                "##Content",
                ImVec2(
                    windowSize.x -
                    sidebarWidth - 1.0f,
                    windowSize.y
                ),
                false,
                ImGuiWindowFlags_NoScrollbar
            );

            ImGui::SetCursorPos(
                ImVec2(14.0f, 10.0f)
            );

            ImGui::TextColored(
                ImVec4(
                    0.92f,
                    0.94f,
                    0.98f,
                    1.0f
                ),
                "%s",
                pages[gSelectedPage]
            );

            ImGui::SameLine();

            ImGui::TextColored(
                ImVec4(
                    0.35f,
                    0.39f,
                    0.47f,
                    1.0f
                ),
                " / ASASEC"
            );

            ImGui::SameLine(
                ImGui::GetContentRegionAvail().x - 62.0f
            );

            if (ImGui::Button(
                "—",
                ImVec2(27.0f, 29.0f)
            ))
            {
                gMenuCollapsed = YES;
            }

            ImGui::SameLine(0.0f, 5.0f);

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.50f,
                    0.08f,
                    0.12f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.70f,
                    0.12f,
                    0.17f,
                    1.0f
                )
            );

            if (ImGui::Button(
                "×",
                ImVec2(27.0f, 29.0f)
            ))
            {
                gMenuVisible = NO;
            }

            ImGui::PopStyleColor(2);

            ImGui::SetCursorPosY(
                ImGui::GetCursorPosY() + 10.0f
            );

            ImGui::Separator();

            ImGui::SetCursorPosY(
                ImGui::GetCursorPosY() + 12.0f
            );

            if (gSelectedPage == 0)
            {
                ImGui::TextColored(
                    ImVec4(
                        0.30f,
                        0.65f,
                        1.0f,
                        1.0f
                    ),
                    "COMBAT SETTINGS"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.40f,
                        0.44f,
                        0.52f,
                        1.0f
                    ),
                    "Configure your combat options"
                );

                ImGui::Spacing();

                static bool aimbot = false;
                static bool esp = true;
                static bool autoFire = false;
                static float fov = 90.0f;

                ImGui::BeginChild(
                    "##CombatCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        265.0f
                    ),
                    true
                );

                ImGui::TextColored(
                    ImVec4(
                        0.90f,
                        0.93f,
                        0.98f,
                        1.0f
                    ),
                    "Aimbot"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 48.0f
                );

                ImGui::Checkbox(
                    "##AimbotMain",
                    &aimbot
                );

                ImGui::Separator();

                ImGui::Spacing();

                ImGui::Checkbox(
                    "Enable Aimbot",
                    &aimbot
                );

                ImGui::Checkbox(
                    "Box ESP",
                    &esp
                );

                ImGui::Checkbox(
                    "Auto Fire",
                    &autoFire
                );

                ImGui::Spacing();

                ImGui::Text(
                    "FOV Radius"
                );

                ImGui::SetNextItemWidth(
                    ImGui::GetContentRegionAvail().x - 10.0f
                );

                ImGui::SliderFloat(
                    "##FOV",
                    &fov,
                    10.0f,
                    180.0f,
                    "%.0f"
                );

                ImGui::Spacing();

                if (ImGui::Button(
                    "Reset",
                    ImVec2(90.0f, 32.0f)
                ))
                {
                    aimbot = false;
                    esp = true;
                    autoFire = false;
                    fov = 90.0f;
                }

                ImGui::EndChild();
            }
            else if (gSelectedPage == 1)
            {
                ImGui::TextColored(
                    ImVec4(
                        0.30f,
                        0.85f,
                        0.58f,
                        1.0f
                    ),
                    "VISUAL SETTINGS"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.40f,
                        0.44f,
                        0.52f,
                        1.0f
                    ),
                    "Configure visual options"
                );

                ImGui::Spacing();

                static bool playerESP = true;
                static bool healthBar = true;
                static bool wallhack = false;

                ImGui::BeginChild(
                    "##VisualCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        220.0f
                    ),
                    true
                );

                ImGui::Text(
                    "ESP"
                );

                ImGui::Separator();

                ImGui::Spacing();

                ImGui::Checkbox(
                    "Player ESP",
                    &playerESP
                );

                ImGui::Checkbox(
                    "Health Bar",
                    &healthBar
                );

                ImGui::Checkbox(
                    "Wallhack",
                    &wallhack
                );

                ImGui::EndChild();
            }
            else
            {
                ImGui::TextColored(
                    ImVec4(
                        1.0f,
                        0.65f,
                        0.28f,
                        1.0f
                    ),
                    "SETTINGS"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.40f,
                        0.44f,
                        0.52f,
                        1.0f
                    ),
                    "ASASEC configuration"
                );

                ImGui::Spacing();

                ImGui::BeginChild(
                    "##SettingsCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        220.0f
                    ),
                    true
                );

                ImGui::Text(
                    "Application"
                );

                ImGui::Separator();

                ImGui::Spacing();

                ImGui::Text(
                    "Version"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 65.0f
                );

                ImGui::TextColored(
                    ImVec4(
                        0.30f,
                        0.65f,
                        1.0f,
                        1.0f
                    ),
                    "3.0"
                );

                ImGui::Spacing();

                ImGui::Text(
                    "Renderer"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 65.0f
                );

                ImGui::Text(
                    "Metal"
                );

                ImGui::Spacing();

                ImGui::Text(
                    "Status"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 65.0f
                );

                ImGui::TextColored(
                    ImVec4(
                        0.30f,
                        0.85f,
                        0.55f,
                        1.0f
                    ),
                    "ACTIVE"
                );

                ImGui::EndChild();
            }

            ImGui::EndChild();
        }

        ImGui::End();

        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);
    }

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:pass];

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


static void ASASECApplyStyle(void)
{
    ImGuiStyle &style = ImGui::GetStyle();

    style.WindowPadding =
        ImVec2(10.0f, 10.0f);

    style.FramePadding =
        ImVec2(9.0f, 7.0f);

    style.ItemSpacing =
        ImVec2(8.0f, 8.0f);

    style.ItemInnerSpacing =
        ImVec2(6.0f, 6.0f);

    style.ScrollbarSize =
        7.0f;

    style.GrabMinSize =
        12.0f;

    style.WindowRounding =
        18.0f;

    style.ChildRounding =
        12.0f;

    style.FrameRounding =
        8.0f;

    style.PopupRounding =
        10.0f;

    style.ScrollbarRounding =
        8.0f;

    style.GrabRounding =
        8.0f;

    style.TabRounding =
        8.0f;

    style.WindowBorderSize =
        0.0f;

    style.ChildBorderSize =
        1.0f;

    style.FrameBorderSize =
        0.0f;

    ImVec4 *c =
        style.Colors;

    c[ImGuiCol_Text] =
        ImVec4(
            0.92f,
            0.94f,
            0.98f,
            1.0f
        );

    c[ImGuiCol_TextDisabled] =
        ImVec4(
            0.42f,
            0.46f,
            0.54f,
            1.0f
        );

    c[ImGuiCol_WindowBg] =
        ImVec4(
            0.035f,
            0.045f,
            0.065f,
            0.97f
        );

    c[ImGuiCol_ChildBg] =
        ImVec4(
            0.055f,
            0.068f,
            0.095f,
            0.98f
        );

    c[ImGuiCol_Border] =
        ImVec4(
            0.12f,
            0.15f,
            0.21f,
            0.8f
        );

    c[ImGuiCol_FrameBg] =
        ImVec4(
            0.075f,
            0.09f,
            0.125f,
            1.0f
        );

    c[ImGuiCol_FrameBgHovered] =
        ImVec4(
            0.11f,
            0.14f,
            0.20f,
            1.0f
        );

    c[ImGuiCol_FrameBgActive] =
        ImVec4(
            0.13f,
            0.19f,
            0.28f,
            1.0f
        );

    c[ImGuiCol_Button] =
        ImVec4(
            0.075f,
            0.095f,
            0.135f,
            1.0f
        );

    c[ImGuiCol_ButtonHovered] =
        ImVec4(
            0.11f,
            0.16f,
            0.24f,
            1.0f
        );

    c[ImGuiCol_ButtonActive] =
        ImVec4(
            0.15f,
            0.25f,
            0.40f,
            1.0f
        );

    c[ImGuiCol_CheckMark] =
        ImVec4(
            0.28f,
            0.65f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_SliderGrab] =
        ImVec4(
            0.22f,
            0.55f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_SliderGrabActive] =
        ImVec4(
            0.34f,
            0.68f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_Header] =
        ImVec4(
            0.10f,
            0.16f,
            0.25f,
            1.0f
        );

    c[ImGuiCol_HeaderHovered] =
        ImVec4(
            0.13f,
            0.22f,
            0.34f,
            1.0f
        );

    c[ImGuiCol_HeaderActive] =
        ImVec4(
            0.16f,
            0.28f,
            0.44f,
            1.0f
        );

    c[ImGuiCol_Separator] =
        ImVec4(
            0.12f,
            0.15f,
            0.21f,
            0.75f
        );
}


void ASASECImGuiStart(void)
{
    if (gInitialized)
        return;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (gInitialized)
                return;

            UIWindow *window = nil;

            for (UIScene *scene
                 in UIApplication.sharedApplication.connectedScenes)
            {
                if (scene.activationState !=
                    UISceneActivationStateForegroundActive)
                    continue;

                if (![scene isKindOfClass:
                     [UIWindowScene class]])
                    continue;

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
                return;

            id<MTLDevice> device =
                MTLCreateSystemDefaultDevice();

            if (!device)
                return;

            gCommandQueue =
                [device newCommandQueue];

            if (!gCommandQueue)
                return;

            ImGui::CreateContext();

            ImGuiIO &io =
                ImGui::GetIO();

            io.IniFilename = NULL;
            io.FontGlobalScale = 1.0f;

            io.DisplaySize =
                ImVec2(
                    window.bounds.size.width,
                    window.bounds.size.height
                );

            CGFloat scale =
                window.screen.scale;

            if (scale <= 0.0)
                scale = 1.0;

            io.DisplayFramebufferScale =
                ImVec2(
                    scale,
                    scale
                );

            ASASECApplyStyle();

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

            gImGuiView.paused = NO;

            gImGuiView.multipleTouchEnabled =
                YES;

            gRenderer =
                [[ASASECImGuiRenderer alloc] init];

            gImGuiView.delegate =
                gRenderer;

            [window addSubview:gImGuiView];

            [window bringSubviewToFront:gImGuiView];

            ImGui_ImplMetal_Init(device);

            gInitialized = YES;
        }
    );
}


void ASASECImGuiStop(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!gInitialized)
                return;

            gInitialized = NO;

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

            gMenuVisible = YES;
            gMenuCollapsed = NO;

            gSelectedPage = 0;

            gMenuPosition =
                ImVec2(
                    25.0f,
                    75.0f
                );

            gMenuSize =
                ImVec2(
                    560.0f,
                    390.0f
                );
        }
    );
}
