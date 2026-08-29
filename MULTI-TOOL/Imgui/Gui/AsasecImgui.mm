#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include "../imgui.h"
#include "../imgui_internal.h"
#include "../Backends/imgui_impl_metal.h"

#pragma mark - Global State

static MTKView *gImGuiView = nil;
static id<MTLCommandQueue> gCommandQueue = nil;
static BOOL gInitialized = NO;

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 390.0f);

static const float kMenuMinWidth = 430.0f;
static const float kMenuMaxWidth = 760.0f;
static const float kMenuMinHeight = 300.0f;
static const float kMenuMaxHeight = 620.0f;

static const float kHeaderHeight = 54.0f;
static const float kResizeSize = 42.0f;

static int gSelectedPage = 0;

static BOOL gDraggingMenu = NO;
static BOOL gResizingMenu = NO;

static CGPoint gDragStartPoint = CGPointZero;
static CGPoint gResizeStartPoint = CGPointZero;

static ImVec2 gDragStartPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gResizeStartSize = ImVec2(560.0f, 390.0f);

#pragma mark - Helpers

static float ASASECClampFloat(float value, float minValue, float maxValue)
{
    if (value < minValue)
        return minValue;

    if (value > maxValue)
        return maxValue;

    return value;
}

static void ASASECClampMenuToScreen(UIWindow *window)
{
    if (!window)
        return;

    CGSize screenSize = window.bounds.size;

    float width = gMenuSize.x;

    float height = gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    const float margin = 8.0f;

    float maxX =
        (float)screenSize.width -
        width -
        margin;

    float maxY =
        (float)screenSize.height -
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

static ImU32 ASASECColor(float r, float g, float b, float a)
{
    return ImGui::ColorConvertFloat4ToU32(
        ImVec4(r, g, b, a)
    );
}

#pragma mark - Modern Switch

static bool ASASECModernSwitch(const char *label, bool *value)
{
    if (!value)
        return false;

    ImGui::PushID(label);

    float width = 48.0f;
    float height = 27.0f;

    ImVec2 start =
        ImGui::GetCursorScreenPos();

    ImVec2 total =
        ImGui::GetContentRegionAvail();

    float labelWidth =
        ImGui::CalcTextSize(label).x;

    float totalWidth =
        total.x > 0.0f
        ? total.x
        : 250.0f;

    if (totalWidth < labelWidth + width + 28.0f)
        totalWidth = labelWidth + width + 28.0f;

    ImVec2 itemSize =
        ImVec2(totalWidth, 40.0f);

    bool clicked =
        ImGui::InvisibleButton(
            "##switch",
            itemSize
        );

    if (clicked)
    {
        *value = !(*value);
    }

    ImVec2 itemMin =
        ImGui::GetItemRectMin();

    ImVec2 itemMax =
        ImGui::GetItemRectMax();

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    float switchX =
        itemMax.x - width - 4.0f;

    float switchY =
        itemMin.y + (itemSize.y - height) * 0.5f;

    ImVec2 switchMin =
        ImVec2(
            switchX,
            switchY
        );

    ImVec2 switchMax =
        ImVec2(
            switchX + width,
            switchY + height
        );

    bool hovered =
        ImGui::IsItemHovered();

    ImU32 background;

    if (*value)
    {
        background =
            ASASECColor(
                hovered ? 0.24f : 0.18f,
                hovered ? 0.62f : 0.52f,
                1.0f,
                1.0f
            );
    }
    else
    {
        background =
            ASASECColor(
                hovered ? 0.15f : 0.09f,
                hovered ? 0.19f : 0.13f,
                hovered ? 0.27f : 0.19f,
                1.0f
            );
    }

    draw->AddRectFilled(
        switchMin,
        switchMax,
        background,
        height * 0.5f
    );

    if (*value)
    {
        draw->AddRect(
            ImVec2(
                switchMin.x + 0.5f,
                switchMin.y + 0.5f
            ),
            ImVec2(
                switchMax.x - 0.5f,
                switchMax.y - 0.5f
            ),
            ASASECColor(
                0.45f,
                0.75f,
                1.0f,
                0.75f
            ),
            height * 0.5f,
            0,
            1.0f
        );
    }
    else
    {
        draw->AddRect(
            ImVec2(
                switchMin.x + 0.5f,
                switchMin.y + 0.5f
            ),
            ImVec2(
                switchMax.x - 0.5f,
                switchMax.y - 0.5f
            ),
            ASASECColor(
                0.22f,
                0.27f,
                0.36f,
                0.90f
            ),
            height * 0.5f,
            0,
            1.0f
        );
    }

    float knobRadius = 9.0f;

    float knobX =
        *value
        ? switchMax.x - 14.0f
        : switchMin.x + 14.0f;

    float knobY =
        switchMin.y + height * 0.5f;

    draw->AddCircleFilled(
        ImVec2(knobX, knobY),
        knobRadius + 1.0f,
        ASASECColor(
            0.0f,
            0.0f,
            0.0f,
            0.18f
        )
    );

    draw->AddCircleFilled(
        ImVec2(knobX, knobY),
        knobRadius,
        ASASECColor(
            0.94f,
            0.97f,
            1.0f,
            1.0f
        )
    );

    ImGui::SetCursorScreenPos(
        ImVec2(
            itemMin.x,
            itemMin.y + 8.0f
        )
    );

    ImGui::TextColored(
        ImVec4(
            0.88f,
            0.92f,
            0.98f,
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

#pragma mark Hit Testing

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    float width =
        gMenuSize.x;

    float height =
        gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    return
        point.x >= gMenuPosition.x &&
        point.x <= gMenuPosition.x + width &&
        point.y >= gMenuPosition.y &&
        point.y <= gMenuPosition.y + height;
}

- (BOOL)pointInsideResizeHandle:(CGPoint)point
{
    if (!gMenuVisible || gMenuCollapsed)
        return NO;

    float right =
        gMenuPosition.x + gMenuSize.x;

    float bottom =
        gMenuPosition.y + gMenuSize.y;

    return
        point.x >= right - kResizeSize &&
        point.x <= right + 6.0f &&
        point.y >= bottom - kResizeSize &&
        point.y <= bottom + 6.0f;
}

- (BOOL)pointInsideDragHeader:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    return
        point.x >= gMenuPosition.x &&
        point.x <= gMenuPosition.x + gMenuSize.x &&
        point.y >= gMenuPosition.y &&
        point.y <= gMenuPosition.y + kHeaderHeight;
}

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return nil;

    if (!gMenuVisible)
        return nil;

    if ([self pointInsideMenu:point])
        return self;

    return nil;
}

#pragma mark Menu Drag

- (void)beginMenuDragAtPoint:(CGPoint)point
{
    gDraggingMenu = YES;
    gResizingMenu = NO;

    gDragStartPoint = point;
    gDragStartPosition = gMenuPosition;
}

- (void)updateMenuDragAtPoint:(CGPoint)point
{
    if (!gDraggingMenu)
        return;

    CGFloat dx =
        point.x - gDragStartPoint.x;

    CGFloat dy =
        point.y - gDragStartPoint.y;

    gMenuPosition.x =
        gDragStartPosition.x + (float)dx;

    gMenuPosition.y =
        gDragStartPosition.y + (float)dy;

    [self clampMenuPosition];
}

#pragma mark Menu Resize

- (void)beginMenuResizeAtPoint:(CGPoint)point
{
    if (gMenuCollapsed)
        return;

    gResizingMenu = YES;
    gDraggingMenu = NO;

    gResizeStartPoint = point;
    gResizeStartSize = gMenuSize;
}

- (void)updateMenuResizeAtPoint:(CGPoint)point
{
    if (!gResizingMenu)
        return;

    CGFloat dx =
        point.x - gResizeStartPoint.x;

    CGFloat dy =
        point.y - gResizeStartPoint.y;

    float newWidth =
        gResizeStartSize.x + (float)dx;

    float newHeight =
        gResizeStartSize.y + (float)dy;

    newWidth =
        ASASECClampFloat(
            newWidth,
            kMenuMinWidth,
            kMenuMaxWidth
        );

    newHeight =
        ASASECClampFloat(
            newHeight,
            kMenuMinHeight,
            kMenuMaxHeight
        );

    UIWindow *window =
        self.window;

    if (window)
    {
        CGSize screenSize =
            window.bounds.size;

        float availableWidth =
            (float)screenSize.width -
            gMenuPosition.x -
            8.0f;

        float availableHeight =
            (float)screenSize.height -
            gMenuPosition.y -
            8.0f;

        if (availableWidth < kMenuMinWidth)
            availableWidth = kMenuMinWidth;

        if (availableHeight < kMenuMinHeight)
            availableHeight = kMenuMinHeight;

        newWidth =
            MIN(
                newWidth,
                availableWidth
            );

        newHeight =
            MIN(
                newHeight,
                availableHeight
            );
    }

    gMenuSize.x =
        newWidth;

    gMenuSize.y =
        newHeight;
}

#pragma mark Interaction End

- (void)endMenuInteraction
{
    gDraggingMenu = NO;
    gResizingMenu = NO;
}

#pragma mark Clamp

- (void)clampMenuPosition
{
    UIWindow *window =
        self.window;

    if (!window)
        return;

    ASASECClampMenuToScreen(window);
}

#pragma mark Touch -> ImGui

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    UITouch *touch =
        event.allTouches.anyObject;

    if (!touch)
        return;

    CGPoint point =
        [touch locationInView:self];

    ImGuiIO &io =
        ImGui::GetIO();

    io.MousePos =
        ImVec2(
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

    io.MouseDown[0] =
        touching;
}

#pragma mark Touches

- (void)touchesBegan:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    UITouch *touch =
        touches.anyObject;

    if (touch)
    {
        CGPoint point =
            [touch locationInView:self];

        if ([self pointInsideResizeHandle:point])
        {
            [self beginMenuResizeAtPoint:point];
        }
        else if ([self pointInsideDragHeader:point])
        {
            [self beginMenuDragAtPoint:point];
        }
    }

    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    UITouch *touch =
        touches.anyObject;

    if (touch)
    {
        CGPoint point =
            [touch locationInView:self];

        if (gResizingMenu)
        {
            [self updateMenuResizeAtPoint:point];
        }
        else if (gDraggingMenu)
        {
            [self updateMenuDragAtPoint:point];
        }
    }

    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self endMenuInteraction];

    [self updateIOWithTouchEvent:event];

    ImGuiIO &io =
        ImGui::GetIO();

    io.MouseDown[0] = false;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    [self endMenuInteraction];

    [self updateIOWithTouchEvent:event];

    ImGuiIO &io =
        ImGui::GetIO();

    io.MouseDown[0] = false;
}

@end

#pragma mark - Renderer

@interface ASASECImGuiRenderer : NSObject <MTKViewDelegate>
@end

@implementation ASASECImGuiRenderer

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    if (!gInitialized)
        return;

    ImGuiIO &io =
        ImGui::GetIO();

    io.DisplaySize =
        ImVec2(
            (float)view.bounds.size.width,
            (float)view.bounds.size.height
        );

    io.DisplayFramebufferScale =
        ImVec2(
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

    ImGuiIO &io =
        ImGui::GetIO();

    io.DisplaySize =
        ImVec2(
            (float)view.bounds.size.width,
            (float)view.bounds.size.height
        );

    io.DisplayFramebufferScale =
        ImVec2(
            view.contentScaleFactor,
            view.contentScaleFactor
        );

    float fps =
        (float)view.preferredFramesPerSecond;

    if (fps <= 0.0f)
        fps = 60.0f;

    io.DeltaTime =
        1.0f / fps;

    ImGui::NewFrame();

    if (gMenuVisible)
    {
        const float sidebarWidth = 145.0f;

        float windowHeight =
            gMenuCollapsed
            ? kHeaderHeight
            : gMenuSize.y;

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
            ImGuiWindowFlags_NoSavedSettings;

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowPadding,
            ImVec2(0.0f, 0.0f)
        );

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowRounding,
            20.0f
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

        ImGui::Begin(
            "##ASASEC_WINDOW",
            NULL,
            flags
        );

        ImVec2 windowPos =
            ImGui::GetWindowPos();

        ImVec2 windowSize =
            ImGui::GetWindowSize();

        ImDrawList *draw =
            ImGui::GetWindowDrawList();

        ImVec2 windowEnd =
            ImVec2(
                windowPos.x + windowSize.x,
                windowPos.y + windowSize.y
            );

        draw->AddRectFilled(
            windowPos,
            windowEnd,
            IM_COL32(6, 9, 16, 252),
            20.0f
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
            IM_COL32(42, 53, 73, 190),
            20.0f,
            0,
            1.0f
        );

        if (gMenuCollapsed)
        {
            draw->AddRectFilled(
                windowPos,
                ImVec2(
                    windowEnd.x,
                    windowPos.y + kHeaderHeight
                ),
                IM_COL32(10, 15, 25, 255),
                20.0f,
                ImDrawFlags_RoundCornersAll
            );

            draw->AddLine(
                ImVec2(
                    windowPos.x + 18.0f,
                    windowPos.y + kHeaderHeight - 2.0f
                ),
                ImVec2(
                    windowEnd.x - 18.0f,
                    windowPos.y + kHeaderHeight - 2.0f
                ),
                IM_COL32(48, 112, 205, 170),
                1.0f
            );

            ImGui::SetCursorPos(
                ImVec2(18.0f, 9.0f)
            );

            ImGui::TextColored(
                ImVec4(
                    0.30f,
                    0.68f,
                    1.0f,
                    1.0f
                ),
                "ASASEC"
            );

            ImGui::SameLine(
                0.0f,
                6.0f
            );

            ImGui::TextColored(
                ImVec4(
                    0.43f,
                    0.49f,
                    0.59f,
                    1.0f
                ),
                "CONTROL"
            );

            float buttonX =
                windowSize.x - 72.0f;

            ImGui::SetCursorPos(
                ImVec2(
                    buttonX,
                    10.0f
                )
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                9.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.07f,
                    0.11f,
                    0.18f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.12f,
                    0.20f,
                    0.32f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.17f,
                    0.28f,
                    0.44f,
                    1.0f
                )
            );

            if (ImGui::Button(
                "+",
                ImVec2(28.0f, 32.0f)
            ))
            {
                gMenuCollapsed = NO;

                UIWindow *window =
                    view.window;

                if (window)
                    ASASECClampMenuToScreen(window);
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();

            ImGui::SameLine(
                0.0f,
                6.0f
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                9.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.32f,
                    0.055f,
                    0.085f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.55f,
                    0.09f,
                    0.14f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.70f,
                    0.13f,
                    0.19f,
                    1.0f
                )
            );

            if (ImGui::Button(
                "x",
                ImVec2(28.0f, 32.0f)
            ))
            {
                gMenuVisible = NO;
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
        }
        else
        {
            #pragma mark Sidebar

            draw->AddRectFilled(
                windowPos,
                ImVec2(
                    windowPos.x + sidebarWidth,
                    windowEnd.y
                ),
                IM_COL32(9, 14, 24, 255),
                20.0f,
                ImDrawFlags_RoundCornersLeft
            );

            draw->AddLine(
                ImVec2(
                    windowPos.x + sidebarWidth,
                    windowPos.y + 16.0f
                ),
                ImVec2(
                    windowPos.x + sidebarWidth,
                    windowEnd.y - 16.0f
                ),
                IM_COL32(34, 43, 59, 210),
                1.0f
            );

            ImGui::SetCursorPos(
                ImVec2(18.0f, 13.0f)
            );

            ImGui::TextColored(
                ImVec4(
                    0.30f,
                    0.68f,
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
                    0.46f,
                    0.51f,
                    0.60f,
                    1.0f
                ),
                "UI"
            );

            ImGui::SetCursorPos(
                ImVec2(18.0f, 36.0f)
            );

            ImGui::TextColored(
                ImVec4(
                    0.27f,
                    0.32f,
                    0.40f,
                    1.0f
                ),
                "CONTROL CENTER"
            );

            draw->AddLine(
                ImVec2(
                    windowPos.x + 18.0f,
                    windowPos.y + 57.0f
                ),
                ImVec2(
                    windowPos.x + sidebarWidth - 18.0f,
                    windowPos.y + 57.0f
                ),
                IM_COL32(35, 44, 60, 190),
                1.0f
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
                    72.0f + i * 53.0f;

                if (active)
                {
                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x + 9.0f,
                            windowPos.y + itemY
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth - 9.0f,
                            windowPos.y +
                            itemY + 42.0f
                        ),
                        IM_COL32(19, 48, 84, 255),
                        11.0f
                    );

                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x + 9.0f,
                            windowPos.y + itemY + 9.0f
                        ),
                        ImVec2(
                            windowPos.x + 12.0f,
                            windowPos.y + itemY + 33.0f
                        ),
                        IM_COL32(75, 153, 255, 255),
                        2.0f
                    );
                }

                char id[64];

                snprintf(
                    id,
                    sizeof(id),
                    "%s  %s##page_%d",
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
                        sidebarWidth - 20.0f,
                        42.0f
                    )
                ))
                {
                    gSelectedPage = i;
                }

                ImGui::PopStyleColor(3);
                ImGui::PopStyleVar();
            }

            #pragma mark Content Area

            ImGui::SetCursorPos(
                ImVec2(
                    sidebarWidth + 1.0f,
                    0.0f
                )
            );

            float contentWidth =
                windowSize.x -
                sidebarWidth -
                1.0f;

            float contentHeight =
                windowSize.y;

            ImGui::BeginChild(
                "##ContentRoot",
                ImVec2(
                    contentWidth,
                    contentHeight
                ),
                false,
                ImGuiWindowFlags_NoBackground
            );

            #pragma mark Header

            ImGui::SetCursorPos(
                ImVec2(15.0f, 9.0f)
            );

            ImGui::TextColored(
                ImVec4(
                    0.94f,
                    0.97f,
                    1.0f,
                    1.0f
                ),
                "%s",
                pages[gSelectedPage]
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

            float controlX =
                contentWidth - 73.0f;

            ImGui::SetCursorPos(
                ImVec2(
                    controlX,
                    8.0f
                )
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                9.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.065f,
                    0.095f,
                    0.15f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.12f,
                    0.18f,
                    0.28f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.17f,
                    0.26f,
                    0.40f,
                    1.0f
                )
            );

            if (ImGui::Button(
                "v",
                ImVec2(28.0f, 32.0f)
            ))
            {
                gMenuCollapsed = YES;

                UIWindow *window =
                    view.window;

                if (window)
                    ASASECClampMenuToScreen(window);
            }

            ImGui::PopStyleColor(2);
            ImGui::PopStyleVar();

            ImGui::SameLine(
                0.0f,
                6.0f
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                9.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.32f,
                    0.055f,
                    0.085f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.55f,
                    0.09f,
                    0.14f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.70f,
                    0.13f,
                    0.19f,
                    1.0f
                )
            );

            if (ImGui::Button(
                "x",
                ImVec2(28.0f, 32.0f)
            ))
            {
                gMenuVisible = NO;
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();

            draw->AddLine(
                ImVec2(
                    windowPos.x + sidebarWidth + 16.0f,
                    windowPos.y + 51.0f
                ),
                ImVec2(
                    windowEnd.x - 16.0f,
                    windowPos.y + 51.0f
                ),
                IM_COL32(32, 41, 56, 220),
                1.0f
            );

            #pragma mark Internal Scroll Area

            ImGui::SetCursorPos(
                ImVec2(
                    0.0f,
                    60.0f
                )
            );

            float scrollHeight =
                contentHeight - 60.0f;

            if (scrollHeight < 100.0f)
                scrollHeight = 100.0f;

            ImGui::BeginChild(
                "##ScrollableContent",
                ImVec2(
                    contentWidth,
                    scrollHeight
                ),
                false,
                ImGuiWindowFlags_AlwaysVerticalScrollbar
            );

            ImGui::SetCursorPosX(
                15.0f
            );

            #pragma mark Combat

            if (gSelectedPage == 0)
            {
                ImGui::TextColored(
                    ImVec4(
                        0.30f,
                        0.68f,
                        1.0f,
                        1.0f
                    ),
                    "COMBAT"
                );

                ImGui::SameLine(
                    0.0f,
                    6.0f
                );

                ImGui::TextColored(
                    ImVec4(
                        0.34f,
                        0.39f,
                        0.48f,
                        1.0f
                    ),
                    "ACTIONS"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.43f,
                        0.47f,
                        0.55f,
                        1.0f
                    ),
                    "Configure your combat options"
                );

                ImGui::Spacing();

                static bool aimbot = false;
                static bool esp = true;
                static bool autoFire = false;
                static bool silentAim = false;
                static float fov = 90.0f;

                ImGui::BeginChild(
                    "##CombatCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        315.0f
                    ),
                    true
                );

                ImGui::TextColored(
                    ImVec4(
                        0.93f,
                        0.96f,
                        1.0f,
                        1.0f
                    ),
                    "Combat Features"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.37f,
                        0.42f,
                        0.50f,
                        1.0f
                    ),
                    "Main configuration"
                );

                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();

                ASASECModernSwitch(
                    "Enable Aimbot",
                    &aimbot
                );

                ASASECModernSwitch(
                    "Box ESP",
                    &esp
                );

                ASASECModernSwitch(
                    "Auto Fire",
                    &autoFire
                );

                ASASECModernSwitch(
                    "Silent Aim",
                    &silentAim
                );

                ImGui::Spacing();

                ImGui::TextColored(
                    ImVec4(
                        0.80f,
                        0.84f,
                        0.91f,
                        1.0f
                    ),
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
                    "Reset Defaults",
                    ImVec2(130.0f, 36.0f)
                ))
                {
                    aimbot = false;
                    esp = true;
                    autoFire = false;
                    silentAim = false;
                    fov = 90.0f;
                }

                ImGui::EndChild();

                ImGui::Spacing();

                ImGui::BeginChild(
                    "##CombatExtra",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        220.0f
                    ),
                    true
                );

                ImGui::TextColored(
                    ImVec4(
                        0.93f,
                        0.96f,
                        1.0f,
                        1.0f
                    ),
                    "Advanced"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.37f,
                        0.42f,
                        0.50f,
                        1.0f
                    ),
                    "Additional options"
                );

                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();

                static bool targetLock = false;
                static bool prediction = false;
                static bool visibilityCheck = true;

                ASASECModernSwitch(
                    "Target Lock",
                    &targetLock
                );

                ASASECModernSwitch(
                    "Prediction",
                    &prediction
                );

                ASASECModernSwitch(
                    "Visibility Check",
                    &visibilityCheck
                );

                ImGui::EndChild();
            }

            #pragma mark Visuals

            else if (gSelectedPage == 1)
            {
                ImGui::TextColored(
                    ImVec4(
                        0.28f,
                        0.86f,
                        0.58f,
                        1.0f
                    ),
                    "VISUALS"
                );

                ImGui::SameLine(
                    0.0f,
                    6.0f
                );

                ImGui::TextColored(
                    ImVec4(
                        0.34f,
                        0.39f,
                        0.48f,
                        1.0f
                    ),
                    "ESP"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.43f,
                        0.47f,
                        0.55f,
                        1.0f
                    ),
                    "Configure visual options"
                );

                ImGui::Spacing();

                static bool playerESP = true;
                static bool healthBar = true;
                static bool wallhack = false;
                static bool nameTags = true;
                static bool distance = true;

                ImGui::BeginChild(
                    "##VisualCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        315.0f
                    ),
                    true
                );

                ImGui::TextColored(
                    ImVec4(
                        0.93f,
                        0.96f,
                        1.0f,
                        1.0f
                    ),
                    "ESP Features"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.37f,
                        0.42f,
                        0.50f,
                        1.0f
                    ),
                    "Visual configuration"
                );

                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();

                ASASECModernSwitch(
                    "Player ESP",
                    &playerESP
                );

                ASASECModernSwitch(
                    "Health Bar",
                    &healthBar
                );

                ASASECModernSwitch(
                    "Wallhack",
                    &wallhack
                );

                ASASECModernSwitch(
                    "Name Tags",
                    &nameTags
                );

                ASASECModernSwitch(
                    "Distance",
                    &distance
                );

                ImGui::EndChild();

                ImGui::Spacing();

                ImGui::BeginChild(
                    "##VisualExtra",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        240.0f
                    ),
                    true
                );

                ImGui::TextColored(
                    ImVec4(
                        0.93f,
                        0.96f,
                        1.0f,
                        1.0f
                    ),
                    "Visual Style"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.37f,
                        0.42f,
                        0.50f,
                        1.0f
                    ),
                    "Overlay configuration"
                );

                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();

                static bool glow = false;
                static bool skeleton = false;
                static bool snapLines = false;

                ASASECModernSwitch(
                    "Glow",
                    &glow
                );

                ASASECModernSwitch(
                    "Skeleton",
                    &skeleton
                );

                ASASECModernSwitch(
                    "Snap Lines",
                    &snapLines
                );

                ImGui::EndChild();
            }

            #pragma mark Settings

            else
            {
                ImGui::TextColored(
                    ImVec4(
                        1.0f,
                        0.67f,
                        0.28f,
                        1.0f
                    ),
                    "SETTINGS"
                );

                ImGui::SameLine(
                    0.0f,
                    6.0f
                );

                ImGui::TextColored(
                    ImVec4(
                        0.34f,
                        0.39f,
                        0.48f,
                        1.0f
                    ),
                    "SYSTEM"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.43f,
                        0.47f,
                        0.55f,
                        1.0f
                    ),
                    "ASASEC configuration"
                );

                ImGui::Spacing();

                ImGui::BeginChild(
                    "##SettingsCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        330.0f
                    ),
                    true
                );

                ImGui::TextColored(
                    ImVec4(
                        0.93f,
                        0.96f,
                        1.0f,
                        1.0f
                    ),
                    "Application"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.37f,
                        0.42f,
                        0.50f,
                        1.0f
                    ),
                    "Runtime information"
                );

                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();

                ImGui::Text(
                    "Version"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 55.0f
                );

                ImGui::TextColored(
                    ImVec4(
                        0.30f,
                        0.68f,
                        1.0f,
                        1.0f
                    ),
                    "3.1"
                );

                ImGui::Spacing();

                ImGui::Text(
                    "Renderer"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 55.0f
                );

                ImGui::Text(
                    "Metal"
                );

                ImGui::Spacing();

                ImGui::Text(
                    "Status"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 55.0f
                );

                ImGui::TextColored(
                    ImVec4(
                        0.30f,
                        0.88f,
                        0.56f,
                        1.0f
                    ),
                    "ACTIVE"
                );

                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();

                static bool animations = true;
                static bool haptics = true;
                static bool compactMode = false;

                ASASECModernSwitch(
                    "Animations",
                    &animations
                );

                ASASECModernSwitch(
                    "Haptic Feedback",
                    &haptics
                );

                ASASECModernSwitch(
                    "Compact Mode",
                    &compactMode
                );

                ImGui::EndChild();

                ImGui::Spacing();

                ImGui::BeginChild(
                    "##InfoCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        210.0f
                    ),
                    true
                );

                ImGui::TextColored(
                    ImVec4(
                        0.93f,
                        0.96f,
                        1.0f,
                        1.0f
                    ),
                    "Interface"
                );

                ImGui::TextColored(
                    ImVec4(
                        0.37f,
                        0.42f,
                        0.50f,
                        1.0f
                    ),
                    "Display configuration"
                );

                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();

                ImGui::TextWrapped(
                    "Use the internal scroll area to navigate through the menu. The lower-right handle controls the menu size."
                );

                ImGui::EndChild();
            }

            ImGui::Spacing();

            ImGui::EndChild();

            #pragma mark Modern Resize Handle

            if (windowSize.x > 300.0f &&
                windowSize.y > 220.0f)
            {
                float right =
                    windowSize.x - 8.0f;

                float bottom =
                    windowSize.y - 8.0f;

                ImVec2 origin =
                    ImVec2(
                        windowPos.x + right - 26.0f,
                        windowPos.y + bottom - 26.0f
                    );

                ImU32 handleColor =
                    gResizingMenu
                    ? ASASECColor(
                        0.45f,
                        0.73f,
                        1.0f,
                        0.95f
                    )
                    : ASASECColor(
                        0.82f,
                        0.85f,
                        0.90f,
                        0.45f
                    );

                float thickness =
                    gResizingMenu
                    ? 2.6f
                    : 2.0f;

                draw->AddLine(
                    ImVec2(
                        origin.x + 5.0f,
                        origin.y + 20.0f
                    ),
                    ImVec2(
                        origin.x + 20.0f,
                        origin.y + 20.0f
                    ),
                    handleColor,
                    thickness
                );

                draw->AddLine(
                    ImVec2(
                        origin.x + 11.0f,
                        origin.y + 14.0f
                    ),
                    ImVec2(
                        origin.x + 20.0f,
                        origin.y + 14.0f
                    ),
                    handleColor,
                    thickness
                );

                draw->AddLine(
                    ImVec2(
                        origin.x + 17.0f,
                        origin.y + 8.0f
                    ),
                    ImVec2(
                        origin.x + 20.0f,
                        origin.y + 8.0f
                    ),
                    handleColor,
                    thickness
                );

                draw->AddLine(
                    ImVec2(
                        origin.x + 20.0f,
                        origin.y + 8.0f
                    ),
                    ImVec2(
                        origin.x + 20.0f,
                        origin.y + 20.0f
                    ),
                    handleColor,
                    thickness
                );

                draw->AddCircleFilled(
                    ImVec2(
                        origin.x + 20.0f,
                        origin.y + 20.0f
                    ),
                    2.0f,
                    handleColor
                );
            }

            ImGui::EndChild();
        }

        ImGui::End();

        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);
    }

    ImGui::Render();

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer
         renderCommandEncoderWithDescriptor:pass];

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

#pragma mark - Renderer Instance

static ASASECImGuiRenderer *gRenderer = nil;

#pragma mark - Style

static void ASASECApplyStyle(void)
{
    ImGuiStyle &style =
        ImGui::GetStyle();

    style.WindowPadding =
        ImVec2(10.0f, 10.0f);

    style.FramePadding =
        ImVec2(11.0f, 8.0f);

    style.ItemSpacing =
        ImVec2(9.0f, 9.0f);

    style.ItemInnerSpacing =
        ImVec2(7.0f, 6.0f);

    style.ScrollbarSize =
        9.0f;

    style.GrabMinSize =
        15.0f;

    style.WindowRounding =
        20.0f;

    style.ChildRounding =
        14.0f;

    style.FrameRounding =
        9.0f;

    style.PopupRounding =
        11.0f;

    style.ScrollbarRounding =
        8.0f;

    style.GrabRounding =
        8.0f;

    style.TabRounding =
        9.0f;

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

    c[ImGuiCol_ScrollbarBg] =
        ImVec4(
            0.020f,
            0.027f,
            0.042f,
            0.90f
        );

    c[ImGuiCol_ScrollbarGrab] =
        ImVec4(
            0.17f,
            0.23f,
            0.33f,
            1.0f
        );

    c[ImGuiCol_ScrollbarGrabHovered] =
        ImVec4(
            0.23f,
            0.32f,
            0.46f,
            1.0f
        );

    c[ImGuiCol_ScrollbarGrabActive] =
        ImVec4(
            0.28f,
            0.42f,
            0.60f,
            1.0f
        );
}

#pragma mark - Start

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
            {
                for (UIScene *scene
                     in UIApplication.sharedApplication.connectedScenes)
                {
                    if (![scene isKindOfClass:
                         [UIWindowScene class]])
                        continue;

                    UIWindowScene *windowScene =
                        (UIWindowScene *)scene;

                    if (windowScene.windows.count > 0)
                    {
                        window =
                            windowScene.windows.firstObject;

                        if (window)
                            break;
                    }
                }
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
                    (float)window.bounds.size.width,
                    (float)window.bounds.size.height
                );

            CGFloat scale =
                window.screen.scale;

            if (scale <= 0.0)
                scale = 1.0;

            io.DisplayFramebufferScale =
                ImVec2(
                    (float)scale,
                    (float)scale
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

            gInitialized = YES;
        }
    );
}

#pragma mark - Stop

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

            gDraggingMenu = NO;
            gResizingMenu = NO;

            gDragStartPoint =
                CGPointZero;

            gResizeStartPoint =
                CGPointZero;

            gMenuPosition =
                ImVec2(
                    25.0f,
                    75.0f
                );

            gDragStartPosition =
                gMenuPosition;

            gResizeStartSize =
                ImVec2(
                    560.0f,
                    390.0f
                );

            gMenuSize =
                ImVec2(
                    560.0f,
                    390.0f
                );
        }
    );
}
