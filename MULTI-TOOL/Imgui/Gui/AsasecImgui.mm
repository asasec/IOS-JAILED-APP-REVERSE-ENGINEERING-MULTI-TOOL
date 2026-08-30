#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <float.h>
#import <string.h>
#import <stdint.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include "../imgui.h"
#include "../imgui_internal.h"
#include "../Backends/imgui_impl_metal.h"

#pragma mark - Forward Declarations

@interface ASASECImGuiRenderer : NSObject <MTKViewDelegate>
@end

@interface ASASECImGuiView : MTKView
@end

#pragma mark - Global State

static ASASECImGuiView *gImGuiView = nil;
static ASASECImGuiRenderer *gRenderer = nil;

static id<MTLDevice> gMetalDevice = nil;
static id<MTLCommandQueue> gCommandQueue = nil;

/*
 * ASASEC'in kendi ImGui context'i.
 *
 * ÖNEMLİ:
 * Artık ImGui::GetCurrentContext() üzerinden rastgele bir
 * context'i destroy etmiyoruz.
 */
static ImGuiContext *gASASECImGuiContext = NULL;

/*
 * Start sırasında o anda mevcut olan context'i saklıyoruz.
 * Stop sonrasında mümkünse geri yükleniyor.
 */
static ImGuiContext *gPreviousImGuiContext = NULL;

static BOOL gInitialized = NO;
static BOOL gStarting = NO;
static BOOL gStopping = NO;
static BOOL gMetalInitialized = NO;

/*
 * Backend'in gerçekten ASASEC tarafından initialize edilip
 * edilmediğini ayrıca takip ediyoruz.
 */
static BOOL gASASECBackendOwned = NO;

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 390.0f);

static const float kMenuMinWidth  = 430.0f;
static const float kMenuMaxWidth  = 760.0f;
static const float kMenuMinHeight = 300.0f;
static const float kMenuMaxHeight = 620.0f;

static const float kHeaderHeight = 54.0f;

static int gSelectedPage = 0;
static int gPreviousPage = 0;

static BOOL gDraggingMenu = NO;
static BOOL gResizingMenu = NO;
static BOOL gContentDragging = NO;

static CGPoint gDragStartPoint = CGPointZero;
static CGPoint gResizeStartPoint = CGPointZero;
static CGPoint gContentStartPoint = CGPointZero;
static CGPoint gContentLastPoint = CGPointZero;

static ImVec2 gDragStartPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gResizeStartSize = ImVec2(560.0f, 390.0f);

static float gPendingContentScrollY = 0.0f;
static float gContentScrollVelocity = 0.0f;

static BOOL gContentHasMoved = NO;
static BOOL gContentTouchCandidate = NO;

static float gPageAnimation = 1.0f;
static float gPageSlide = 0.0f;

static NSUInteger gActiveTouchCount = 0;

/*
 * Renderer callback sırasında stop işlemi başlarsa ikinci bir
 * lifecycle işlemi yapılmasını önlüyoruz.
 */
static BOOL gRenderingFrame = NO;

#pragma mark - Helpers

static float ASASECClampFloat(float value,
                              float minValue,
                              float maxValue)
{
    if (!isfinite(value))
        return minValue;

    if (value < minValue)
        return minValue;

    if (value > maxValue)
        return maxValue;

    return value;
}

static float ASASECEase(float current,
                        float target,
                        float speed,
                        float dt)
{
    if (!isfinite(current))
        current = target;

    if (!isfinite(target))
        target = current;

    if (!isfinite(dt) ||
        dt <= 0.0f ||
        dt > 0.1f)
    {
        dt = 1.0f / 60.0f;
    }

    if (!isfinite(speed) ||
        speed <= 0.0f)
    {
        return target;
    }

    float factor =
        1.0f -
        expf(-speed * dt);

    if (!isfinite(factor))
        return target;

    factor =
        ASASECClampFloat(
            factor,
            0.0f,
            1.0f
        );

    float result =
        current +
        (target - current) * factor;

    if (!isfinite(result))
        return target;

    return result;
}

static ImU32 ASASECColor(float r,
                         float g,
                         float b,
                         float a)
{
    r = ASASECClampFloat(r, 0.0f, 1.0f);
    g = ASASECClampFloat(g, 0.0f, 1.0f);
    b = ASASECClampFloat(b, 0.0f, 1.0f);
    a = ASASECClampFloat(a, 0.0f, 1.0f);

    return ImGui::ColorConvertFloat4ToU32(
        ImVec4(r, g, b, a)
    );
}

static UIWindow *ASASECFindActiveWindow(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (!application)
        return nil;

    /*
     * Öncelik:
     * ForegroundActive + keyWindow
     */
    for (UIScene *scene in application.connectedScenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive)
        {
            continue;
        }

        for (UIWindow *window in windowScene.windows)
        {
            if (!window)
                continue;

            if (window.hidden)
                continue;

            if (window.alpha <= 0.0)
                continue;

            if (window.isKeyWindow)
                return window;
        }
    }

    /*
     * Foreground aktif herhangi bir window.
     */
    for (UIScene *scene in application.connectedScenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive)
        {
            continue;
        }

        for (UIWindow *window in windowScene.windows)
        {
            if (!window)
                continue;

            if (window.hidden)
                continue;

            if (window.alpha <= 0.0)
                continue;

            return window;
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

    UIWindow *keyWindow =
        application.keyWindow;

#pragma clang diagnostic pop

    if (keyWindow &&
        !keyWindow.hidden &&
        keyWindow.alpha > 0.0)
    {
        return keyWindow;
    }

    return nil;
}

static void ASASECClampMenuToScreen(UIWindow *window)
{
    if (!window)
        return;

    CGSize size =
        window.bounds.size;

    if (!isfinite(size.width) ||
        !isfinite(size.height) ||
        size.width <= 0.0 ||
        size.height <= 0.0)
    {
        return;
    }

    float maximumWidth =
        MAX(
            100.0f,
            (float)size.width - 16.0f
        );

    float maximumHeight =
        MAX(
            100.0f,
            (float)size.height - 16.0f
        );

    float minWidth =
        MIN(
            kMenuMinWidth,
            maximumWidth
        );

    float maxWidth =
        MIN(
            kMenuMaxWidth,
            maximumWidth
        );

    float minHeight =
        MIN(
            kMenuMinHeight,
            maximumHeight
        );

    float maxHeight =
        MIN(
            kMenuMaxHeight,
            maximumHeight
        );

    if (maxWidth < minWidth)
        minWidth = maxWidth;

    if (maxHeight < minHeight)
        minHeight = maxHeight;

    gMenuSize.x =
        ASASECClampFloat(
            gMenuSize.x,
            minWidth,
            maxWidth
        );

    gMenuSize.y =
        ASASECClampFloat(
            gMenuSize.y,
            minHeight,
            maxHeight
        );

    float visibleHeight =
        gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    float maxX =
        (float)size.width -
        gMenuSize.x -
        8.0f;

    float maxY =
        (float)size.height -
        visibleHeight -
        8.0f;

    if (maxX < 8.0f)
        maxX = 8.0f;

    if (maxY < 8.0f)
        maxY = 8.0f;

    gMenuPosition.x =
        ASASECClampFloat(
            gMenuPosition.x,
            8.0f,
            maxX
        );

    gMenuPosition.y =
        ASASECClampFloat(
            gMenuPosition.y,
            8.0f,
            maxY
        );
}

#pragma mark - Switch Animation

typedef struct
{
    const char *label;
    float progress;
    float pulse;
}
ASASECSwitchAnimation;

static ASASECSwitchAnimation
gSwitchAnimations[64];

static int gSwitchAnimationCount = 0;

static ASASECSwitchAnimation *
ASASECGetSwitchAnimationData(const char *label)
{
    if (!label)
        return NULL;

    for (int i = 0;
         i < gSwitchAnimationCount;
         i++)
    {
        if (!gSwitchAnimations[i].label)
            continue;

        if (strcmp(
                gSwitchAnimations[i].label,
                label
            ) == 0)
        {
            return &gSwitchAnimations[i];
        }
    }

    if (gSwitchAnimationCount >= 64)
        return NULL;

    int index =
        gSwitchAnimationCount++;

    gSwitchAnimations[index].label =
        label;

    gSwitchAnimations[index].progress =
        0.0f;

    gSwitchAnimations[index].pulse =
        0.0f;

    return &gSwitchAnimations[index];
}

#pragma mark - Modern Switch

static bool ASASECModernSwitch(const char *label,
                               bool *value)
{
    if (!label || !value)
        return false;

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return false;

    ImGui::PushID(label);

    const float switchWidth = 48.0f;
    const float switchHeight = 26.0f;
    const float rowHeight = 52.0f;

    float available =
        ImGui::GetContentRegionAvail().x;

    if (!isfinite(available) ||
        available < 200.0f)
    {
        available = 200.0f;
    }

    bool clicked =
        ImGui::InvisibleButton(
            "##switch",
            ImVec2(
                available,
                rowHeight
            )
        );

    ImVec2 itemMin =
        ImGui::GetItemRectMin();

    ImVec2 itemMax =
        ImGui::GetItemRectMax();

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    ASASECSwitchAnimation *animation =
        ASASECGetSwitchAnimationData(label);

    if (clicked)
    {
        *value =
            !(*value);

        if (animation)
            animation->pulse =
                1.0f;
    }

    bool hovered =
        ImGui::IsItemHovered();

    float dt =
        ImGui::GetIO().DeltaTime;

    if (!isfinite(dt) ||
        dt <= 0.0f ||
        dt > 0.1f)
    {
        dt =
            1.0f / 60.0f;
    }

    float progress =
        animation
        ? animation->progress
        : (*value ? 1.0f : 0.0f);

    progress =
        ASASECEase(
            progress,
            *value ? 1.0f : 0.0f,
            16.0f,
            dt
        );

    if (animation)
    {
        animation->progress =
            progress;

        animation->pulse =
            ASASECEase(
                animation->pulse,
                0.0f,
                12.0f,
                dt
            );
    }

    float pulse =
        animation
        ? animation->pulse
        : 0.0f;

    if (draw)
    {
        ImU32 background =
            hovered
            ? ASASECColor(
                0.075f,
                0.100f,
                0.145f,
                0.98f
            )
            : ASASECColor(
                0.052f,
                0.070f,
                0.105f,
                0.98f
            );

        ImU32 border =
            hovered
            ? ASASECColor(
                0.18f,
                0.28f,
                0.42f,
                0.80f
            )
            : ASASECColor(
                0.12f,
                0.17f,
                0.25f,
                0.75f
            );

        draw->AddRectFilled(
            itemMin,
            itemMax,
            background,
            11.0f
        );

        draw->AddRect(
            ImVec2(
                itemMin.x + 0.5f,
                itemMin.y + 0.5f
            ),
            ImVec2(
                itemMax.x - 0.5f,
                itemMax.y - 0.5f
            ),
            border,
            11.0f,
            0,
            1.0f
        );

        float switchX =
            itemMax.x -
            switchWidth -
            14.0f;

        float switchY =
            itemMin.y +
            (rowHeight -
             switchHeight) *
            0.5f;

        ImVec2 switchMin =
            ImVec2(
                switchX,
                switchY
            );

        ImVec2 switchMax =
            ImVec2(
                switchX + switchWidth,
                switchY + switchHeight
            );

        float bgR =
            0.09f +
            (0.18f - 0.09f) *
            progress;

        float bgG =
            0.13f +
            (0.52f - 0.13f) *
            progress;

        float bgB =
            0.20f +
            (0.95f - 0.20f) *
            progress;

        draw->AddRectFilled(
            switchMin,
            switchMax,
            ASASECColor(
                bgR,
                bgG,
                bgB,
                1.0f
            ),
            switchHeight * 0.5f
        );

        float knobX =
            switchMin.x +
            13.0f +
            (
                switchMax.x -
                13.0f -
                (switchMin.x + 13.0f)
            ) *
            progress;

        float knobY =
            switchMin.y +
            switchHeight * 0.5f;

        float knobRadius =
            9.0f +
            pulse * 1.3f;

        if (pulse > 0.01f)
        {
            draw->AddCircle(
                ImVec2(
                    knobX,
                    knobY
                ),
                12.0f +
                pulse * 3.0f,
                ASASECColor(
                    0.30f,
                    0.68f,
                    1.0f,
                    pulse * 0.30f
                ),
                24,
                1.6f
            );
        }

        draw->AddCircleFilled(
            ImVec2(
                knobX,
                knobY + 1.0f
            ),
            knobRadius + 0.8f,
            ASASECColor(
                0.0f,
                0.0f,
                0.0f,
                0.30f
            )
        );

        draw->AddCircleFilled(
            ImVec2(
                knobX,
                knobY
            ),
            knobRadius,
            ASASECColor(
                0.96f,
                0.98f,
                1.0f,
                1.0f
            )
        );

        ImVec2 cursor =
            ImGui::GetCursorPos();

        ImGui::SetCursorPos(
            ImVec2(
                cursor.x + 15.0f,
                cursor.y -
                rowHeight +
                8.0f
            )
        );

        ImGui::TextColored(
            ImVec4(
                0.92f,
                0.95f,
                1.0f,
                1.0f
            ),
            "%s",
            label
        );

        ImGui::SetCursorPos(
            ImVec2(
                cursor.x + 15.0f,
                cursor.y -
                rowHeight +
                29.0f
            )
        );

        ImGui::TextColored(
            ImVec4(
                0.38f,
                0.44f,
                0.53f,
                1.0f
            ),
            "%s",
            *value
            ? "Enabled"
            : "Disabled"
        );

        ImGui::SetCursorPos(
            cursor
        );
    }

    ImGui::PopID();

    return clicked;
}

#pragma mark - Feature Card

static void ASASECFeatureCard(const char *id,
                              const char *title,
                              const char *description,
                              bool *value)
{
    if (!id ||
        !title ||
        !description ||
        !value)
    {
        return;
    }

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return;

    float width =
        ImGui::GetContentRegionAvail().x;

    if (!isfinite(width) ||
        width < 260.0f)
    {
        width = 260.0f;
    }

    const float cardHeight = 68.0f;

    ImGui::PushID(id);

    ImVec2 start =
        ImGui::GetCursorScreenPos();

    bool clicked =
        ImGui::InvisibleButton(
            "##feature",
            ImVec2(
                width,
                cardHeight
            )
        );

    ImVec2 end =
        ImGui::GetItemRectMax();

    bool hovered =
        ImGui::IsItemHovered();

    if (clicked)
        *value =
            !(*value);

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    if (draw)
    {
        ImU32 background =
            hovered
            ? ASASECColor(
                0.075f,
                0.105f,
                0.155f,
                0.98f
            )
            : ASASECColor(
                0.045f,
                0.062f,
                0.092f,
                0.98f
            );

        ImU32 border =
            hovered
            ? ASASECColor(
                0.18f,
                0.30f,
                0.46f,
                0.90f
            )
            : ASASECColor(
                0.12f,
                0.17f,
                0.25f,
                0.78f
            );

        draw->AddRectFilled(
            start,
            end,
            background,
            12.0f
        );

        draw->AddRect(
            ImVec2(
                start.x + 0.5f,
                start.y + 0.5f
            ),
            ImVec2(
                end.x - 0.5f,
                end.y - 0.5f
            ),
            border,
            12.0f,
            0,
            1.0f
        );

        draw->AddCircleFilled(
            ImVec2(
                start.x + 18.0f,
                start.y + 20.0f
            ),
            4.0f,
            *value
            ? ASASECColor(
                0.30f,
                0.68f,
                1.0f,
                1.0f
            )
            : ASASECColor(
                0.25f,
                0.30f,
                0.38f,
                1.0f
            )
        );

        float switchWidth = 46.0f;
        float switchHeight = 24.0f;

        float sx =
            end.x -
            switchWidth -
            14.0f;

        float sy =
            start.y +
            (cardHeight -
             switchHeight) *
            0.5f;

        ImVec2 sMin =
            ImVec2(
                sx,
                sy
            );

        ImVec2 sMax =
            ImVec2(
                sx + switchWidth,
                sy + switchHeight
            );

        draw->AddRectFilled(
            sMin,
            sMax,
            *value
            ? ASASECColor(
                0.16f,
                0.48f,
                0.86f,
                1.0f
            )
            : ASASECColor(
                0.12f,
                0.16f,
                0.23f,
                1.0f
            ),
            switchHeight * 0.5f
        );

        float knobX =
            *value
            ? sMax.x - 12.0f
            : sMin.x + 12.0f;

        draw->AddCircleFilled(
            ImVec2(
                knobX,
                sy +
                switchHeight * 0.5f
            ),
            8.0f,
            ASASECColor(
                0.94f,
                0.97f,
                1.0f,
                1.0f
            )
        );

        ImVec2 afterButton =
            ImGui::GetCursorPos();

        ImGui::SetCursorPos(
            ImVec2(
                afterButton.x + 31.0f,
                afterButton.y -
                cardHeight +
                9.0f
            )
        );

        ImGui::TextColored(
            ImVec4(
                0.92f,
                0.95f,
                1.0f,
                1.0f
            ),
            "%s",
            title
        );

        ImGui::SetCursorPos(
            ImVec2(
                afterButton.x + 31.0f,
                afterButton.y -
                cardHeight +
                31.0f
            )
        );

        ImGui::TextColored(
            ImVec4(
                0.38f,
                0.44f,
                0.53f,
                1.0f
            ),
            "%s",
            description
        );

        ImGui::SetCursorPos(
            ImVec2(
                afterButton.x,
                afterButton.y + 8.0f
            )
        );
    }

    ImGui::PopID();
}

#pragma mark - Style

static void ASASECApplyStyle(void)
{
    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return;

    ImGuiStyle &style =
        ImGui::GetStyle();

    style.WindowPadding =
        ImVec2(10.0f, 10.0f);

    style.FramePadding =
        ImVec2(11.0f, 8.0f);

    style.ItemSpacing =
        ImVec2(9.0f, 10.0f);

    style.ItemInnerSpacing =
        ImVec2(7.0f, 6.0f);

    style.ScrollbarSize =
        1.0f;

    style.GrabMinSize =
        15.0f;

    style.WindowRounding =
        22.0f;

    style.ChildRounding =
        14.0f;

    style.FrameRounding =
        10.0f;

    style.PopupRounding =
        12.0f;

    style.ScrollbarRounding =
        8.0f;

    style.GrabRounding =
        8.0f;

    style.TabRounding =
        10.0f;

    style.WindowBorderSize =
        0.0f;

    style.ChildBorderSize =
        1.0f;

    style.FrameBorderSize =
        0.0f;

    style.IndentSpacing =
        20.0f;

    ImVec4 *c =
        style.Colors;

    c[ImGuiCol_Text] =
        ImVec4(
            0.93f,
            0.96f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_TextDisabled] =
        ImVec4(
            0.40f,
            0.45f,
            0.54f,
            1.0f
        );

    c[ImGuiCol_WindowBg] =
        ImVec4(
            0.018f,
            0.024f,
            0.038f,
            0.985f
        );

    c[ImGuiCol_ChildBg] =
        ImVec4(
            0.040f,
            0.052f,
            0.074f,
            0.98f
        );

    c[ImGuiCol_Border] =
        ImVec4(
            0.13f,
            0.17f,
            0.24f,
            0.75f
        );

    c[ImGuiCol_FrameBg] =
        ImVec4(
            0.060f,
            0.076f,
            0.108f,
            1.0f
        );

    c[ImGuiCol_FrameBgHovered] =
        ImVec4(
            0.095f,
            0.125f,
            0.18f,
            1.0f
        );

    c[ImGuiCol_FrameBgActive] =
        ImVec4(
            0.12f,
            0.18f,
            0.27f,
            1.0f
        );

    c[ImGuiCol_Button] =
        ImVec4(
            0.060f,
            0.080f,
            0.12f,
            1.0f
        );

    c[ImGuiCol_ButtonHovered] =
        ImVec4(
            0.105f,
            0.15f,
            0.23f,
            1.0f
        );

    c[ImGuiCol_ButtonActive] =
        ImVec4(
            0.14f,
            0.24f,
            0.39f,
            1.0f
        );

    c[ImGuiCol_CheckMark] =
        ImVec4(
            0.30f,
            0.68f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_SliderGrab] =
        ImVec4(
            0.22f,
            0.56f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_SliderGrabActive] =
        ImVec4(
            0.38f,
            0.70f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_Header] =
        ImVec4(
            0.10f,
            0.17f,
            0.27f,
            1.0f
        );

    c[ImGuiCol_HeaderHovered] =
        ImVec4(
            0.14f,
            0.23f,
            0.36f,
            1.0f
        );

    c[ImGuiCol_HeaderActive] =
        ImVec4(
            0.17f,
            0.30f,
            0.47f,
            1.0f
        );

    c[ImGuiCol_Separator] =
        ImVec4(
            0.13f,
            0.17f,
            0.23f,
            0.80f
        );
}

#pragma mark - Content

static void ASASECSectionHeader(const char *title,
                                const char *subtitle,
                                ImU32 accent)
{
    if (!title)
        return;

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return;

    ImGui::PushStyleVar(
        ImGuiStyleVar_ItemSpacing,
        ImVec2(5.0f, 4.0f)
    );

    ImGui::TextColored(
        ImGui::ColorConvertU32ToFloat4(accent),
        "%s",
        title
    );

    if (subtitle)
    {
        ImGui::SameLine(
            0.0f,
            7.0f
        );

        ImGui::TextColored(
            ImVec4(
                0.34f,
                0.40f,
                0.49f,
                1.0f
            ),
            "%s",
            subtitle
        );
    }

    ImGui::PopStyleVar();
}

static void ASASECPageDescription(const char *text)
{
    if (!text)
        return;

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return;

    ImGui::TextColored(
        ImVec4(
            0.42f,
            0.47f,
            0.56f,
            1.0f
        ),
        "%s",
        text
    );
}

#pragma mark - ImGui View

@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gInitialized ||
        !gMenuVisible)
    {
        return NO;
    }

    if (!isfinite(point.x) ||
        !isfinite(point.y))
    {
        return NO;
    }

    float height =
        gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    return
        point.x >= gMenuPosition.x &&
        point.x <=
            gMenuPosition.x +
            gMenuSize.x &&
        point.y >= gMenuPosition.y &&
        point.y <=
            gMenuPosition.y +
            height;
}

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{
    if (!gInitialized ||
        !gMenuVisible ||
        gStopping)
    {
        return nil;
    }

    if ([self pointInsideMenu:point])
        return self;

    return nil;
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)updateMousePositionFromTouches:(NSSet<UITouch *> *)touches
{
    if (!gInitialized ||
        gStopping)
    {
        return;
    }

    if (!touches ||
        touches.count == 0)
    {
        return;
    }

    ImGuiContext *ctx =
        gASASECImGuiContext;

    if (!ctx)
        return;

    if (ImGui::GetCurrentContext() != ctx)
        ImGui::SetCurrentContext(ctx);

    ImGuiIO &io =
        ImGui::GetIO();

    UITouch *touch =
        touches.anyObject;

    if (!touch)
        return;

    if (!self.window)
        return;

    CGPoint point =
        [touch locationInView:self];

    if (!isfinite(point.x) ||
        !isfinite(point.y))
    {
        return;
    }

    io.MousePos =
        ImVec2(
            (float)point.x,
            (float)point.y
        );
}

- (void)updateMouseButtonState
{
    if (!gInitialized ||
        gStopping)
    {
        return;
    }

    ImGuiContext *ctx =
        gASASECImGuiContext;

    if (!ctx)
        return;

    if (ImGui::GetCurrentContext() != ctx)
        ImGui::SetCurrentContext(ctx);

    ImGuiIO &io =
        ImGui::GetIO();

    io.MouseDown[0] =
        (gActiveTouchCount > 0);
}

#pragma mark Touches

- (void)touchesBegan:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized ||
        gStopping)
    {
        return;
    }

    NSUInteger count =
        touches.count;

    if (count >
        NSUIntegerMax -
        gActiveTouchCount)
    {
        gActiveTouchCount =
            NSUIntegerMax;
    }
    else
    {
        gActiveTouchCount +=
            count;
    }

    [self updateMousePositionFromTouches:touches];
    [self updateMouseButtonState];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized ||
        gStopping)
    {
        return;
    }

    [self updateMousePositionFromTouches:touches];
    [self updateMouseButtonState];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized &&
        !gStopping)
    {
        return;
    }

    NSUInteger count =
        touches.count;

    if (count >= gActiveTouchCount)
        gActiveTouchCount = 0;
    else
        gActiveTouchCount -= count;

    if (!gStopping)
    {
        [self updateMousePositionFromTouches:touches];
        [self updateMouseButtonState];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    if (!gInitialized &&
        !gStopping)
    {
        return;
    }

    NSUInteger count =
        touches.count;

    if (count >= gActiveTouchCount)
        gActiveTouchCount = 0;
    else
        gActiveTouchCount -= count;

    if (!gStopping)
    {
        [self updateMousePositionFromTouches:touches];
        [self updateMouseButtonState];
    }
}

@end

#pragma mark - Renderer

@implementation ASASECImGuiRenderer

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    if (!view)
        return;

    if (!gInitialized ||
        gStopping ||
        !gMetalInitialized)
    {
        return;
    }

    ImGuiContext *ctx =
        gASASECImGuiContext;

    if (!ctx)
        return;

    if (ImGui::GetCurrentContext() != ctx)
        ImGui::SetCurrentContext(ctx);

    ImGuiIO &io =
        ImGui::GetIO();

    CGSize bounds =
        view.bounds.size;

    if (!isfinite(bounds.width) ||
        !isfinite(bounds.height) ||
        bounds.width <= 0.0 ||
        bounds.height <= 0.0)
    {
        return;
    }

    io.DisplaySize =
        ImVec2(
            (float)bounds.width,
            (float)bounds.height
        );

    CGFloat scale =
        view.contentScaleFactor;

    if (!isfinite(scale) ||
        scale <= 0.0)
    {
        scale = 1.0;
    }

    io.DisplayFramebufferScale =
        ImVec2(
            (float)scale,
            (float)scale
        );

    UIWindow *window =
        view.window;

    if (window)
    {
        ASASECClampMenuToScreen(
            window
        );
    }
}

- (void)drawInMTKView:(MTKView *)view
{
    /*
     * =========================================================
     * HARD LIFECYCLE GUARD
     * =========================================================
     */

    if (!view)
        return;

    if (!gInitialized ||
        gStopping ||
        !gMetalInitialized)
    {
        return;
    }

    if (!gASASECBackendOwned)
        return;

    if (!gMetalDevice ||
        !gCommandQueue)
    {
        return;
    }

    /*
     * Aynı renderer'ın üst üste draw callback'i almaması.
     */
    if (gRenderingFrame)
        return;

    gRenderingFrame = YES;

    /*
     * Bu fonksiyondan çıkarken mutlaka false yap.
     */
#define ASASEC_DRAW_RETURN() \
    do { \
        gRenderingFrame = NO; \
        return; \
    } while (0)

    /*
     * =========================================================
     * CONTEXT
     * =========================================================
     */

    ImGuiContext *ctx =
        gASASECImGuiContext;

    if (!ctx)
        ASASEC_DRAW_RETURN();

    /*
     * Context başka bir callback tarafından değiştirilmişse
     * ASASEC context'ini geri al.
     */
    if (ImGui::GetCurrentContext() != ctx)
        ImGui::SetCurrentContext(ctx);

    if (ImGui::GetCurrentContext() != ctx)
        ASASEC_DRAW_RETURN();

    ImGuiIO &io =
        ImGui::GetIO();

    if (io.BackendRendererUserData == NULL)
        ASASEC_DRAW_RETURN();

    /*
     * =========================================================
     * VIEW VALIDATION
     * =========================================================
     */

    CGSize bounds =
        view.bounds.size;

    CGSize drawableSize =
        view.drawableSize;

    if (!isfinite(bounds.width) ||
        !isfinite(bounds.height) ||
        !isfinite(drawableSize.width) ||
        !isfinite(drawableSize.height))
    {
        ASASEC_DRAW_RETURN();
    }

    if (bounds.width <= 0.0 ||
        bounds.height <= 0.0 ||
        drawableSize.width <= 0.0 ||
        drawableSize.height <= 0.0)
    {
        ASASEC_DRAW_RETURN();
    }

    /*
     * =========================================================
     * RENDER PASS
     * =========================================================
     *
     * Her frame için tek render pass.
     */
    MTLRenderPassDescriptor *renderPass =
        view.currentRenderPassDescriptor;

    if (!renderPass)
        ASASEC_DRAW_RETURN();

    /*
     * =========================================================
     * DRAWABLE
     * =========================================================
     *
     * Render pass alındıktan sonra aynı frame'in drawable'ı.
     */
    id<CAMetalDrawable> drawable =
        view.currentDrawable;

    if (!drawable)
        ASASEC_DRAW_RETURN();

    /*
     * =========================================================
     * COMMAND BUFFER
     * =========================================================
     */

    id<MTLCommandQueue> queue =
        gCommandQueue;

    if (!queue)
        ASASEC_DRAW_RETURN();

    id<MTLCommandBuffer> commandBuffer =
        [queue commandBuffer];

    if (!commandBuffer)
        ASASEC_DRAW_RETURN();

    /*
     * Stop işlemi frame'in ortasında başlamışsa bu command
     * buffer'ı güvenli şekilde kapat.
     */
    if (!gInitialized ||
        gStopping ||
        !gMetalInitialized ||
        !gASASECBackendOwned ||
        gASASECImGuiContext != ctx ||
        ImGui::GetCurrentContext() != ctx)
    {
        [commandBuffer commit];
        ASASEC_DRAW_RETURN();
    }

    if (ImGui::GetIO().BackendRendererUserData == NULL)
    {
        [commandBuffer commit];
        ASASEC_DRAW_RETURN();
    }

    /*
     * =========================================================
     * DISPLAY
     * =========================================================
     */

    io.DisplaySize =
        ImVec2(
            (float)bounds.width,
            (float)bounds.height
        );

    CGFloat scale =
        view.contentScaleFactor;

    if (!isfinite(scale) ||
        scale <= 0.0)
    {
        scale = 1.0;
    }

    io.DisplayFramebufferScale =
        ImVec2(
            (float)scale,
            (float)scale
        );

    /*
     * =========================================================
     * DELTA TIME
     * =========================================================
     */

    float fps =
        (float)view.preferredFramesPerSecond;

    if (!isfinite(fps) ||
        fps < 1.0f)
    {
        fps = 60.0f;
    }

    float dt =
        1.0f / fps;

    if (!isfinite(dt) ||
        dt <= 0.0f ||
        dt > 0.1f)
    {
        dt =
            1.0f / 60.0f;
    }

    io.DeltaTime =
        dt;

    /*
     * =========================================================
     * METAL NEW FRAME
     * =========================================================
     */

    ImGui_ImplMetal_NewFrame(
        renderPass
    );

    /*
     * Backend/context hâlâ geçerli mi?
     */
    if (!gInitialized ||
        gStopping ||
        !gMetalInitialized ||
        !gASASECBackendOwned ||
        gASASECImGuiContext != ctx ||
        ImGui::GetCurrentContext() != ctx ||
        ImGui::GetIO().BackendRendererUserData == NULL)
    {
        [commandBuffer commit];
        ASASEC_DRAW_RETURN();
    }

    /*
     * =========================================================
     * IMGUI NEW FRAME
     * =========================================================
     */

    ImGui::NewFrame();

    /*
     * =========================================================
     * PAGE ANIMATION
     * =========================================================
     */

    if (gSelectedPage !=
        gPreviousPage)
    {
        gPreviousPage =
            gSelectedPage;

        gPageAnimation =
            0.0f;

        gPageSlide =
            18.0f;
    }

    gPageAnimation =
        ASASECEase(
            gPageAnimation,
            1.0f,
            14.0f,
            dt
        );

    gPageSlide =
        ASASECEase(
            gPageSlide,
            0.0f,
            14.0f,
            dt
        );

    /*
     * =========================================================
     * SCROLL INERTIA
     * =========================================================
     */

    if (!gContentDragging &&
        fabsf(gContentScrollVelocity) > 0.01f)
    {
        gPendingContentScrollY +=
            gContentScrollVelocity;

        gContentScrollVelocity *=
            expf(-7.0f * dt);

        if (!isfinite(gPendingContentScrollY))
            gPendingContentScrollY = 0.0f;

        if (!isfinite(gContentScrollVelocity) ||
            fabsf(gContentScrollVelocity) < 0.01f)
        {
            gContentScrollVelocity =
                0.0f;
        }
    }

    /*
     * =========================================================
     * MAIN WINDOW
     * =========================================================
     */

    if (gMenuVisible)
    {
        const float sidebarWidth =
            145.0f;

        ImVec2 actualSize =
            ImVec2(
                gMenuSize.x,
                gMenuCollapsed
                ? kHeaderHeight
                : gMenuSize.y
            );

        if (!isfinite(actualSize.x) ||
            !isfinite(actualSize.y))
        {
            actualSize =
                ImVec2(
                    560.0f,
                    390.0f
                );
        }

        ImGui::SetNextWindowPos(
            gMenuPosition,
            ImGuiCond_Always
        );

        ImGui::SetNextWindowSize(
            actualSize,
            ImGuiCond_Always
        );

        ImGuiWindowFlags flags =
            ImGuiWindowFlags_NoTitleBar |
            ImGuiWindowFlags_NoResize |
            ImGuiWindowFlags_NoCollapse |
            ImGuiWindowFlags_NoSavedSettings |
            ImGuiWindowFlags_NoScrollbar;

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowPadding,
            ImVec2(0.0f, 0.0f)
        );

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowRounding,
            22.0f
        );

        ImGui::PushStyleColor(
            ImGuiCol_WindowBg,
            ImVec4(
                0.018f,
                0.024f,
                0.038f,
                0.985f
            )
        );

        bool windowOpen =
            ImGui::Begin(
                "##ASASEC_WINDOW",
                NULL,
                flags
            );

        if (windowOpen)
        {
            ImVec2 windowPos =
                ImGui::GetWindowPos();

            ImVec2 windowSize =
                ImGui::GetWindowSize();

            ImVec2 windowEnd =
                ImVec2(
                    windowPos.x +
                    windowSize.x,
                    windowPos.y +
                    windowSize.y
                );

            ImDrawList *draw =
                ImGui::GetWindowDrawList();

            /*
             * =================================================
             * WINDOW BACKGROUND
             * =================================================
             */

            if (draw)
            {
                draw->AddRectFilled(
                    windowPos,
                    windowEnd,
                    IM_COL32(
                        6,
                        9,
                        16,
                        252
                    ),
                    22.0f
                );

                draw->AddRect(
                    ImVec2(
                        windowPos.x + 0.5f,
                        windowPos.y + 0.5f
                    ),
                    ImVec2(
                        windowEnd.x - 0.5f,
                        windowEnd.y - 0.5f
                    ),
                    IM_COL32(
                        48,
                        62,
                        84,
                        185
                    ),
                    22.0f,
                    0,
                    1.0f
                );

                draw->AddRectFilled(
                    ImVec2(
                        windowPos.x + 1.0f,
                        windowPos.y + 1.0f
                    ),
                    ImVec2(
                        windowEnd.x - 1.0f,
                        windowPos.y +
                        kHeaderHeight
                    ),
                    IM_COL32(
                        10,
                        15,
                        25,
                        255
                    ),
                    21.0f,
                    ImDrawFlags_RoundCornersTop
                );

                draw->AddLine(
                    ImVec2(
                        windowPos.x + 16.0f,
                        windowPos.y +
                        kHeaderHeight
                    ),
                    ImVec2(
                        windowEnd.x - 16.0f,
                        windowPos.y +
                        kHeaderHeight
                    ),
                    IM_COL32(
                        38,
                        48,
                        66,
                        220
                    ),
                    1.0f
                );
            }

            /*
             * =================================================
             * HEADER
             * =================================================
             */

            ImGui::SetCursorPos(
                ImVec2(
                    18.0f,
                    11.0f
                )
            );

            ImGui::TextColored(
                ImVec4(
                    0.30f,
                    0.68f,
                    1.0f,
                    1.0f
                ),
                "●"
            );

            ImGui::SameLine(
                0.0f,
                7.0f
            );

            ImGui::TextColored(
                ImVec4(
                    0.94f,
                    0.97f,
                    1.0f,
                    1.0f
                ),
                "ASASEC"
            );

            ImGui::SameLine(
                0.0f,
                5.0f
            );

            ImGui::TextColored(
                ImVec4(
                    0.43f,
                    0.49f,
                    0.59f,
                    1.0f
                ),
                "UI"
            );

            if (!gMenuCollapsed)
            {
                float titleX =
                    windowSize.x -
                    230.0f;

                if (titleX > 170.0f)
                {
                    ImGui::SetCursorPos(
                        ImVec2(
                            titleX,
                            19.0f
                        )
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.35f,
                            0.42f,
                            0.52f,
                            1.0f
                        ),
                        "CONTROL PANEL"
                    );
                }
            }

            /*
             * =================================================
             * COLLAPSE BUTTON
             * =================================================
             */

            float collapseX =
                windowSize.x -
                96.0f;

            if (collapseX < 150.0f)
                collapseX = 150.0f;

            ImGui::SetCursorPos(
                ImVec2(
                    collapseX,
                    9.0f
                )
            );

            ImGui::PushID(
                "ASASEC_COLLAPSE"
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                10.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.06f,
                    0.09f,
                    0.14f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.11f,
                    0.18f,
                    0.29f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.17f,
                    0.28f,
                    0.43f,
                    1.0f
                )
            );

            ImGui::Button(
                "##collapse",
                ImVec2(
                    38.0f,
                    34.0f
                )
            );

            bool collapsePressed =
                ImGui::IsItemClicked();

            bool collapseHovered =
                ImGui::IsItemHovered();

            ImVec2 collapseMin =
                ImGui::GetItemRectMin();

            ImVec2 collapseMax =
                ImGui::GetItemRectMax();

            ImDrawList *headerDraw =
                ImGui::GetWindowDrawList();

            if (headerDraw)
            {
                float cx =
                    (collapseMin.x +
                     collapseMax.x) *
                    0.5f;

                float cy =
                    (collapseMin.y +
                     collapseMax.y) *
                    0.5f;

                float aw = 7.0f;
                float ah = 5.0f;

                ImU32 arrowColor =
                    collapseHovered
                    ? ASASECColor(
                        0.42f,
                        0.74f,
                        1.0f,
                        1.0f
                    )
                    : ASASECColor(
                        0.78f,
                        0.84f,
                        0.93f,
                        0.95f
                    );

                if (gMenuCollapsed)
                {
                    headerDraw->AddLine(
                        ImVec2(
                            cx - aw,
                            cy - ah
                        ),
                        ImVec2(
                            cx,
                            cy + ah
                        ),
                        arrowColor,
                        2.2f
                    );

                    headerDraw->AddLine(
                        ImVec2(
                            cx,
                            cy + ah
                        ),
                        ImVec2(
                            cx + aw,
                            cy - ah
                        ),
                        arrowColor,
                        2.2f
                    );
                }
                else
                {
                    headerDraw->AddLine(
                        ImVec2(
                            cx - aw,
                            cy + ah
                        ),
                        ImVec2(
                            cx,
                            cy - ah
                        ),
                        arrowColor,
                        2.2f
                    );

                    headerDraw->AddLine(
                        ImVec2(
                            cx,
                            cy - ah
                        ),
                        ImVec2(
                            cx + aw,
                            cy + ah
                        ),
                        arrowColor,
                        2.2f
                    );
                }
            }

            if (collapsePressed)
            {
                gMenuCollapsed =
                    !gMenuCollapsed;

                gDraggingMenu =
                    NO;

                gResizingMenu =
                    NO;

                gContentDragging =
                    NO;

                gContentScrollVelocity =
                    0.0f;

                gPendingContentScrollY =
                    0.0f;

                UIWindow *window =
                    view.window;

                if (window)
                {
                    ASASECClampMenuToScreen(
                        window
                    );
                }
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
            ImGui::PopID();

            /*
             * =================================================
             * CLOSE BUTTON
             * =================================================
             */

            float closeX =
                windowSize.x -
                50.0f;

            if (closeX < 190.0f)
                closeX = 190.0f;

            ImGui::SetCursorPos(
                ImVec2(
                    closeX,
                    9.0f
                )
            );

            ImGui::PushID(
                "ASASEC_CLOSE"
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                10.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.10f,
                    0.065f,
                    0.085f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.34f,
                    0.10f,
                    0.15f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.48f,
                    0.12f,
                    0.18f,
                    1.0f
                )
            );

            ImGui::Button(
                "##close",
                ImVec2(
                    34.0f,
                    34.0f
                )
            );

            bool closePressed =
                ImGui::IsItemClicked();

            bool closeHovered =
                ImGui::IsItemHovered();

            ImVec2 closeMin =
                ImGui::GetItemRectMin();

            ImVec2 closeMax =
                ImGui::GetItemRectMax();

            ImDrawList *closeDraw =
                ImGui::GetWindowDrawList();

            if (closeDraw)
            {
                float cx =
                    (closeMin.x +
                     closeMax.x) *
                    0.5f;

                float cy =
                    (closeMin.y +
                     closeMax.y) *
                    0.5f;

                float s = 6.0f;

                ImU32 color =
                    closeHovered
                    ? ASASECColor(
                        1.0f,
                        0.45f,
                        0.52f,
                        1.0f
                    )
                    : ASASECColor(
                        0.86f,
                        0.90f,
                        0.96f,
                        0.95f
                    );

                closeDraw->AddLine(
                    ImVec2(
                        cx - s,
                        cy - s
                    ),
                    ImVec2(
                        cx + s,
                        cy + s
                    ),
                    color,
                    2.2f
                );

                closeDraw->AddLine(
                    ImVec2(
                        cx + s,
                        cy - s
                    ),
                    ImVec2(
                        cx - s,
                        cy + s
                    ),
                    color,
                    2.2f
                );
            }

            if (closePressed)
            {
                /*
                 * Frame içinde context'i destroy etmiyoruz.
                 * Sadece görünürlüğü kapatıyoruz.
                 */
                gMenuVisible =
                    NO;

                gMenuCollapsed =
                    NO;

                gDraggingMenu =
                    NO;

                gResizingMenu =
                    NO;

                gContentDragging =
                    NO;

                gActiveTouchCount =
                    0;
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
            ImGui::PopID();

            /*
             * =================================================
             * CONTENT
             * =================================================
             */

            if (!gMenuCollapsed &&
                gMenuVisible)
            {
                if (draw)
                {
                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x,
                            windowPos.y +
                            kHeaderHeight
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowEnd.y
                        ),
                        IM_COL32(
                            9,
                            14,
                            24,
                            255
                        ),
                        0.0f
                    );

                    draw->AddLine(
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowPos.y +
                            62.0f
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowEnd.y -
                            16.0f
                        ),
                        IM_COL32(
                            34,
                            43,
                            59,
                            210
                        ),
                        1.0f
                    );
                }

                ImGui::SetCursorPos(
                    ImVec2(
                        18.0f,
                        36.0f
                    )
                );

                ImGui::TextColored(
                    ImVec4(
                        0.27f,
                        0.32f,
                        0.40f,
                        1.0f
                    ),
                    "NAVIGATION"
                );

                const char *pages[] =
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
                    bool active =
                        gSelectedPage == i;

                    float itemY =
                        72.0f +
                        i * 54.0f;

                    if (active && draw)
                    {
                        draw->AddRectFilled(
                            ImVec2(
                                windowPos.x + 9.0f,
                                windowPos.y +
                                itemY
                            ),
                            ImVec2(
                                windowPos.x +
                                sidebarWidth -
                                9.0f,
                                windowPos.y +
                                itemY +
                                43.0f
                            ),
                            IM_COL32(
                                19,
                                48,
                                84,
                                255
                            ),
                            11.0f
                        );
                    }

                    char id[64];

                    snprintf(
                        id,
                        sizeof(id),
                        "%s   %s##page_%d",
                        icons[i],
                        pages[i],
                        i
                    );

                    ImGui::SetCursorPos(
                        ImVec2(
                            10.0f,
                            itemY
                        )
                    );

                    ImGui::PushStyleVar(
                        ImGuiStyleVar_FrameRounding,
                        11.0f
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
                            0.17f,
                            0.27f,
                            0.85f
                        )
                    );

                    ImGui::PushStyleColor(
                        ImGuiCol_ButtonActive,
                        ImVec4(
                            0.13f,
                            0.24f,
                            0.39f,
                            1.0f
                        )
                    );

                    if (ImGui::Button(
                            id,
                            ImVec2(
                                sidebarWidth -
                                20.0f,
                                43.0f
                            )
                        ))
                    {
                        if (gSelectedPage != i)
                        {
                            gSelectedPage =
                                i;

                            gPageAnimation =
                                0.0f;

                            gPageSlide =
                                18.0f;

                            gPendingContentScrollY =
                                0.0f;

                            gContentScrollVelocity =
                                0.0f;
                        }
                    }

                    ImGui::PopStyleColor(3);
                    ImGui::PopStyleVar();
                }

                /*
                 * =================================================
                 * CONTENT CHILD
                 * =================================================
                 */

                ImGui::SetCursorPos(
                    ImVec2(
                        sidebarWidth + 1.0f,
                        54.0f
                    )
                );

                float contentWidth =
                    windowSize.x -
                    sidebarWidth -
                    1.0f;

                float contentHeight =
                    windowSize.y -
                    54.0f;

                if (!isfinite(contentWidth) ||
                    contentWidth < 100.0f)
                {
                    contentWidth = 100.0f;
                }

                if (!isfinite(contentHeight) ||
                    contentHeight < 100.0f)
                {
                    contentHeight = 100.0f;
                }

                ImGui::PushStyleVar(
                    ImGuiStyleVar_ChildRounding,
                    0.0f
                );

                bool contentOpen =
                    ImGui::BeginChild(
                        "##ContentRoot",
                        ImVec2(
                            contentWidth,
                            contentHeight
                        ),
                        false,
                        ImGuiWindowFlags_NoBackground |
                        ImGuiWindowFlags_NoScrollbar
                    );

                if (contentOpen)
                {
                    ImGui::SetCursorPos(
                        ImVec2(
                            17.0f,
                            10.0f
                        )
                    );

                    const char *pageTitle =
                        gSelectedPage == 0
                        ? "Combat"
                        : gSelectedPage == 1
                        ? "Visuals"
                        : "Settings";

                    ImGui::TextColored(
                        ImVec4(
                            0.94f,
                            0.97f,
                            1.0f,
                            1.0f
                        ),
                        "%s",
                        pageTitle
                    );

                    ImGui::SameLine(
                        0.0f,
                        7.0f
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.30f,
                            0.36f,
                            0.45f,
                            1.0f
                        ),
                        "/ ASASEC"
                    );

                    ImGui::SetCursorPos(
                        ImVec2(
                            17.0f,
                            62.0f
                        )
                    );

                    float fade =
                        ASASECClampFloat(
                            gPageAnimation,
                            0.0f,
                            1.0f
                        );

                    ImGui::PushStyleVar(
                        ImGuiStyleVar_Alpha,
                        fade
                    );

                    ImGui::SetCursorPosX(
                        17.0f +
                        gPageSlide
                    );

                    /*
                     * =================================================
                     * COMBAT
                     * =================================================
                     */

                    if (gSelectedPage == 0)
                    {
                        ASASECSectionHeader(
                            "COMBAT",
                            "ACTIONS",
                            ASASECColor(
                                0.30f,
                                0.68f,
                                1.0f,
                                1.0f
                            )
                        );

                        ASASECPageDescription(
                            "Configure your combat options"
                        );

                        ImGui::Dummy(
                            ImVec2(
                                0.0f,
                                10.0f
                            )
                        );

                        static bool sw1 = false;
                        static bool sw2 = false;
                        static bool sw3 = false;
                        static bool sw4 = false;

                        ASASECFeatureCard(
                            "aimbot",
                            "swicht 1",
                            "Automatic target assistance",
                            &sw1
                        );

                        ASASECFeatureCard(
                            "silent",
                            "swicht 2",
                            "Hidden targeting correction",
                            &sw2
                        );

                        ASASECFeatureCard(
                            "recoil",
                            "swicht 3",
                            "Reduce weapon recoil",
                            &sw3
                        );

                        ASASECFeatureCard(
                            "rapid",
                            "swicht 4",
                            "Increase firing response",
                            &sw4
                        );
                    }

                    /*
                     * =================================================
                     * VISUALS
                     * =================================================
                     */

                    else if (gSelectedPage == 1)
                    {
                        ASASECSectionHeader(
                            "VISUALS",
                            "ESP",
                            ASASECColor(
                                0.28f,
                                0.86f,
                                0.58f,
                                1.0f
                            )
                        );

                        ASASECPageDescription(
                            "Configure visual and player information"
                        );

                        ImGui::Dummy(
                            ImVec2(
                                0.0f,
                                10.0f
                            )
                        );

                        static bool sw1 = false;
                        static bool sw2 = false;
                        static bool sw3 = false;
                        static bool sw4 = false;

                        ASASECFeatureCard(
                            "player",
                            "swicht 1",
                            "Display nearby players",
                            &sw1
                        );

                        ASASECFeatureCard(
                            "box",
                            "swicht 2",
                            "Draw player bounding boxes",
                            &sw2
                        );

                        ASASECFeatureCard(
                            "distance",
                            "swicht 3",
                            "Show player distance",
                            &sw3
                        );

                        ASASECFeatureCard(
                            "skeleton",
                            "swicht 4",
                            "Display player skeleton",
                            &sw4
                        );
                    }

                    /*
                     * =================================================
                     * SETTINGS
                     * =================================================
                     */

                    else
                    {
                        ASASECSectionHeader(
                            "SETTINGS",
                            "SYSTEM",
                            ASASECColor(
                                1.0f,
                                0.67f,
                                0.28f,
                                1.0f
                            )
                        );

                        ASASECPageDescription(
                            "Configure ASASEC interface and system"
                        );

                        ImGui::Dummy(
                            ImVec2(
                                0.0f,
                                10.0f
                            )
                        );

                        static bool sw1 = false;
                        static bool sw2 = false;
                        static bool sw3 = false;
                        static bool sw4 = false;

                        ASASECFeatureCard(
                            "save",
                            "swicht 1",
                            "Keep your interface settings",
                            &sw1
                        );

                        ASASECFeatureCard(
                            "theme",
                            "swicht 2",
                            "Use the ASASEC dark interface",
                            &sw2
                        );

                        ASASECFeatureCard(
                            "vibration",
                            "swicht 3",
                            "Enable touch feedback",
                            &sw3
                        );

                        ASASECFeatureCard(
                            "developer",
                            "swicht 4",
                            "Enable developer options",
                            &sw4
                        );
                    }

                    /*
                     * =================================================
                     * SCROLL
                     * =================================================
                     */

                    if (fabsf(gPendingContentScrollY) > 0.001f)
                    {
                        float currentScroll =
                            ImGui::GetScrollY();

                        float maxScroll =
                            ImGui::GetScrollMaxY();

                        if (!isfinite(currentScroll))
                            currentScroll = 0.0f;

                        if (!isfinite(maxScroll) ||
                            maxScroll < 0.0f)
                        {
                            maxScroll = 0.0f;
                        }

                        float targetScroll =
                            ASASECClampFloat(
                                currentScroll +
                                gPendingContentScrollY,
                                0.0f,
                                maxScroll
                            );

                        ImGui::SetScrollY(
                            targetScroll
                        );

                        gPendingContentScrollY =
                            0.0f;
                    }

                    ImGui::PopStyleVar();
                }

                /*
                 * BeginChild false dönse bile EndChild şart.
                 */
                ImGui::EndChild();

                ImGui::PopStyleVar();
            }
        }

        /*
         * Begin sonucu ne olursa olsun End.
         */
        ImGui::End();

        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);
    }

    /*
     * =========================================================
     * RENDER
     * =========================================================
     */

    ImGui::Render();

    /*
     * =========================================================
     * POST-RENDER LIFECYCLE CHECK
     * =========================================================
     */

    if (!gInitialized ||
        gStopping ||
        !gMetalInitialized ||
        !gASASECBackendOwned ||
        gASASECImGuiContext != ctx ||
        ImGui::GetCurrentContext() != ctx)
    {
        [commandBuffer commit];
        ASASEC_DRAW_RETURN();
    }

    if (ImGui::GetIO().BackendRendererUserData == NULL)
    {
        [commandBuffer commit];
        ASASEC_DRAW_RETURN();
    }

    ImDrawData *drawData =
        ImGui::GetDrawData();

    if (!drawData)
    {
        [commandBuffer commit];
        ASASEC_DRAW_RETURN();
    }

    if (drawData->DisplaySize.x <= 0.0f ||
        drawData->DisplaySize.y <= 0.0f)
    {
        [commandBuffer commit];
        ASASEC_DRAW_RETURN();
    }

    /*
     * =========================================================
     * RENDER ENCODER
     * =========================================================
     */

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer
            renderCommandEncoderWithDescriptor:
                renderPass];

    if (!encoder)
    {
        [commandBuffer commit];
        ASASEC_DRAW_RETURN();
    }

    [encoder setViewport:(MTLViewport){
        0.0,
        0.0,
        (double)drawableSize.width,
        (double)drawableSize.height,
        0.0,
        1.0
    }];

    /*
     * Backend hâlâ tamamen geçerliyse çiz.
     */
    if (gInitialized &&
        !gStopping &&
        gMetalInitialized &&
        gASASECBackendOwned &&
        gASASECImGuiContext == ctx &&
        ImGui::GetCurrentContext() == ctx &&
        ImGui::GetIO().BackendRendererUserData != NULL)
    {
        ImGui_ImplMetal_RenderDrawData(
            drawData,
            commandBuffer,
            encoder
        );
    }

    [encoder endEncoding];

    /*
     * Aynı frame'in drawable'ı.
     */
    [commandBuffer
        presentDrawable:drawable];

    /*
     * Tek commit.
     */
    [commandBuffer commit];

    ASASEC_DRAW_RETURN();

#undef ASASEC_DRAW_RETURN
}

@end

#pragma mark - Safe Backend Cleanup

static void ASASECSafeShutdownMetalBackend(void)
{
    /*
     * Yalnızca ASASEC'in oluşturduğu context.
     */
    ImGuiContext *ctx =
        gASASECImGuiContext;

    if (!ctx)
    {
        gMetalInitialized =
            NO;

        gASASECBackendOwned =
            NO;

        return;
    }

    /*
     * Context'i current yap.
     */
    if (ImGui::GetCurrentContext() != ctx)
        ImGui::SetCurrentContext(ctx);

    /*
     * Backend gerçekten ASASEC tarafından initialize
     * edilmiş değilse Shutdown çağırma.
     */
    if (!gASASECBackendOwned ||
        !gMetalInitialized)
    {
        gMetalInitialized =
            NO;

        gASASECBackendOwned =
            NO;

        return;
    }

    ImGuiIO &io =
        ImGui::GetIO();

    /*
     * =========================================================
     * GPU SYNCHRONIZATION
     * =========================================================
     *
     * Backend resource'larını release etmeden önce command
     * queue'nun daha önce gönderilmiş işleri bitirmesini
     * bekliyoruz.
     */
    id<MTLCommandQueue> queue =
        gCommandQueue;

    if (queue)
    {
        id<MTLCommandBuffer> syncBuffer =
            [queue commandBuffer];

        if (syncBuffer)
        {
            [syncBuffer commit];
            [syncBuffer waitUntilCompleted];
        }
    }

    /*
     * Context ve backend hâlâ bizim context'imiz mi?
     */
    if (ImGui::GetCurrentContext() == ctx &&
        gASASECBackendOwned &&
        io.BackendRendererUserData != NULL)
    {
        ImGui_ImplMetal_Shutdown();
    }

    gMetalInitialized =
        NO;

    gASASECBackendOwned =
        NO;
}

static void ASASECSafeDestroyOwnImGuiContext(void)
{
    ImGuiContext *ctx =
        gASASECImGuiContext;

    if (!ctx)
        return;

    /*
     * Önce bizim backend'i kapat.
     */
    ASASECSafeShutdownMetalBackend();

    /*
     * Sadece kendi context'imizi destroy ediyoruz.
     */
    if (ImGui::GetCurrentContext() != ctx)
        ImGui::SetCurrentContext(ctx);

    if (ImGui::GetCurrentContext() == ctx)
    {
        ImGui::DestroyContext(ctx);
    }

    /*
     * Artık dangling pointer bırakma.
     */
    gASASECImGuiContext =
        NULL;

    /*
     * Daha önceki context'i geri yükle.
     *
     * Aynı pointer zaten yok edilmiş bizim context ise
     * NULL bırak.
     */
    if (gPreviousImGuiContext &&
        gPreviousImGuiContext != ctx)
    {
        ImGui::SetCurrentContext(
            gPreviousImGuiContext
        );
    }
    else
    {
        ImGui::SetCurrentContext(
            NULL
        );
    }

    gPreviousImGuiContext =
        NULL;
}

#pragma mark - Start

void ASASECImGuiStart(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            /*
             * =================================================
             * START GUARD
             * =================================================
             */

            if (gInitialized ||
                gStarting)
            {
                return;
            }

            if (gStopping)
            {
                return;
            }

            gStarting =
                YES;

            UIWindow *window =
                ASASECFindActiveWindow();

            if (!window)
            {
                gStarting =
                    NO;

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.50 *
                            NSEC_PER_SEC
                        )
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        if (!gInitialized &&
                            !gStarting &&
                            !gStopping)
                        {
                            ASASECImGuiStart();
                        }
                    }
                );

                return;
            }

            CGSize windowSize =
                window.bounds.size;

            if (!isfinite(windowSize.width) ||
                !isfinite(windowSize.height) ||
                windowSize.width <= 0.0 ||
                windowSize.height <= 0.0)
            {
                gStarting =
                    NO;

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.50 *
                            NSEC_PER_SEC
                        )
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        if (!gInitialized &&
                            !gStarting &&
                            !gStopping)
                        {
                            ASASECImGuiStart();
                        }
                    }
                );

                return;
            }

            /*
             * =================================================
             * METAL DEVICE
             * =================================================
             */

            id<MTLDevice> device =
                MTLCreateSystemDefaultDevice();

            if (!device)
            {
                gStarting =
                    NO;

                return;
            }

            id<MTLCommandQueue> queue =
                [device newCommandQueue];

            if (!queue)
            {
                gStarting =
                    NO;

                return;
            }

            /*
             * =================================================
             * REMOVE PREVIOUS ASASEC VIEW
             * =================================================
             */

            if (gImGuiView)
            {
                ASASECImGuiView *oldView =
                    gImGuiView;

                /*
                 * Callback'i kes.
                 */
                oldView.paused =
                    YES;

                oldView.delegate =
                    nil;

                oldView.userInteractionEnabled =
                    NO;

                oldView.multipleTouchEnabled =
                    NO;

                [oldView removeFromSuperview];

                gImGuiView =
                    nil;
            }

            gRenderer =
                nil;

            /*
             * =================================================
             * ESKİ ASASEC CONTEXT VARSA TEMİZLE
             * =================================================
             */

            if (gASASECImGuiContext)
            {
                gInitialized =
                    NO;

                gStopping =
                    YES;

                ASASECSafeDestroyOwnImGuiContext();

                gStopping =
                    NO;
            }

            gMetalInitialized =
                NO;

            gASASECBackendOwned =
                NO;

            gMetalDevice =
                device;

            gCommandQueue =
                queue;

            /*
             * =================================================
             * CREATE OWN CONTEXT
             * =================================================
             */

            IMGUI_CHECKVERSION();

            /*
             * Başka bir context varsa onu sakla.
             * ASASEC yalnızca kendi context'ini kullanacak.
             */
            gPreviousImGuiContext =
                ImGui::GetCurrentContext();

            ImGuiContext *ctx =
                ImGui::CreateContext();

            if (!ctx)
            {
                gPreviousImGuiContext =
                    NULL;

                gMetalDevice =
                    nil;

                gCommandQueue =
                    nil;

                gStarting =
                    NO;

                return;
            }

            gASASECImGuiContext =
                ctx;

            ImGui::SetCurrentContext(
                ctx
            );

            if (ImGui::GetCurrentContext() != ctx)
            {
                gASASECImGuiContext =
                    NULL;

                gPreviousImGuiContext =
                    NULL;

                gMetalDevice =
                    nil;

                gCommandQueue =
                    nil;

                gStarting =
                    NO;

                return;
            }

            ImGuiIO &io =
                ImGui::GetIO();

            io.IniFilename =
                NULL;

            io.LogFilename =
                NULL;

            io.FontGlobalScale =
                1.0f;

            io.MousePos =
                ImVec2(
                    -FLT_MAX,
                    -FLT_MAX
                );

            io.MouseDown[0] =
                false;

            io.MouseDown[1] =
                false;

            io.MouseDown[2] =
                false;

            io.DisplaySize =
                ImVec2(
                    (float)windowSize.width,
                    (float)windowSize.height
                );

            CGFloat scale =
                window.screen.scale;

            if (!isfinite(scale) ||
                scale <= 0.0)
            {
                scale = 1.0;
            }

            io.DisplayFramebufferScale =
                ImVec2(
                    (float)scale,
                    (float)scale
                );

            io.BackendPlatformName =
                "ASASEC-iOS-Touch";

            io.BackendRendererName =
                "ASASEC-Metal";

            ASASECApplyStyle();

            /*
             * =================================================
             * RESET UI STATE
             * =================================================
             */

            gMenuVisible =
                YES;

            gMenuCollapsed =
                NO;

            gSelectedPage =
                0;

            gPreviousPage =
                0;

            gPageAnimation =
                1.0f;

            gPageSlide =
                0.0f;

            gDraggingMenu =
                NO;

            gResizingMenu =
                NO;

            gContentDragging =
                NO;

            gContentHasMoved =
                NO;

            gContentTouchCandidate =
                NO;

            gPendingContentScrollY =
                0.0f;

            gContentScrollVelocity =
                0.0f;

            gActiveTouchCount =
                0;

            gRenderingFrame =
                NO;

            gSwitchAnimationCount =
                0;

            /*
             * =================================================
             * MTKVIEW
             * =================================================
             */

            ASASECImGuiView *view =
                [[ASASECImGuiView alloc]
                    initWithFrame:window.bounds
                    device:device];

            if (!view)
            {
                gStopping =
                    YES;

                ASASECSafeDestroyOwnImGuiContext();

                gStopping =
                    NO;

                gMetalDevice =
                    nil;

                gCommandQueue =
                    nil;

                gStarting =
                    NO;

                return;
            }

            view.device =
                device;

            view.frame =
                window.bounds;

            view.autoresizingMask =
                UIViewAutoresizingFlexibleWidth |
                UIViewAutoresizingFlexibleHeight;

            view.backgroundColor =
                UIColor.clearColor;

            view.opaque =
                NO;

            view.clearColor =
                MTLClearColorMake(
                    0.0,
                    0.0,
                    0.0,
                    0.0
                );

            view.colorPixelFormat =
                MTLPixelFormatBGRA8Unorm;

            view.depthStencilPixelFormat =
                MTLPixelFormatInvalid;

            view.preferredFramesPerSecond =
                60;

            /*
             * İlk callback'i önlemek için başlangıçta pause.
             */
            view.paused =
                YES;

            view.enableSetNeedsDisplay =
                NO;

            view.userInteractionEnabled =
                YES;

            view.multipleTouchEnabled =
                YES;

            /*
             * Drawable otomatik resize.
             */
            view.autoResizeDrawable =
                YES;

            /*
             * =================================================
             * RENDERER
             * =================================================
             */

            ASASECImGuiRenderer *renderer =
                [[ASASECImGuiRenderer alloc]
                    init];

            if (!renderer)
            {
                view.delegate =
                    nil;

                view.paused =
                    YES;

                gStopping =
                    YES;

                ASASECSafeDestroyOwnImGuiContext();

                gStopping =
                    NO;

                gMetalDevice =
                    nil;

                gCommandQueue =
                    nil;

                gStarting =
                    NO;

                return;
            }

            /*
             * =================================================
             * METAL BACKEND
             * =================================================
             */

            /*
             * ASASEC context'i current olmalı.
             */
            if (ImGui::GetCurrentContext() != ctx)
                ImGui::SetCurrentContext(ctx);

            if (ImGui::GetCurrentContext() != ctx)
            {
                view.delegate =
                    nil;

                gStopping =
                    YES;

                ASASECSafeDestroyOwnImGuiContext();

                gStopping =
                    NO;

                gMetalDevice =
                    nil;

                gCommandQueue =
                    nil;

                gStarting =
                    NO;

                return;
            }

            BOOL backendOK =
                ImGui_ImplMetal_Init(
                    device
                );

            if (!backendOK)
            {
                view.delegate =
                    nil;

                view.paused =
                    YES;

                gStopping =
                    YES;

                ASASECSafeDestroyOwnImGuiContext();

                gStopping =
                    NO;

                gMetalDevice =
                    nil;

                gCommandQueue =
                    nil;

                gStarting =
                    NO;

                return;
            }

            gMetalInitialized =
                YES;

            gASASECBackendOwned =
                YES;

            /*
             * =================================================
             * ATTACH
             * =================================================
             */

            gRenderer =
                renderer;

            gImGuiView =
                view;

            /*
             * Delegate'i attach et.
             */
            view.delegate =
                renderer;

            /*
             * Callback hâlâ pause durumda.
             */
            view.paused =
                YES;

            /*
             * View hierarchy.
             */
            [window addSubview:view];

            /*
             * ASASEC overlay en üstte.
             */
            [window bringSubviewToFront:view];

            view.frame =
                window.bounds;

            [view setNeedsLayout];

            [view layoutIfNeeded];

            ASASECClampMenuToScreen(
                window
            );

            /*
             * =================================================
             * FINAL VALIDATION
             * =================================================
             */

            if (!gImGuiView ||
                gImGuiView != view ||
                !gRenderer ||
                !gMetalDevice ||
                !gCommandQueue ||
                !gASASECImGuiContext ||
                !gMetalInitialized ||
                !gASASECBackendOwned)
            {
                view.paused =
                    YES;

                view.delegate =
                    nil;

                view.userInteractionEnabled =
                    NO;

                [view removeFromSuperview];

                gImGuiView =
                    nil;

                gRenderer =
                    nil;

                gStopping =
                    YES;

                ASASECSafeDestroyOwnImGuiContext();

                gStopping =
                    NO;

                gMetalDevice =
                    nil;

                gCommandQueue =
                    nil;

                gStarting =
                    NO;

                return;
            }

            /*
             * =================================================
             * LIVE
             * =================================================
             *
             * Artık callback başlayabilir.
             */
            gInitialized =
                YES;

            gStopping =
                NO;

            view.paused =
                NO;

            gStarting =
                NO;
        }
    );
}

#pragma mark - Stop

void ASASECImGuiStop(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            /*
             * =================================================
             * STOP GUARD
             * =================================================
             */

            if (gStopping)
                return;

            gStopping =
                YES;

            /*
             * =================================================
             * 1. CALLBACK'LERİ DURDUR
             * =================================================
             */

            gInitialized =
                NO;

            gActiveTouchCount =
                0;

            /*
             * =================================================
             * 2. VIEW REFERANSINI AYIR
             * =================================================
             */

            ASASECImGuiView *view =
                gImGuiView;

            gImGuiView =
                nil;

            if (view)
            {
                /*
                 * Önce pause.
                 */
                view.paused =
                    YES;

                /*
                 * Yeni frame isteklerini kapat.
                 */
                view.enableSetNeedsDisplay =
                    NO;

                /*
                 * Delegate'i kes.
                 */
                view.delegate =
                    nil;

                /*
                 * Touch callback'lerini kes.
                 */
                view.userInteractionEnabled =
                    NO;

                view.multipleTouchEnabled =
                    NO;

                /*
                 * Hierarchy'den çıkar.
                 */
                [view removeFromSuperview];
            }

            /*
             * =================================================
             * 3. RENDERER REFERANSINI BIRAK
             * =================================================
             */

            gRenderer =
                nil;

            /*
             * =================================================
             * 4. RENDERER CALLBACK'İ TAMAMLANDIYSA TEMİZLE
             * =================================================
             *
             * Normal MTKView lifecycle'da stop main queue'da
             * geldiği için draw callback'i burada devam etmiyor.
             */
            if (!gRenderingFrame)
            {
                /*
                 * =================================================
                 * 5. SADECE KENDİ CONTEXT'İMİZİ KAPAT
                 * =================================================
                 */

                if (gASASECImGuiContext)
                {
                    ASASECSafeDestroyOwnImGuiContext();
                }
            }

            /*
             * =================================================
             * 6. METAL STATE
             * =================================================
             */

            gMetalInitialized =
                NO;

            gASASECBackendOwned =
                NO;

            gCommandQueue =
                nil;

            gMetalDevice =
                nil;

            /*
             * =================================================
             * 7. UI STATE
             * =================================================
             */

            gDraggingMenu =
                NO;

            gResizingMenu =
                NO;

            gContentDragging =
                NO;

            gContentTouchCandidate =
                NO;

            gContentHasMoved =
                NO;

            gPendingContentScrollY =
                0.0f;

            gContentScrollVelocity =
                0.0f;

            gActiveTouchCount =
                0;

            gRenderingFrame =
                NO;

            /*
             * Stop tamamlandı.
             */
            gStopping =
                NO;
        }
    );
}
