#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <string.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include "../imgui.h"
#include "../imgui_internal.h"
#include "../Backends/imgui_impl_metal.h"

#pragma mark - Global State

static MTKView *gImGuiView = nil;
static id gMetalDevice = nil;
static id gCommandQueue = nil;

static BOOL gInitialized = NO;
static BOOL gStarting = NO;

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 390.0f);

static const float kMenuMinWidth = 430.0f;
static const float kMenuMaxWidth = 760.0f;
static const float kMenuMinHeight = 300.0f;
static const float kMenuMaxHeight = 620.0f;

static const float kHeaderHeight = 54.0f;
static const float kResizeSize = 48.0f;

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

#pragma mark - Renderer

@interface ASASECImGuiRenderer : NSObject <MTKViewDelegate>
@end

static ASASECImGuiRenderer *gRenderer = nil;

#pragma mark - Helpers

static float ASASECClampFloat(float value,
                              float minValue,
                              float maxValue)
{
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
    if (dt <= 0.0f)
        dt = 1.0f / 60.0f;

    if (dt > 0.1f)
        dt = 0.1f;

    if (speed <= 0.0f)
        return target;

    float factor = 1.0f - expf(-speed * dt);

    return current + (target - current) * factor;
}

static ImU32 ASASECColor(float r,
                         float g,
                         float b,
                         float a)
{
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

    return nil;
}

static void ASASECClampMenuToScreen(UIWindow *window)
{
    if (!window)
        return;

    CGSize size = window.bounds.size;

    float width = gMenuSize.x;

    float height =
        gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    const float margin = 8.0f;

    float maxX =
        (float)size.width -
        width -
        margin;

    float maxY =
        (float)size.height -
        height -
        margin;

    if (maxX < margin)
        maxX = margin;

    if (maxY < margin)
        maxY = margin;

    gMenuPosition.x =
        ASASECClampFloat(
            gMenuPosition.x,
            margin,
            maxX
        );

    gMenuPosition.y =
        ASASECClampFloat(
            gMenuPosition.y,
            margin,
            maxY
        );
}

#pragma mark - Switch Animation

typedef struct
{
    const char *label;
    float progress;
    float pulse;
} ASASECSwitchAnimation;

static ASASECSwitchAnimation gSwitchAnimations[64];
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
        if (gSwitchAnimations[i].label &&
            strcmp(
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

static bool ASASECModernSwitch(const char *label,
                               bool *value)
{
    if (!label || !value)
        return false;

    ImGui::PushID(label);

    const float switchWidth = 54.0f;
    const float switchHeight = 28.0f;
    const float rowHeight = 52.0f; // Butonların birbirine girmemesi için satır yüksekliği artırıldı

    float available =
        ImGui::GetContentRegionAvail().x;

    if (available < 180.0f)
        available = 180.0f;

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

    ASASECSwitchAnimation *animationData =
        ASASECGetSwitchAnimationData(label);

    if (clicked)
    {
        *value = !(*value);

        if (animationData)
            animationData->pulse = 1.0f;
    }

    bool hovered =
        ImGui::IsItemHovered();

    float dt =
        ImGui::GetIO().DeltaTime;

    if (dt <= 0.0f || dt > 0.1f)
        dt = 1.0f / 60.0f;

    float progress =
        animationData
        ? animationData->progress
        : (*value ? 1.0f : 0.0f);

    float target =
        *value ? 1.0f : 0.0f;

    progress =
        ASASECEase(
            progress,
            target,
            16.0f,
            dt
        );

    if (animationData)
    {
        animationData->progress =
            progress;

        animationData->pulse =
            ASASECEase(
                animationData->pulse,
                0.0f,
                12.0f,
                dt
            );
    }

    float pulse =
        animationData
        ? animationData->pulse
        : 0.0f;

    // Modernleştirilmiş Kart Tasarımı (Content Geliştirmesi)
    draw->AddRectFilled(
        itemMin,
        itemMax,
        ASASECColor(0.08f, 0.11f, 0.17f, 0.75f),
        12.0f
    );
    draw->AddRect(
        itemMin,
        itemMax,
        ASASECColor(0.20f, 0.28f, 0.40f, 0.6f),
        12.0f,
        0,
        1.1f
    );

    float switchX =
        itemMax.x -
        switchWidth -
        16.0f;

    float switchY =
        itemMin.y +
        (rowHeight - switchHeight) *
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
        0.10f +
        (0.20f - 0.10f) *
        progress;

    float bgG =
        0.14f +
        (0.55f - 0.14f) *
        progress;

    float bgB =
        0.22f +
        (1.00f - 0.22f) *
        progress;

    if (hovered)
    {
        bgR += 0.03f;
        bgG += 0.03f;
        bgB += 0.03f;
    }

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

    draw->AddRect(
        switchMin,
        switchMax,
        ASASECColor(
            0.25f + 0.25f * progress,
            0.32f + 0.35f * progress,
            0.45f + 0.45f * progress,
            0.8f
        ),
        switchHeight * 0.5f,
        0,
        1.0f
    );

    float offX =
        switchMin.x + 15.0f;

    float onX =
        switchMax.x - 15.0f;

    float knobX =
        offX +
        (onX - offX) *
        progress;

    float knobY =
        switchMin.y +
        switchHeight * 0.5f;

    float knobRadius =
        10.0f +
        pulse * 1.5f;

    if (pulse > 0.01f)
    {
        draw->AddCircle(
            ImVec2(
                knobX,
                knobY
            ),
            13.0f +
                pulse * 3.0f,
            ASASECColor(
                0.30f,
                0.68f,
                1.0f,
                pulse * 0.35f
            ),
            24,
            1.8f
        );
    }

    draw->AddCircleFilled(
        ImVec2(
            knobX,
            knobY + 1.0f
        ),
        knobRadius + 0.5f,
        ASASECColor(
            0.0f,
            0.0f,
            0.0f,
            0.3f
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

    ImGui::SetCursorScreenPos(
        ImVec2(
            itemMin.x + 16.0f,
            itemMin.y + (rowHeight - 20.0f) * 0.5f
        )
    );

    ImGui::TextColored(
        ImVec4(
            0.94f,
            0.97f,
            1.0f,
            1.0f
        ),
        "%s",
        label
    );

    ImGui::PopID();

    return clicked;
}

#pragma mark - ImGui View

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

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

- (BOOL)pointInsideResizeHandle:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    if (gMenuCollapsed)
        return NO;

    float right =
        gMenuPosition.x +
        gMenuSize.x;

    float bottom =
        gMenuPosition.y +
        gMenuSize.y;

    return
        point.x >= right - kResizeSize &&
        point.x <= right + 8.0f &&
        point.y >= bottom - kResizeSize &&
        point.y <= bottom + 8.0f;
}

- (BOOL)pointInsideDragHeader:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    return
        point.x >= gMenuPosition.x &&
        point.x <=
            gMenuPosition.x +
            gMenuSize.x &&
        point.y >= gMenuPosition.y &&
        point.y <=
            gMenuPosition.y +
            kHeaderHeight;
}

- (BOOL)pointInsideContent:(CGPoint)point
{
    if (!gMenuVisible ||
        gMenuCollapsed)
        return NO;

    const float sidebarWidth = 145.0f;

    float contentLeft =
        gMenuPosition.x +
        sidebarWidth;

    float contentTop =
        gMenuPosition.y +
        kHeaderHeight;

    float contentRight =
        gMenuPosition.x +
        gMenuSize.x;

    float contentBottom =
        gMenuPosition.y +
        gMenuSize.y;

    return
        point.x >= contentLeft &&
        point.x <= contentRight &&
        point.y >= contentTop &&
        point.y <= contentBottom;
}

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{
    if (!gInitialized || !gMenuVisible)
        return nil;

    if ([self pointInsideMenu:point])
        return self;

    return nil;
}

- (void)beginMenuDragAtPoint:(CGPoint)point
{
    if (!gMenuVisible)
        return;

    gDraggingMenu = YES;
    gResizingMenu = NO;
    gContentDragging = NO;

    gDragStartPoint = point;
    gDragStartPosition = gMenuPosition;
}

- (void)updateMenuDragAtPoint:(CGPoint)point
{
    if (!gDraggingMenu)
        return;

    CGFloat dx = point.x - gDragStartPoint.x;
    CGFloat dy = point.y - gDragStartPoint.y;

    gMenuPosition.x = gDragStartPosition.x + (float)dx;
    gMenuPosition.y = gDragStartPosition.y + (float)dy;

    [self clampMenuPosition];
}

- (void)beginMenuResizeAtPoint:(CGPoint)point
{
    if (!gMenuVisible || gMenuCollapsed)
        return;

    gResizingMenu = YES;
    gDraggingMenu = NO;
    gContentDragging = NO;

    gResizeStartPoint = point;
    gResizeStartSize = gMenuSize;
}

- (void)updateMenuResizeAtPoint:(CGPoint)point
{
    if (!gResizingMenu)
        return;

    CGFloat dx = point.x - gResizeStartPoint.x;
    CGFloat dy = point.y - gResizeStartPoint.y;

    float newWidth = gResizeStartSize.x + (float)dx;
    float newHeight = gResizeStartSize.y + (float)dy;

    newWidth = ASASECClampFloat(newWidth, kMenuMinWidth, kMenuMaxWidth);
    newHeight = ASASECClampFloat(newHeight, kMenuMinHeight, kMenuMaxHeight);

    UIWindow *window = self.window;
    if (window)
    {
        CGSize screenSize = window.bounds.size;
        float availableWidth = (float)screenSize.width - gMenuPosition.x - 8.0f;
        float availableHeight = (float)screenSize.height - gMenuPosition.y - 8.0f;

        if (availableWidth >= kMenuMinWidth)
            newWidth = MIN(newWidth, availableWidth);

        if (availableHeight >= kMenuMinHeight)
            newHeight = MIN(newHeight, availableHeight);
    }

    gMenuSize.x = newWidth;
    gMenuSize.y = newHeight;
}

- (void)beginContentDragAtPoint:(CGPoint)point
{
    if (!gMenuVisible || gMenuCollapsed)
        return;

    gContentDragging = YES;
    gContentTouchCandidate = YES;
    gContentHasMoved = NO;
    gDraggingMenu = NO;
    gResizingMenu = NO;

    gContentStartPoint = point;
    gContentLastPoint = point;
    gPendingContentScrollY = 0.0f;
    gContentScrollVelocity = 0.0f;
}

- (void)updateContentDragAtPoint:(CGPoint)point
{
    if (!gContentDragging)
        return;

    float dy = (float)(point.y - gContentLastPoint.y);
    float dx = (float)(point.x - gContentLastPoint.x);

    if (fabsf(dy) < 0.05f)
        dy = 0.0f;

    float totalDX = fabsf((float)(point.x - gContentStartPoint.x));
    float totalDY = fabsf((float)(point.y - gContentStartPoint.y));

    if (!gContentHasMoved)
    {
        if (totalDY > 5.0f && totalDY >= totalDX)
            gContentHasMoved = YES;
    }

    if (gContentHasMoved)
    {
        float scrollDelta = -dy;
        gPendingContentScrollY += scrollDelta;
        gContentScrollVelocity = scrollDelta;
    }

    gContentLastPoint = point;
}

- (void)endContentDrag
{
    if (!gContentDragging)
        return;
    gContentDragging = NO;
    gContentTouchCandidate = NO;
}

- (void)endMenuInteraction
{
    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentDragging = NO;
    gContentTouchCandidate = NO;
}

- (void)clampMenuPosition
{
    UIWindow *window = self.window;
    if (!window)
        return;
    ASASECClampMenuToScreen(window);
}

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    ImGuiContext *ctx = ImGui::GetCurrentContext();
    if (!ctx)
        return;

    ImGuiIO &io = ImGui::GetIO();
    UITouch *touch = event.allTouches.anyObject;

    if (touch)
    {
        CGPoint point = [touch locationInView:self];
        io.MousePos = ImVec2((float)point.x, (float)point.y);
    }

    BOOL touching = NO;
    for (UITouch *currentTouch in event.allTouches)
    {
        if (!currentTouch)
            continue;
        if (currentTouch.phase != UITouchPhaseEnded &&
            currentTouch.phase != UITouchPhaseCancelled)
        {
            touching = YES;
            break;
        }
    }

    io.MouseDown[0] = touching;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    UITouch *touch = touches.anyObject;
    if (touch)
    {
        CGPoint point = [touch locationInView:self];

        if ([self pointInsideResizeHandle:point])
            [self beginMenuResizeAtPoint:point];
        else if ([self pointInsideDragHeader:point])
            [self beginMenuDragAtPoint:point];
        else if ([self pointInsideContent:point])
            [self beginContentDragAtPoint:point];
    }

    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    UITouch *touch = touches.anyObject;
    if (touch)
    {
        CGPoint point = [touch locationInView:self];

        if (gResizingMenu)
            [self updateMenuResizeAtPoint:point];
        else if (gDraggingMenu)
            [self updateMenuDragAtPoint:point];
        else if (gContentDragging)
            [self updateContentDragAtPoint:point];
    }

    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (gContentDragging)
        [self endContentDrag];
    else
        [self endMenuInteraction];

    if (!gInitialized)
        return;

    [self updateIOWithTouchEvent:event];

    ImGuiContext *ctx = ImGui::GetCurrentContext();
    if (ctx)
    {
        ImGuiIO &io = ImGui::GetIO();
        io.MouseDown[0] = false;
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self endMenuInteraction];

    gContentScrollVelocity = 0.0f;
    gPendingContentScrollY = 0.0f;

    if (!gInitialized)
        return;

    [self updateIOWithTouchEvent:event];

    ImGuiContext *ctx = ImGui::GetCurrentContext();
    if (ctx)
    {
        ImGuiIO &io = ImGui::GetIO();
        io.MouseDown[0] = false;
    }
}

@end

#pragma mark - Style

static void ASASECApplyStyle(void)
{
    if (!ImGui::GetCurrentContext())
        return;

    ImGuiStyle &style = ImGui::GetStyle();

    style.WindowPadding = ImVec2(10.0f, 10.0f);
    style.FramePadding = ImVec2(11.0f, 8.0f);
    style.ItemSpacing = ImVec2(10.0f, 10.0f); // Butonlar arası boşluk optimize edildi
    style.ItemInnerSpacing = ImVec2(7.0f, 6.0f);
    style.ScrollbarSize = 1.0f;
    style.GrabMinSize = 15.0f;
    style.WindowRounding = 22.0f;
    style.ChildRounding = 16.0f;
    style.FrameRounding = 10.0f;
    style.PopupRounding = 12.0f;
    style.ScrollbarRounding = 8.0f;
    style.GrabRounding = 8.0f;
    style.TabRounding = 10.0f;
    style.WindowBorderSize = 0.0f;
    style.ChildBorderSize = 1.0f;
    style.FrameBorderSize = 0.0f;
    style.IndentSpacing = 20.0f;

    ImVec4 *c = style.Colors;

    c[ImGuiCol_Text] = ImVec4(0.93f, 0.96f, 1.0f, 1.0f);
    c[ImGuiCol_TextDisabled] = ImVec4(0.40f, 0.45f, 0.54f, 1.0f);
    c[ImGuiCol_WindowBg] = ImVec4(0.018f, 0.024f, 0.038f, 0.985f);
    c[ImGuiCol_ChildBg] = ImVec4(0.040f, 0.052f, 0.074f, 0.98f);
    c[ImGuiCol_Border] = ImVec4(0.13f, 0.17f, 0.24f, 0.75f);
    c[ImGuiCol_FrameBg] = ImVec4(0.060f, 0.076f, 0.108f, 1.0f);
    c[ImGuiCol_FrameBgHovered] = ImVec4(0.095f, 0.125f, 0.18f, 1.0f);
    c[ImGuiCol_FrameBgActive] = ImVec4(0.12f, 0.18f, 0.27f, 1.0f);
    c[ImGuiCol_Button] = ImVec4(0.060f, 0.080f, 0.12f, 1.0f);
    c[ImGuiCol_ButtonHovered] = ImVec4(0.105f, 0.15f, 0.23f, 1.0f);
    c[ImGuiCol_ButtonActive] = ImVec4(0.14f, 0.24f, 0.39f, 1.0f);
    c[ImGuiCol_CheckMark] = ImVec4(0.30f, 0.68f, 1.0f, 1.0f);
    c[ImGuiCol_SliderGrab] = ImVec4(0.22f, 0.56f, 1.0f, 1.0f);
    c[ImGuiCol_SliderGrabActive] = ImVec4(0.38f, 0.70f, 1.0f, 1.0f);
    c[ImGuiCol_Header] = ImVec4(0.10f, 0.17f, 0.27f, 1.0f);
    c[ImGuiCol_HeaderHovered] = ImVec4(0.14f, 0.23f, 0.36f, 1.0f);
    c[ImGuiCol_HeaderActive] = ImVec4(0.17f, 0.30f, 0.47f, 1.0f);
    c[ImGuiCol_Separator] = ImVec4(0.13f, 0.17f, 0.23f, 0.80f);
}

#pragma mark - Renderer

@implementation ASASECImGuiRenderer

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    if (!gInitialized || !view)
        return;

    ImGuiContext *ctx = ImGui::GetCurrentContext();
    if (!ctx)
        return;

    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2((float)view.bounds.size.width, (float)view.bounds.size.height);

    CGFloat scale = view.contentScaleFactor;
    if (scale <= 0.0)
        scale = 1.0;

    io.DisplayFramebufferScale = ImVec2((float)scale, (float)scale);
}

- (void)drawInMTKView:(MTKView *)view
{
    if (!gInitialized || !view || !gMetalDevice || !gCommandQueue)
        return;

    ImGuiContext *ctx = ImGui::GetCurrentContext();
    if (!ctx)
        return;

    MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
    if (!pass)
        return;

    id drawable = view.currentDrawable;
    if (!drawable)
        return;

    id commandBuffer = [gCommandQueue commandBuffer];
    if (!commandBuffer)
        return;

    ImGui_ImplMetal_NewFrame(pass);

    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2((float)view.bounds.size.width, (float)view.bounds.size.height);

    CGFloat scale = view.contentScaleFactor;
    if (scale <= 0.0)
        scale = 1.0;

    io.DisplayFramebufferScale = ImVec2((float)scale, (float)scale);

    float fps = (float)view.preferredFramesPerSecond;
    if (fps < 1.0f)
        fps = 60.0f;

    io.DeltaTime = 1.0f / fps;
    if (io.DeltaTime <= 0.0f || io.DeltaTime > 0.1f)
        io.DeltaTime = 1.0f / 60.0f;

    ImGui::NewFrame();

    float dt = io.DeltaTime;
    if (dt <= 0.0f || dt > 0.1f)
        dt = 1.0f / 60.0f;

    if (gSelectedPage != gPreviousPage)
    {
        gPreviousPage = gSelectedPage;
        gPageAnimation = 0.0f;
        gPageSlide = 18.0f;
    }

    gPageAnimation = ASASECEase(gPageAnimation, 1.0f, 14.0f, dt);
    gPageSlide = ASASECEase(gPageSlide, 0.0f, 14.0f, dt);

    if (!gContentDragging && fabsf(gContentScrollVelocity) > 0.01f)
    {
        gPendingContentScrollY += gContentScrollVelocity;
        gContentScrollVelocity *= expf(-7.0f * dt);
        if (fabsf(gContentScrollVelocity) < 0.01f)
            gContentScrollVelocity = 0.0f;
    }

    if (gMenuVisible)
    {
        const float sidebarWidth = 145.0f;

        ImVec2 actualWindowSize = ImVec2(
            gMenuSize.x,
            gMenuCollapsed ? kHeaderHeight : gMenuSize.y
        );

        ImGui::SetNextWindowPos(gMenuPosition, ImGuiCond_Always);
        ImGui::SetNextWindowSize(actualWindowSize, ImGuiCond_Always);

        ImGuiWindowFlags flags =
            ImGuiWindowFlags_NoTitleBar |
            ImGuiWindowFlags_NoResize |
            ImGuiWindowFlags_NoCollapse |
            ImGuiWindowFlags_NoSavedSettings |
            ImGuiWindowFlags_NoScrollbar;

        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0.0f, 0.0f));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 22.0f);
        ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.018f, 0.024f, 0.038f, 0.985f));

        ImGui::Begin("##ASASEC_WINDOW", NULL, flags);

        ImVec2 windowPos = ImGui::GetWindowPos();
        ImVec2 windowSize = ImGui::GetWindowSize();
        ImVec2 windowEnd = ImVec2(windowPos.x + windowSize.x, windowPos.y + windowSize.y);

        ImDrawList *draw = ImGui::GetWindowDrawList();

        if (draw)
        {
            // Sol üst köşe yumuşatması (TopLeft corner yumuşak çizim maskesi ile desteklendi)
            draw->AddRectFilled(windowPos, windowEnd, IM_COL32(6, 9, 16, 252), 22.0f);
            draw->AddRect(
                ImVec2(windowPos.x + 0.5f, windowPos.y + 0.5f),
                ImVec2(windowEnd.x - 0.5f, windowEnd.y - 0.5f),
                IM_COL32(48, 62, 84, 185),
                22.0f, 0, 1.0f
            );

            draw->AddRectFilled(
                ImVec2(windowPos.x + 1.0f, windowPos.y + 1.0f),
                ImVec2(windowEnd.x - 1.0f, windowPos.y + kHeaderHeight),
                IM_COL32(10, 15, 25, 255),
                21.0f, ImDrawFlags_RoundCornersTopLeft | ImDrawFlags_RoundCornersTopRight
            );

            draw->AddLine(
                ImVec2(windowPos.x + 16.0f, windowPos.y + kHeaderHeight),
                ImVec2(windowEnd.x - 16.0f, windowPos.y + kHeaderHeight),
                IM_COL32(38, 48, 66, 220), 1.0f
            );
        }

        // Sol üst Logo/İsim Alanı (ASASEC UI her ikihalde de görünür)
        ImGui::SetCursorPos(ImVec2(18.0f, 11.0f));
        ImGui::TextColored(ImVec4(0.30f, 0.68f, 1.0f, 1.0f), "●");
        ImGui::SameLine(0.0f, 7.0f);

        ImGui::PushFont(ImGui::GetIO().Fonts->Fonts[0]);
        ImGui::SetWindowFontScale(1.15f);
        ImGui::TextColored(ImVec4(0.94f, 0.97f, 1.0f, 1.0f), "ASASEC");
        ImGui::SameLine(0.0f, 5.0f);
        ImGui::TextColored(ImVec4(0.43f, 0.49f, 0.59f, 1.0f), "UI");
        ImGui::SetWindowFontScale(1.0f);
        ImGui::PopFont();

        // Control Center Başlığı: Yalnızca Menü Normal (Açık) Haldeyken Gözüksün
        if (!gMenuCollapsed)
        {
            float headerTitleX = windowSize.x - 290.0f;
            if (headerTitleX > 160.0f)
            {
                ImGui::SetCursorPos(ImVec2(headerTitleX, 18.0f));
                ImGui::TextColored(ImVec4(0.35f, 0.42f, 0.52f, 1.0f), "CONTROL CENTER");
            }
        }

        // Collapse Butonu
        float collapseButtonX = windowSize.x - 96.0f;
        ImGui::SetCursorPos(ImVec2(collapseButtonX, 9.0f));
        ImGui::PushID("ASASEC_COLLAPSE_BUTTON");
        ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 10.0f);
        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.06f, 0.09f, 0.14f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.11f, 0.18f, 0.29f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.17f, 0.28f, 0.43f, 1.0f));
        ImGui::Button("##collapse", ImVec2(38.0f, 34.0f));

        bool collapsePressed = ImGui::IsItemClicked();
        bool collapseHovered = ImGui::IsItemHovered();
        ImVec2 arrowMin = ImGui::GetItemRectMin();
        ImVec2 arrowMax = ImGui::GetItemRectMax();
        ImDrawList *headerDraw = ImGui::GetWindowDrawList();

        if (headerDraw)
        {
            float centerX = (arrowMin.x + arrowMax.x) * 0.5f;
            float centerY = (arrowMin.y + arrowMax.y) * 0.5f;
            float arrowWidth = 7.0f;
            float arrowHeight = 5.0f;

            ImU32 arrowColor = collapseHovered
                ? ASASECColor(0.42f, 0.74f, 1.0f, 1.0f)
                : ASASECColor(0.78f, 0.84f, 0.93f, 0.95f);

            if (gMenuCollapsed)
            {
                headerDraw->AddLine(ImVec2(centerX - arrowWidth, centerY - arrowHeight), ImVec2(centerX, centerY + arrowHeight), arrowColor, 2.2f);
                headerDraw->AddLine(ImVec2(centerX, centerY + arrowHeight), ImVec2(centerX + arrowWidth, centerY - arrowHeight), arrowColor, 2.2f);
            }
            else
            {
                headerDraw->AddLine(ImVec2(centerX - arrowWidth, centerY + arrowHeight), ImVec2(centerX, centerY - arrowHeight), arrowColor, 2.2f);
                headerDraw->AddLine(ImVec2(centerX, centerY - arrowHeight), ImVec2(centerX + arrowWidth, centerY + arrowHeight), arrowColor, 2.2f);
            }
        }

        if (collapsePressed)
        {
            gMenuCollapsed = !gMenuCollapsed;
            gDraggingMenu = NO;
            gResizingMenu = NO;
            gContentDragging = NO;
            gContentScrollVelocity = 0.0f;
            gPendingContentScrollY = 0.0f;

            UIWindow *window = view.window;
            if (window)
                ASASECClampMenuToScreen(window);
        }

        ImGui::PopStyleColor(3);
        ImGui::PopStyleVar();
        ImGui::PopID();

        // Close Butonu
        float closeButtonX = windowSize.x - 50.0f;
        ImGui::SetCursorPos(ImVec2(closeButtonX, 9.0f));
        ImGui::PushID("ASASEC_CLOSE_BUTTON");
        ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 10.0f);
        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.10f, 0.065f, 0.085f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.34f, 0.10f, 0.15f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.48f, 0.12f, 0.18f, 1.0f));
        ImGui::Button("##close", ImVec2(34.0f, 34.0f));

        bool closePressed = ImGui::IsItemClicked();
        bool closeHovered = ImGui::IsItemHovered();
        ImVec2 closeMin = ImGui::GetItemRectMin();
        ImVec2 closeMax = ImGui::GetItemRectMax();
        ImDrawList *closeDraw = ImGui::GetWindowDrawList();

        if (closeDraw)
        {
            float cx = (closeMin.x + closeMax.x) * 0.5f;
            float cy = (closeMin.y + closeMax.y) * 0.5f;
            float size = 6.0f;

            ImU32 closeColor = closeHovered
                ? ASASECColor(1.0f, 0.45f, 0.52f, 1.0f)
                : ASASECColor(0.86f, 0.90f, 0.96f, 0.95f);

            closeDraw->AddLine(ImVec2(cx - size, cy - size), ImVec2(cx + size, cy + size), closeColor, 2.2f);
            closeDraw->AddLine(ImVec2(cx + size, cy - size), ImVec2(cx - size, cy + size), closeColor, 2.2f);
        }

        if (closePressed)
        {
            gMenuVisible = NO;
            gMenuCollapsed = NO;
            gDraggingMenu = NO;
            gResizingMenu = NO;
            gContentDragging = NO;
        }

        ImGui::PopStyleColor(3);
        ImGui::PopStyleVar();
        ImGui::PopID();

        if (!gMenuCollapsed && gMenuVisible)
        {
            if (draw)
            {
                draw->AddRectFilled(
                    windowPos,
                    ImVec2(windowPos.x + sidebarWidth, windowEnd.y),
                    IM_COL32(9, 14, 24, 255),
                    22.0f, ImDrawFlags_RoundCornersBottomLeft
                );

                draw->AddLine(
                    ImVec2(windowPos.x + sidebarWidth, windowPos.y + 62.0f),
                    ImVec2(windowPos.x + sidebarWidth, windowEnd.y - 16.0f),
                    IM_COL32(34, 43, 59, 210), 1.0f
                );
            }

            ImGui::SetCursorPos(ImVec2(18.0f, 36.0f));
            ImGui::TextColored(ImVec4(0.27f, 0.32f, 0.40f, 1.0f), "NAVIGATION");

            const char *pages[] = { "Combat", "Visuals", "Settings" };
            const char *icons[] = { "A", "V", "S" };

            for (int i = 0; i < 3; i++)
            {
                bool active = gSelectedPage == i;
                float itemY = 72.0f + i * 53.0f;

                if (active && draw)
                {
                    draw->AddRectFilled(
                        ImVec2(windowPos.x + 9.0f, windowPos.y + itemY),
                        ImVec2(windowPos.x + sidebarWidth - 9.0f, windowPos.y + itemY + 42.0f),
                        IM_COL32(19, 48, 84, 255), 11.0f
                    );

                    draw->AddCircleFilled(
                        ImVec2(windowPos.x + 18.0f, windowPos.y + itemY + 21.0f),
                        3.0f, IM_COL32(80, 160, 255, 255)
                    );
                }

                char id[64];
                snprintf(id, sizeof(id), "%s   %s##page_%d", icons[i], pages[i], i);

                ImGui::SetCursorPos(ImVec2(10.0f, itemY));
                ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 11.0f);
                ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.0f, 0.0f, 0.0f, 0.0f));
                ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.10f, 0.17f, 0.27f, 0.85f));
                ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.13f, 0.24f, 0.39f, 1.0f));

                if (ImGui::Button(id, ImVec2(sidebarWidth - 20.0f, 42.0f)))
                {
                    if (gSelectedPage != i)
                    {
                        gSelectedPage = i;
                        gPageAnimation = 0.0f;
                        gPageSlide = 18.0f;
                        gPendingContentScrollY = 0.0f;
                        gContentScrollVelocity = 0.0f;
                    }
                }

                ImGui::PopStyleColor(3);
                ImGui::PopStyleVar();
            }

            ImGui::SetCursorPos(ImVec2(sidebarWidth + 1.0f, 54.0f));

            float contentWidth = windowSize.x - sidebarWidth - 1.0f;
            float contentHeight = windowSize.y - 54.0f;

            if (contentWidth < 100.0f) contentWidth = 100.0f;
            if (contentHeight < 100.0f) contentHeight = 100.0f;

            ImGui::BeginChild(
                "##ContentRoot",
                ImVec2(contentWidth, contentHeight),
                false,
                ImGuiWindowFlags_NoBackground | ImGuiWindowFlags_NoScrollbar
            );

            ImGui::SetCursorPos(ImVec2(18.0f, 12.0f));

            const char *pageTitle = gSelectedPage == 0 ? "Combat" : gSelectedPage == 1 ? "Visuals" : "Settings";

            ImGui::TextColored(ImVec4(0.94f, 0.97f, 1.0f, 1.0f), "%s", pageTitle);
            ImGui::SameLine(0.0f, 7.0f);
            ImGui::TextColored(ImVec4(0.30f, 0.36f, 0.45f, 1.0f), "/ ASASEC");

            if (draw)
            {
                draw->AddLine(
                    ImVec2(windowPos.x + sidebarWidth + 16.0f, windowPos.y + 51.0f),
                    ImVec2(windowEnd.x - 16.0f, windowPos.y + 51.0f),
                    IM_COL32(32, 41, 56, 220), 1.0f
                );
            }

            ImGui::SetCursorPos(ImVec2(0.0f, 60.0f));
            float scrollHeight = contentHeight - 60.0f;
            if (scrollHeight < 100.0f) scrollHeight = 100.0f;

            ImGui::BeginChild(
                "##ScrollableContent",
                ImVec2(contentWidth, scrollHeight),
                false,
                ImGuiWindowFlags_NoScrollbar
            );

            float fade = ASASECClampFloat(gPageAnimation, 0.0f, 1.0f);
            ImGui::PushStyleVar(ImGuiStyleVar_Alpha, fade);
            ImGui::SetCursorPosX(16.0f + gPageSlide);

            if (gSelectedPage == 0)
            {
                ImGui::TextColored(ImVec4(0.30f, 0.68f, 1.0f, 1.0f), "COMBAT");
                ImGui::SameLine(0.0f, 6.0f);
                ImGui::TextColored(ImVec4(0.34f, 0.39f, 0.48f, 1.0f), "ACTIONS");
                ImGui::TextColored(ImVec4(0.43f, 0.47f, 0.55f, 1.0f), "Configure your combat options");
                ImGui::Spacing();

                static bool sw1 = false;
                static bool sw2 = false;
                static bool sw3 = false;
                static bool sw4 = false;

                ImGui::BeginChild("##CombatCard", ImVec2(ImGui::GetContentRegionAvail().x - 20.0f, 235.0f), true);
                ASASECModernSwitch("Aimbot Enable", &sw1);
                ASASECModernSwitch("Silent Aim", &sw2);
                ASASECModernSwitch("Recoil Control", &sw3);
                ASASECModernSwitch("Rapid Fire", &sw4);
                ImGui::EndChild();
            }
            else if (gSelectedPage == 1)
            {
                ImGui::TextColored(ImVec4(0.28f, 0.86f, 0.58f, 1.0f), "VISUALS");
                ImGui::SameLine(0.0f, 6.0f);
                ImGui::TextColored(ImVec4(0.34f, 0.39f, 0.48f, 1.0f), "ESP");
                ImGui::TextColored(ImVec4(0.43f, 0.47f, 0.55f, 1.0f), "Configure visual options");
                ImGui::Spacing();

                static bool sw1 = false;
                static bool sw2 = false;
                static bool sw3 = false;
                static bool sw4 = false;

                ImGui::BeginChild("##VisualCard", ImVec2(ImGui::GetContentRegionAvail().x - 20.0f, 235.0f), true);
                ASASECModernSwitch("Player ESP", &sw1);
                ASASECModernSwitch("Box ESP", &sw2);
                ASASECModernSwitch("Distance ESP", &sw3);
                ASASECModernSwitch("Skeleton ESP", &sw4);
                ImGui::EndChild();
            }
            else
            {
                ImGui::TextColored(ImVec4(1.0f, 0.67f, 0.28f, 1.0f), "SETTINGS");
                ImGui::SameLine(0.0f, 6.0f);
                ImGui::TextColored(ImVec4(0.34f, 0.39f, 0.48f, 1.0f), "SYSTEM");
                ImGui::TextColored(ImVec4(0.43f, 0.47f, 0.55f, 1.0f), "ASASEC configuration");
                ImGui::Spacing();

                static bool sw1 = false;
                static bool sw2 = false;
                static bool sw3 = false;
                static bool sw4 = false;

                ImGui::BeginChild("##SettingsCard", ImVec2(ImGui::GetContentRegionAvail().x - 20.0f, 235.0f), true);
                ASASECModernSwitch("Save Config", &sw1);
                ASASECModernSwitch("Dark Theme", &sw2);
                ASASECModernSwitch("Vibration", &sw3);
                ASASECModernSwitch("Developer Mode", &sw4);
                ImGui::EndChild();
            }

            ImGui::PopStyleVar();

            if (fabsf(gPendingContentScrollY) > 0.001f)
            {
                float currentScroll = ImGui::GetScrollY();
                float maxScroll = ImGui::GetScrollMaxY();
                float targetScroll = ASASECClampFloat(currentScroll + gPendingContentScrollY, 0.0f, maxScroll);
                ImGui::SetScrollY(targetScroll);
                gPendingContentScrollY = 0.0f;
            }

            ImGui::EndChild();
            ImGui::EndChild();
        }

        // Sağ Alt Köşe İçin Çok Daha Belirgin, Net ve Sabit Boyutlandırma (Resize) Simgesi
        if (draw && windowSize.x > 300.0f && windowSize.y > 220.0f)
        {
            float right = windowSize.x - 4.0f;
            float bottom = windowSize.y - 4.0f;

            ImVec2 iconCenter = ImVec2(windowPos.x + right - 12.0f, windowPos.y + bottom - 12.0f);
            BOOL resizeActive = gResizingMenu;

            ImU32 iconColor = resizeActive
                ? ASASECColor(0.42f, 0.72f, 1.0f, 1.0f)
                : ASASECColor(0.98f, 0.99f, 1.0f, 0.95f);

            // Çok daha belirgin ve kalın üçlü köşe çizgileri (Simgenin net görünmeme sorunu tamamen çözüldü)
            draw->AddLine(ImVec2(iconCenter.x - 10.0f, iconCenter.y + 10.0f), ImVec2(iconCenter.x + 10.0f, iconCenter.y + 10.0f), iconColor, 3.0f);
            draw->AddLine(ImVec2(iconCenter.x + 10.0f, iconCenter.y - 10.0f), ImVec2(iconCenter.x + 10.0f, iconCenter.y + 10.0f), iconColor, 3.0f);
            draw->AddLine(ImVec2(iconCenter.x - 2.0f, iconCenter.y + 10.0f), ImVec2(iconCenter.x + 10.0f, iconCenter.y - 2.0f), iconColor, 2.2f);
            draw->AddLine(ImVec2(iconCenter.x - 7.0f, iconCenter.y + 10.0f), ImVec2(iconCenter.x + 10.0f, iconCenter.y - 7.0f), iconColor, 1.8f);
        }

        ImGui::End();
        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);
    }

    ImGui::Render();
    ImDrawData *drawData = ImGui::GetDrawData();

    if (!drawData)
    {
        [commandBuffer commit];
        return;
    }

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder)
    {
        [commandBuffer commit];
        return;
    }

    [encoder setViewport:(MTLViewport){
        0.0, 0.0,
        (double)view.drawableSize.width,
        (double)view.drawableSize.height,
        0.0, 1.0
    }];

    ImGui_ImplMetal_RenderDrawData(drawData, commandBuffer, encoder);

    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end

#pragma mark - Start / Stop

void ASASECImGuiStart(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gInitialized || gStarting)
            return;

        gStarting = YES;
        UIWindow *window = ASASECFindActiveWindow();

        if (!window)
        {
            gStarting = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ASASECImGuiStart();
            });
            return;
        }

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) { gStarting = NO; return; }

        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (!queue) { gStarting = NO; return; }

        ImGuiContext *oldContext = ImGui::GetCurrentContext();
        if (oldContext)
        {
            ImGui::SetCurrentContext(oldContext);
            ImGui_ImplMetal_Shutdown();
            ImGui::DestroyContext(oldContext);
        }

        gImGuiView = nil;
        gRenderer = nil;
        gMetalDevice = device;
        gCommandQueue = queue;

        ImGui::CreateContext();
        ImGuiContext *ctx = ImGui::GetCurrentContext();
        if (!ctx)
        {
            gCommandQueue = nil;
            gMetalDevice = nil;
            gStarting = NO;
            return;
        }

        ImGui::SetCurrentContext(ctx);
        ImGuiIO &io = ImGui::GetIO();
        io.IniFilename = NULL;
        io.LogFilename = NULL;
        io.FontGlobalScale = 1.0f;
        io.DisplaySize = ImVec2((float)window.bounds.size.width, (float)window.bounds.size.height);

        CGFloat scale = window.screen.scale;
        if (scale <= 0.0) scale = 1.0;
        io.DisplayFramebufferScale = ImVec2((float)scale, (float)scale);

        ASASECApplyStyle();

        gMenuVisible = YES;
        gMenuCollapsed = NO;
        gSelectedPage = 0;
        gPreviousPage = 0;
        gPageAnimation = 1.0f;
        gPageSlide = 0.0f;
        gDraggingMenu = NO;
        gResizingMenu = NO;
        gContentDragging = NO;

        CGRect frame = window.bounds;
        ASASECImGuiView *view = [[ASASECImGuiView alloc] initWithFrame:frame device:device];
        if (!view)
        {
            ImGui::DestroyContext();
            gCommandQueue = nil;
            gMetalDevice = nil;
            gStarting = NO;
            return;
        }

        view.backgroundColor = UIColor.clearColor;
        view.opaque = NO;
        view.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        view.depthStencilPixelFormat = MTLPixelFormatInvalid;
        view.preferredFramesPerSecond = 60;
        view.enableSetNeedsDisplay = NO;
        view.paused = NO;
        view.multipleTouchEnabled = YES;
        view.userInteractionEnabled = YES;

        ASASECImGuiRenderer *renderer = [[ASASECImGuiRenderer alloc] init];
        if (!renderer)
        {
            ImGui::DestroyContext();
            gCommandQueue = nil;
            gMetalDevice = nil;
            gStarting = NO;
            return;
        }

        if (!ImGui_ImplMetal_Init(device))
        {
            view.delegate = nil;
            ImGui::DestroyContext();
            gCommandQueue = nil;
            gMetalDevice = nil;
            gStarting = NO;
            return;
        }

        gImGuiView = view;
        gRenderer = renderer;
        view.delegate = renderer;

        [window addSubview:view];
        [window bringSubviewToFront:view];

        ASASECClampMenuToScreen(window);
        gInitialized = YES;
        gStarting = NO;
    });
}

void ASASECImGuiStop(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gInitialized && !gStarting)
            return;

        gInitialized = NO;
        gStarting = NO;

        if (gImGuiView)
        {
            gImGuiView.delegate = nil;
            gImGuiView.paused = YES;
            [gImGuiView removeFromSuperview];
            gImGuiView = nil;
        }

        ImGuiContext *ctx = ImGui::GetCurrentContext();
        if (ctx)
        {
            ImGui_ImplMetal_Shutdown();
            ImGui::DestroyContext(ctx);
        }

        gRenderer = nil;
        gCommandQueue = nil;
        gMetalDevice = nil;
        gSwitchAnimationCount = 0;
    });
}
