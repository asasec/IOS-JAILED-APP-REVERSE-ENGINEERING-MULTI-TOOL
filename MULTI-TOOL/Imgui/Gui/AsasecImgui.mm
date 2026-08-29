#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
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

static const float kMenuMinWidth  = 430.0f;
static const float kMenuMaxWidth  = 760.0f;
static const float kMenuMinHeight = 300.0f;
static const float kMenuMaxHeight = 620.0f;

static const float kHeaderHeight = 54.0f;
static const float kResizeSize = 34.0f;

static int gSelectedPage = 0;

static BOOL gDraggingMenu = NO;
static BOOL gResizingMenu = NO;

static CGPoint gDragStartPoint = CGPointZero;
static CGPoint gResizeStartPoint = CGPointZero;

static ImVec2 gDragStartPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gResizeStartSize = ImVec2(560.0f, 390.0f);

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

static void ASASECClampMenuToScreen(UIWindow *window)
{
    if (!window)
        return;

    CGSize screenSize = window.bounds.size;

    float width = gMenuSize.x;

    float height =
        gMenuCollapsed
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

#pragma mark - Modern Switch

static BOOL ASASECSwitch(const char *label,
                         bool *value,
                         const ImVec2 &size = ImVec2(48.0f, 27.0f))
{
    if (!value)
        return NO;

    ImGui::PushID(label);

    ImVec2 cursor =
        ImGui::GetCursorScreenPos();

    float width = size.x;
    float height = size.y;

    ImGui::InvisibleButton(
        "##switch",
        size
    );

    bool hovered =
        ImGui::IsItemHovered();

    bool clicked =
        ImGui::IsItemClicked();

    if (clicked)
        *value = !*value;

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    ImVec2 min =
        cursor;

    ImVec2 max =
        ImVec2(
            cursor.x + width,
            cursor.y + height
        );

    ImU32 background;

    if (*value)
    {
        background =
            IM_COL32(
                54,
                130,
                225,
                hovered ? 255 : 235
            );
    }
    else
    {
        background =
            IM_COL32(
                48,
                58,
                75,
                hovered ? 255 : 225
            );
    }

    draw->AddRectFilled(
        min,
        max,
        background,
        height * 0.5f
    );

    if (!*value)
    {
        draw->AddRect(
            min,
            max,
            IM_COL32(
                93,
                105,
                125,
                110
            ),
            height * 0.5f,
            0,
            1.0f
        );
    }

    float radius =
        height * 0.5f - 4.0f;

    float knobX =
        *value
        ? max.x - radius - 4.0f
        : min.x + radius + 4.0f;

    ImVec2 knobCenter =
        ImVec2(
            knobX,
            min.y + height * 0.5f
        );

    draw->AddCircleFilled(
        knobCenter,
        radius,
        IM_COL32(
            245,
            248,
            252,
            255
        ),
        24
    );

    if (*value)
    {
        draw->AddCircle(
            knobCenter,
            radius,
            IM_COL32(
                255,
                255,
                255,
                80
            ),
            24,
            1.0f
        );
    }

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

    float width =
        gMenuSize.x;

    return
        point.x >= gMenuPosition.x &&
        point.x <= gMenuPosition.x + width &&
        point.y >= gMenuPosition.y &&
        point.y <= gMenuPosition.y + kHeaderHeight;
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

    gMenuSize.x = newWidth;
    gMenuSize.y = newHeight;
}

- (void)endMenuInteraction
{
    gDraggingMenu = NO;
    gResizingMenu = NO;
}

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
            ImGuiWindowFlags_NoScrollbar |
            ImGuiWindowFlags_NoScrollWithMouse |
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

        #pragma mark Background

        draw->AddRectFilled(
            windowPos,
            windowEnd,
            IM_COL32(
                6,
                9,
                16,
                252
            ),
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
            IM_COL32(
                46,
                60,
                82,
                190
            ),
            20.0f,
            0,
            1.0f
        );

        #pragma mark Collapsed

        if (gMenuCollapsed)
        {
            draw->AddRectFilled(
                windowPos,
                windowEnd,
                IM_COL32(
                    9,
                    14,
                    24,
                    255
                ),
                20.0f
            );

            draw->AddLine(
                ImVec2(
                    windowPos.x + 18.0f,
                    windowEnd.y - 1.5f
                ),
                ImVec2(
                    windowEnd.x - 18.0f,
                    windowEnd.y - 1.5f
                ),
                IM_COL32(
                    52,
                    119,
                    210,
                    180
                ),
                1.0f
            );

            ImGui::SetCursorPos(
                ImVec2(
                    18.0f,
                    9.0f
                )
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
                    9.0f
                )
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                14.0f
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
                "⌃",
                ImVec2(
                    28.0f,
                    34.0f
                )
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
                14.0f
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
                "×",
                ImVec2(
                    28.0f,
                    34.0f
                )
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
                IM_COL32(
                    9,
                    14,
                    24,
                    255
                ),
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
                IM_COL32(
                    34,
                    43,
                    59,
                    210
                ),
                1.0f
            );

            #pragma mark Logo

            ImGui::SetCursorPos(
                ImVec2(
                    18.0f,
                    13.0f
                )
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
                IM_COL32(
                    35,
                    44,
                    60,
                    190
                ),
                1.0f
            );

            #pragma mark Navigation

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
                        IM_COL32(
                            19,
                            48,
                            84,
                            255
                        ),
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
                        IM_COL32(
                            75,
                            153,
                            255,
                            255
                        ),
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

            #pragma mark Content

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
                ImGuiWindowFlags_NoScrollWithMouse
            );

            #pragma mark Content Header

            ImGui::SetCursorPos(
                ImVec2(
                    15.0f,
                    9.0f
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

            #pragma mark Header Buttons

            ImGui::SetCursorPos(
                ImVec2(
                    windowSize.x -
                    sidebarWidth -
                    70.0f,
                    8.0f
                )
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                13.0f
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
                    0.27f,
                    0.42f,
                    1.0f
                )
            );

            if (ImGui::Button(
                "⌄",
                ImVec2(
                    28.0f,
                    34.0f
                )
            ))
            {
                gMenuCollapsed = YES;

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
                13.0f
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
                "×",
                ImVec2(
                    28.0f,
                    34.0f
                )
            ))
            {
                gMenuVisible = NO;
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();

            draw->AddLine(
                ImVec2(
                    windowPos.x +
                    sidebarWidth +
                    16.0f,
                    windowPos.y + 51.0f
                ),
                ImVec2(
                    windowEnd.x - 16.0f,
                    windowPos.y + 51.0f
                ),
                IM_COL32(
                    32,
                    41,
                    56,
                    220
                ),
                1.0f
            );

            ImGui::SetCursorPosY(
                69.0f
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
                static float fov = 90.0f;

                ImGui::BeginChild(
                    "##CombatCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        285.0f
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

                ImGui::Text(
                    "Enable Aimbot"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 49.0f
                );

                ASASECSwitch(
                    "Aimbot",
                    &aimbot
                );

                ImGui::Spacing();

                ImGui::Text(
                    "Box ESP"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 49.0f
                );

                ASASECSwitch(
                    "ESP",
                    &esp
                );

                ImGui::Spacing();

                ImGui::Text(
                    "Auto Fire"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 49.0f
                );

                ASASECSwitch(
                    "AutoFire",
                    &autoFire
                );

                ImGui::Spacing();
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
                    ImVec2(
                        130.0f,
                        36.0f
                    )
                ))
                {
                    aimbot = false;
                    esp = true;
                    autoFire = false;
                    fov = 90.0f;
                }

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

                ImGui::BeginChild(
                    "##VisualCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x - 18.0f,
                        235.0f
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

                ImGui::Text(
                    "Player ESP"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 49.0f
                );

                ASASECSwitch(
                    "PlayerESP",
                    &playerESP
                );

                ImGui::Spacing();

                ImGui::Text(
                    "Health Bar"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 49.0f
                );

                ASASECSwitch(
                    "HealthBar",
                    &healthBar
                );

                ImGui::Spacing();

                ImGui::Text(
                    "Wallhack"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x - 49.0f
                );

                ASASECSwitch(
                    "Wallhack",
                    &wallhack
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
                        235.0f
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

                ImGui::EndChild();
            }

            #pragma mark Modern Resize Handle

            float handleRight =
                windowSize.x - 7.0f;

            float handleBottom =
                windowSize.y - 7.0f;

            ImVec2 handleOrigin =
                ImVec2(
                    windowPos.x +
                    handleRight -
                    22.0f,

                    windowPos.y +
                    handleBottom -
                    22.0f
                );

            ImVec4 resizeColor =
                gResizingMenu
                ? ImVec4(
                    0.48f,
                    0.73f,
                    1.0f,
                    0.95f
                  )
                : ImVec4(
                    0.72f,
                    0.76f,
                    0.82f,
                    0.45f
                  );

            ImU32 resizeColorU32 =
                ImGui::ColorConvertFloat4ToU32(
                    resizeColor
                );

            draw->AddLine(
                ImVec2(
                    handleOrigin.x + 5.0f,
                    handleOrigin.y + 18.0f
                ),
                ImVec2(
                    handleOrigin.x + 18.0f,
                    handleOrigin.y + 18.0f
                ),
                resizeColorU32,
                2.2f
            );

            draw->AddLine(
                ImVec2(
                    handleOrigin.x + 11.0f,
                    handleOrigin.y + 12.0f
                ),
                ImVec2(
                    handleOrigin.x + 18.0f,
                    handleOrigin.y + 12.0f
                ),
                resizeColorU32,
                2.2f
            );

            draw->AddLine(
                ImVec2(
                    handleOrigin.x + 17.0f,
                    handleOrigin.y + 6.0f
                ),
                ImVec2(
                    handleOrigin.x + 17.0f,
                    handleOrigin.y + 18.0f
                ),
                resizeColorU32,
                2.2f
            );

            draw->AddLine(
                ImVec2(
                    handleOrigin.x + 11.0f,
                    handleOrigin.y + 12.0f
                ),
                ImVec2(
                    handleOrigin.x + 11.0f,
                    handleOrigin.y + 18.0f
                ),
                resizeColorU32,
                2.2f
            );

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
        ImVec2(
            10.0f,
            10.0f
        );

    style.FramePadding =
        ImVec2(
            11.0f,
            8.0f
        );

    style.ItemSpacing =
        ImVec2(
            9.0f,
            9.0f
        );

    style.ItemInnerSpacing =
        ImVec2(
            7.0f,
            6.0f
        );

    /*
     Scrollbar biraz kalinlastirildi.
    */
    style.ScrollbarSize =
        11.0f;

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
        10.0f;

    style.GrabRounding =
        9.0f;

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
            0.16f,
            0.22f,
            0.32f,
            1.0f
        );

    c[ImGuiCol_ScrollbarGrabHovered] =
        ImVec4(
            0.22f,
            0.31f,
            0.45f,
            1.0f
        );

    c[ImGuiCol_ScrollbarGrabActive] =
        ImVec4(
            0.27f,
            0.40f,
            0.58f,
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

#pragma mark - Stop

void ASASECImGuiStop(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!gInitialized)
                return;

            gInitialized =
                NO;

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

            gMenuVisible =
                YES;

            gMenuCollapsed =
                NO;

            gSelectedPage =
                0;

            gDraggingMenu =
                NO;

            gResizingMenu =
                NO;

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
