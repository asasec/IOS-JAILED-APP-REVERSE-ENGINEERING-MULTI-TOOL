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

static ImVec2 gMenuPosition = ImVec2(24.0f, 70.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 420.0f);

static int gSelectedTab = 0;

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    CGFloat scale = self.contentScaleFactor > 0.0 ? self.contentScaleFactor : 1.0;

    CGFloat x = point.x;
    CGFloat y = point.y;

    CGFloat left = gMenuPosition.x;
    CGFloat top = gMenuPosition.y;
    CGFloat right = left + gMenuSize.x;

    CGFloat height = gMenuCollapsed ? 52.0f : gMenuSize.y;
    CGFloat bottom = top + height;

    if (scale > 1.0)
    {
        left = gMenuPosition.x;
        top = gMenuPosition.y;
    }

    return x >= left &&
           x <= right &&
           y >= top &&
           y <= bottom;
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

    CGPoint location = [touch locationInView:self];

    ImGuiIO &io = ImGui::GetIO();

    io.MousePos = ImVec2(
        (float)location.x,
        (float)location.y
    );

    BOOL active = NO;

    for (UITouch *currentTouch in event.allTouches)
    {
        if (currentTouch.phase != UITouchPhaseEnded &&
            currentTouch.phase != UITouchPhaseCancelled)
        {
            active = YES;
            break;
        }
    }

    io.MouseDown[0] = active;
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

    if (view.bounds.size.width > 0 &&
        view.bounds.size.height > 0)
    {
        float maxX =
            view.bounds.size.width - gMenuSize.x - 8.0f;

        float maxY =
            view.bounds.size.height -
            (gMenuCollapsed ? 52.0f : gMenuSize.y) -
            8.0f;

        if (maxX < 8.0f)
            maxX = 8.0f;

        if (maxY < 8.0f)
            maxY = 8.0f;

        if (gMenuPosition.x > maxX)
            gMenuPosition.x = maxX;

        if (gMenuPosition.y > maxY)
            gMenuPosition.y = maxY;

        if (gMenuPosition.x < 8.0f)
            gMenuPosition.x = 8.0f;

        if (gMenuPosition.y < 8.0f)
            gMenuPosition.y = 8.0f;
    }
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

    if (!gCommandQueue)
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

    float fps = view.preferredFramesPerSecond;

    if (fps <= 0.0f)
        fps = 60.0f;

    io.DeltaTime = 1.0f / fps;

    ImGui::NewFrame();

    if (gMenuVisible)
    {
        const float headerHeight = 52.0f;

        float currentHeight =
            gMenuCollapsed ?
            headerHeight :
            gMenuSize.y;

        ImGui::SetNextWindowPos(
            gMenuPosition,
            ImGuiCond_Always
        );

        ImGui::SetNextWindowSize(
            ImVec2(gMenuSize.x, currentHeight),
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
            ImVec4(0.035f, 0.045f, 0.065f, 0.97f)
        );

        if (ImGui::Begin(
            "##ASASEC_MAIN",
            nullptr,
            flags))
        {
            gMenuPosition = ImGui::GetWindowPos();

            ImVec2 actualSize =
                ImGui::GetWindowSize();

            if (!gMenuCollapsed)
            {
                gMenuSize.x = actualSize.x;
                gMenuSize.y = actualSize.y;
            }

            ImDrawList *drawList =
                ImGui::GetWindowDrawList();

            ImVec2 windowPos =
                ImGui::GetWindowPos();

            ImVec2 windowSize =
                ImGui::GetWindowSize();

            drawList->AddRectFilled(
                windowPos,
                ImVec2(
                    windowPos.x + windowSize.x,
                    windowPos.y + windowSize.y
                ),
                IM_COL32(9, 12, 19, 248),
                18.0f
            );

            if (!gMenuCollapsed)
            {
                float sidebarWidth = 145.0f;

                ImVec2 sidebarMin =
                    windowPos;

                ImVec2 sidebarMax =
                    ImVec2(
                        windowPos.x + sidebarWidth,
                        windowPos.y + windowSize.y
                    );

                drawList->AddRectFilled(
                    sidebarMin,
                    sidebarMax,
                    IM_COL32(13, 17, 27, 255),
                    18.0f,
                    ImDrawFlags_RoundCornersLeft
                );

                ImGui::SetCursorPos(
                    ImVec2(18.0f, 13.0f)
                );

                ImGui::TextColored(
                    ImVec4(
                        0.28f,
                        0.62f,
                        1.0f,
                        1.0f
                    ),
                    "ASASEC"
                );

                ImGui::SameLine();

                ImGui::TextColored(
                    ImVec4(
                        0.70f,
                        0.74f,
                        0.82f,
                        1.0f
                    ),
                    "UI"
                );

                ImGui::SetCursorPos(
                    ImVec2(12.0f, 55.0f)
                );

                ImGui::PushStyleVar(
                    ImGuiStyleVar_ItemSpacing,
                    ImVec2(4.0f, 5.0f)
                );

                const char *tabs[] =
                {
                    "Combat",
                    "Visuals",
                    "Settings"
                };

                const char *icons[] =
                {
                    "A",
                    "V",
                    "S"
                };

                for (int i = 0; i < 3; i++)
                {
                    bool selected =
                        gSelectedTab == i;

                    ImGui::PushStyleColor(
                        ImGuiCol_Button,
                        selected ?
                        ImVec4(
                            0.12f,
                            0.30f,
                            0.56f,
                            1.0f
                        ) :
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
                            0.12f,
                            0.24f,
                            0.40f,
                            1.0f
                        )
                    );

                    ImGui::PushStyleColor(
                        ImGuiCol_ButtonActive,
                        ImVec4(
                            0.16f,
                            0.34f,
                            0.62f,
                            1.0f
                        )
                    );

                    char buttonID[64];

                    snprintf(
                        buttonID,
                        sizeof(buttonID),
                        "%s  %s##tab%d",
                        icons[i],
                        tabs[i],
                        i
                    );

                    if (ImGui::Button(
                        buttonID,
                        ImVec2(
                            sidebarWidth - 24.0f,
                            42.0f
                        )))
                    {
                        gSelectedTab = i;
                    }

                    ImGui::PopStyleColor(3);
                }

                ImGui::PopStyleVar();

                ImGui::SetCursorPos(
                    ImVec2(
                        sidebarWidth + 16.0f,
                        0.0f
                    )
                );

                ImGui::BeginChild(
                    "##MainContent",
                    ImVec2(
                        windowSize.x -
                        sidebarWidth -
                        16.0f,
                        windowSize.y
                    ),
                    false,
                    ImGuiWindowFlags_NoScrollbar
                );

                ImGui::SetCursorPos(
                    ImVec2(0.0f, 0.0f)
                );

                ImGui::BeginChild(
                    "##Header",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x,
                        headerHeight
                    ),
                    false,
                    ImGuiWindowFlags_NoScrollbar
                );

                ImGui::SetCursorPos(
                    ImVec2(8.0f, 10.0f)
                );

                ImGui::TextColored(
                    ImVec4(
                        0.92f,
                        0.95f,
                        1.0f,
                        1.0f
                    ),
                    "%s",
                    tabs[gSelectedTab]
                );

                ImGui::SameLine();

                ImGui::SetCursorPosY(13.0f);

                ImGui::TextColored(
                    ImVec4(
                        0.40f,
                        0.44f,
                        0.52f,
                        1.0f
                    ),
                    "CONTROL"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 82.0f
                );

                ImGui::PushStyleColor(
                    ImGuiCol_Button,
                    ImVec4(
                        0.09f,
                        0.12f,
                        0.18f,
                        1.0f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_ButtonHovered,
                    ImVec4(
                        0.15f,
                        0.20f,
                        0.30f,
                        1.0f
                    )
                );

                if (ImGui::Button(
                    "—",
                    ImVec2(30.0f, 30.0f)))
                {
                    gMenuCollapsed = YES;
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

                ImGui::PushStyleColor(
                    ImGuiCol_ButtonHovered,
                    ImVec4(
                        0.75f,
                        0.14f,
                        0.19f,
                        1.0f
                    )
                );

                if (ImGui::Button(
                    "×",
                    ImVec2(30.0f, 30.0f)))
                {
                    gMenuVisible = NO;
                }

                ImGui::PopStyleColor(4);

                ImGui::EndChild();

                ImGui::Separator();

                ImGui::SetCursorPosY(
                    ImGui::GetCursorPosY() + 10.0f
                );

                if (gSelectedTab == 0)
                {
                    ImGui::TextColored(
                        ImVec4(
                            0.30f,
                            0.65f,
                            1.0f,
                            1.0f
                        ),
                        "COMBAT"
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.43f,
                            0.47f,
                            0.55f,
                            1.0f
                        ),
                        "Configure combat options"
                    );

                    ImGui::Spacing();

                    static bool aimbotActive = false;
                    static bool espBoxes = true;
                    static bool autoFire = false;
                    static float fovSize = 90.0f;

                    ImGui::BeginChild(
                        "##CombatCard",
                        ImVec2(
                            ImGui::GetContentRegionAvail().x,
                            270.0f
                        ),
                        true
                    );

                    ImGui::Text(
                        "Aimbot"
                    );

                    ImGui::SameLine(
                        ImGui::GetContentRegionAvail().x - 52.0f
                    );

                    ImGui::Checkbox(
                        "##AimbotToggle",
                        &aimbotActive
                    );

                    ImGui::Separator();

                    ImGui::Spacing();

                    ImGui::Checkbox(
                        "Enable Aimbot",
                        &aimbotActive
                    );

                    ImGui::Checkbox(
                        "Show Box ESP",
                        &espBoxes
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
                        ImGui::GetContentRegionAvail().x
                    );

                    ImGui::SliderFloat(
                        "##FOV",
                        &fovSize,
                        10.0f,
                        180.0f,
                        "%.0f"
                    );

                    ImGui::Spacing();

                    if (ImGui::Button(
                        "Reset Defaults",
                        ImVec2(140.0f, 34.0f)))
                    {
                        aimbotActive = false;
                        espBoxes = true;
                        autoFire = false;
                        fovSize = 90.0f;
                    }

                    ImGui::EndChild();
                }
                else if (gSelectedTab == 1)
                {
                    ImGui::TextColored(
                        ImVec4(
                            0.28f,
                            0.85f,
                            0.58f,
                            1.0f
                        ),
                        "VISUALS"
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.43f,
                            0.47f,
                            0.55f,
                            1.0f
                        ),
                        "Visual configuration"
                    );

                    ImGui::Spacing();

                    static bool wallhack = false;
                    static bool playerESP = true;
                    static bool healthBar = true;

                    ImGui::BeginChild(
                        "##VisualCard",
                        ImVec2(
                            ImGui::GetContentRegionAvail().x,
                            250.0f
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
                            0.43f,
                            0.47f,
                            0.55f,
                            1.0f
                        ),
                        "Application information"
                    );

                    ImGui::Spacing();

                    ImGui::BeginChild(
                        "##SettingsCard",
                        ImVec2(
                            ImGui::GetContentRegionAvail().x,
                            210.0f
                        ),
                        true
                    );

                    ImGui::Text(
                        "ASASEC iOS Menu"
                    );

                    ImGui::Spacing();

                    ImGui::Text(
                        "Version"
                    );

                    ImGui::SameLine(
                        ImGui::GetContentRegionAvail().x - 70.0f
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.30f,
                            0.65f,
                            1.0f,
                            1.0f
                        ),
                        "2.1"
                    );

                    ImGui::Spacing();

                    ImGui::Text(
                        "Interface"
                    );

                    ImGui::SameLine(
                        ImGui::GetContentRegionAvail().x - 70.0f
                    );

                    ImGui::Text(
                        "Metal"
                    );

                    ImGui::Spacing();

                    ImGui::Text(
                        "Status"
                    );

                    ImGui::SameLine(
                        ImGui::GetContentRegionAvail().x - 70.0f
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

                ImGui::EndChild();
            }
            else
            {
                ImGui::SetCursorPos(
                    ImVec2(15.0f, 10.0f)
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
                        0.55f,
                        0.58f,
                        0.65f,
                        1.0f
                    ),
                    "CONTROL"
                );

                ImGui::SameLine(
                    ImGui::GetWindowWidth() - 72.0f
                );

                if (ImGui::Button(
                    "+",
                    ImVec2(30.0f, 30.0f)))
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
                    ImVec2(30.0f, 30.0f)))
                {
                    gMenuVisible = NO;
                }

                ImGui::PopStyleColor();
            }
        }

        ImGui::End();

        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);
    }

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];

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
        ImVec2(12.0f, 12.0f);

    style.FramePadding =
        ImVec2(10.0f, 7.0f);

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

    style.PopupBorderSize =
        0.0f;

    ImVec4 *colors =
        style.Colors;

    colors[ImGuiCol_Text] =
        ImVec4(
            0.92f,
            0.94f,
            0.98f,
            1.0f
        );

    colors[ImGuiCol_TextDisabled] =
        ImVec4(
            0.43f,
            0.47f,
            0.55f,
            1.0f
        );

    colors[ImGuiCol_WindowBg] =
        ImVec4(
            0.035f,
            0.045f,
            0.065f,
            0.97f
        );

    colors[ImGuiCol_ChildBg] =
        ImVec4(
            0.055f,
            0.068f,
            0.095f,
            0.98f
        );

    colors[ImGuiCol_Border] =
        ImVec4(
            0.12f,
            0.15f,
            0.21f,
            0.8f
        );

    colors[ImGuiCol_FrameBg] =
        ImVec4(
            0.075f,
            0.09f,
            0.125f,
            1.0f
        );

    colors[ImGuiCol_FrameBgHovered] =
        ImVec4(
            0.105f,
            0.14f,
            0.20f,
            1.0f
        );

    colors[ImGuiCol_FrameBgActive] =
        ImVec4(
            0.12f,
            0.18f,
            0.27f,
            1.0f
        );

    colors[ImGuiCol_Button] =
        ImVec4(
            0.075f,
            0.095f,
            0.135f,
            1.0f
        );

    colors[ImGuiCol_ButtonHovered] =
        ImVec4(
            0.11f,
            0.16f,
            0.24f,
            1.0f
        );

    colors[ImGuiCol_ButtonActive] =
        ImVec4(
            0.15f,
            0.24f,
            0.38f,
            1.0f
        );

    colors[ImGuiCol_CheckMark] =
        ImVec4(
            0.28f,
            0.65f,
            1.0f,
            1.0f
        );

    colors[ImGuiCol_SliderGrab] =
        ImVec4(
            0.22f,
            0.55f,
            1.0f,
            1.0f
        );

    colors[ImGuiCol_SliderGrabActive] =
        ImVec4(
            0.34f,
            0.68f,
            1.0f,
            1.0f
        );

    colors[ImGuiCol_Header] =
        ImVec4(
            0.10f,
            0.16f,
            0.25f,
            1.0f
        );

    colors[ImGuiCol_HeaderHovered] =
        ImVec4(
            0.13f,
            0.22f,
            0.34f,
            1.0f
        );

    colors[ImGuiCol_HeaderActive] =
        ImVec4(
            0.16f,
            0.28f,
            0.44f,
            1.0f
        );

    colors[ImGuiCol_Separator] =
        ImVec4(
            0.12f,
            0.15f,
            0.21f,
            0.7f
        );

    colors[ImGuiCol_Tab] =
        ImVec4(
            0.055f,
            0.07f,
            0.10f,
            1.0f
        );

    colors[ImGuiCol_TabHovered] =
        ImVec4(
            0.11f,
            0.18f,
            0.29f,
            1.0f
        );

    colors[ImGuiCol_TabActive] =
        ImVec4(
            0.12f,
            0.25f,
            0.45f,
            1.0f
        );
}


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

            io.IniFilename = nullptr;

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

            gImGuiView.opaque =
                NO;

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

            gImGuiView.multipleTouchEnabled =
                YES;

            gRenderer =
                [[ASASECImGuiRenderer alloc] init];

            gImGuiView.delegate =
                gRenderer;

            [window addSubview:gImGuiView];

            [window bringSubviewToFront:gImGuiView];

            ImGui_ImplMetal_Init(device);

            gInitialized =
                YES;
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

            if (gImGuiView)
            {
                gImGuiView.delegate =
                    nil;

                [gImGuiView removeFromSuperview];

                gImGuiView =
                    nil;
            }

            ImGui_ImplMetal_Shutdown();

            ImGui::DestroyContext();

            gCommandQueue =
                nil;

            gRenderer =
                nil;

            gInitialized =
                NO;

            gMenuVisible =
                YES;

            gMenuCollapsed =
                NO;

            gSelectedTab =
                0;

            gMenuPosition =
                ImVec2(
                    24.0f,
                    70.0f
                );

            gMenuSize =
                ImVec2(
                    560.0f,
                    420.0f
                );
        }
    );
}
