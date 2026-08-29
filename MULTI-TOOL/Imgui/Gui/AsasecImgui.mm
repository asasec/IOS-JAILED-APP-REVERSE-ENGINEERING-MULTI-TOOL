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

static BOOL gDraggingMenu = NO;
static CGPoint gDragStartPoint = CGPointZero;
static ImVec2 gDragStartPosition = ImVec2(25.0f, 75.0f);

static float gMenuAlpha = 1.0f;

static const float kHeaderHeight = 54.0f;
static const float kSidebarWidth = 145.0f;
static const float kMenuRadius = 18.0f;


/*
 * ---------------------------------------------------------
 * HELPERS
 * ---------------------------------------------------------
 */

static float ASASECLerp(
    float current,
    float target,
    float speed
)
{
    ImGuiIO &io = ImGui::GetIO();

    float dt = io.DeltaTime;

    if (dt <= 0.0f || dt > 0.1f)
        dt = 1.0f / 60.0f;

    float amount =
        1.0f - expf(-speed * dt);

    return current +
           (target - current) * amount;
}


static ImVec4 ASASECColor(
    float r,
    float g,
    float b,
    float a
)
{
    return ImVec4(r, g, b, a);
}


/*
 * Modern animated toggle.
 */

static bool ASASECToggle(
    const char *label,
    bool *value
)
{
    bool changed = false;

    ImGui::PushID(label);

    ImVec2 cursor =
        ImGui::GetCursorScreenPos();

    float fullWidth =
        ImGui::GetContentRegionAvail().x;

    if (fullWidth < 80.0f)
        fullWidth = 80.0f;

    const float rowHeight = 34.0f;
    const float toggleWidth = 42.0f;
    const float toggleHeight = 22.0f;

    ImGui::InvisibleButton(
        "##toggle_row",
        ImVec2(fullWidth, rowHeight)
    );

    if (ImGui::IsItemClicked())
    {
        *value = !*value;
        changed = true;
    }

    bool hovered =
        ImGui::IsItemHovered();

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    ImVec2 rowMin =
        cursor;

    ImVec2 rowMax =
        ImVec2(
            cursor.x + fullWidth,
            cursor.y + rowHeight
        );

    if (hovered)
    {
        draw->AddRectFilled(
            rowMin,
            rowMax,
            IM_COL32(255, 255, 255, 5),
            8.0f
        );
    }

    ImVec2 textPos =
        ImVec2(
            cursor.x + 2.0f,
            cursor.y + 8.0f
        );

    draw->AddText(
        textPos,
        IM_COL32(225, 231, 240, 255),
        label
    );

    ImVec2 toggleMin =
        ImVec2(
            cursor.x +
            fullWidth -
            toggleWidth,
            cursor.y +
            (rowHeight - toggleHeight) * 0.5f
        );

    ImVec2 toggleMax =
        ImVec2(
            toggleMin.x + toggleWidth,
            toggleMin.y + toggleHeight
        );

    /*
     * Store animation state per widget.
     */

    static float toggleAnimation[32] = {};

    ImGuiID id =
        ImGui::GetID(label);

    int index =
        (int)(id % 32);

    float target =
        *value ? 1.0f : 0.0f;

    toggleAnimation[index] =
        ASASECLerp(
            toggleAnimation[index],
            target,
            14.0f
        );

    float t =
        toggleAnimation[index];

    int bgR =
        (int)(43.0f + 22.0f * t);

    int bgG =
        (int)(52.0f + 83.0f * t);

    int bgB =
        (int)(68.0f + 168.0f * t);

    draw->AddRectFilled(
        toggleMin,
        toggleMax,
        IM_COL32(
            bgR,
            bgG,
            bgB,
            255
        ),
        toggleHeight * 0.5f
    );

    float knobRadius = 7.5f;

    float knobX =
        toggleMin.x +
        knobRadius +
        2.0f +
        t *
        (
            toggleWidth -
            knobRadius * 2.0f -
            4.0f
        );

    float knobY =
        (toggleMin.y + toggleMax.y) * 0.5f;

    draw->AddCircleFilled(
        ImVec2(
            knobX,
            knobY
        ),
        knobRadius,
        IM_COL32(
            242,
            246,
            252,
            255
        )
    );

    ImGui::PopID();

    return changed;
}


/*
 * ---------------------------------------------------------
 * IMGUI VIEW
 * ---------------------------------------------------------
 */

@interface ASASECImGuiView : MTKView
@end


@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    float height =
        gMenuCollapsed ?
        kHeaderHeight :
        gMenuSize.y;

    return
        point.x >= gMenuPosition.x &&
        point.x <= gMenuPosition.x + gMenuSize.x &&
        point.y >= gMenuPosition.y &&
        point.y <= gMenuPosition.y + height;
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
    if (!gInitialized || !gMenuVisible)
        return nil;

    if ([self pointInsideMenu:point])
        return self;

    return nil;
}


- (void)beginMenuDragAtPoint:(CGPoint)point
{
    gDraggingMenu = YES;

    gDragStartPoint =
        point;

    gDragStartPosition =
        gMenuPosition;
}


- (void)updateMenuDragAtPoint:(CGPoint)point
{
    if (!gDraggingMenu)
        return;

    CGFloat dx =
        point.x -
        gDragStartPoint.x;

    CGFloat dy =
        point.y -
        gDragStartPoint.y;

    gMenuPosition.x =
        gDragStartPosition.x +
        (float)dx;

    gMenuPosition.y =
        gDragStartPosition.y +
        (float)dy;

    UIWindow *window =
        self.window;

    if (!window)
        return;

    CGSize screenSize =
        window.bounds.size;

    float width =
        gMenuSize.x;

    float height =
        gMenuCollapsed ?
        kHeaderHeight :
        gMenuSize.y;

    const float margin =
        8.0f;

    float minX =
        margin;

    float minY =
        margin;

    float maxX =
        (float)screenSize.width -
        width -
        margin;

    float maxY =
        (float)screenSize.height -
        height -
        margin;

    if (maxX < minX)
        maxX = minX;

    if (maxY < minY)
        maxY = minY;

    if (gMenuPosition.x < minX)
        gMenuPosition.x = minX;

    if (gMenuPosition.y < minY)
        gMenuPosition.y = minY;

    if (gMenuPosition.x > maxX)
        gMenuPosition.x = maxX;

    if (gMenuPosition.y > maxY)
        gMenuPosition.y = maxY;
}


- (void)endMenuDrag
{
    gDraggingMenu = NO;
}


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


- (void)touchesBegan:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    UITouch *touch =
        touches.anyObject;

    if (touch)
    {
        CGPoint point =
            [touch locationInView:self];

        /*
         * IMPORTANT:
         * Only header can drag.
         */

        if ([self pointInsideDragHeader:point])
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

    if (touch && gDraggingMenu)
    {
        CGPoint point =
            [touch locationInView:self];

        [self updateMenuDragAtPoint:point];
    }

    [self updateIOWithTouchEvent:event];
}


- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self endMenuDrag];

    [self updateIOWithTouchEvent:event];

    ImGuiIO &io =
        ImGui::GetIO();

    io.MouseDown[0] =
        false;
}


- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    [self endMenuDrag];

    [self updateIOWithTouchEvent:event];

    ImGuiIO &io =
        ImGui::GetIO();

    io.MouseDown[0] =
        false;
}

@end


/*
 * ---------------------------------------------------------
 * RENDERER
 * ---------------------------------------------------------
 */

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


    /*
     * -----------------------------------------------------
     * MENU
     * -----------------------------------------------------
     */

    if (gMenuVisible)
    {
        float windowHeight =
            gMenuCollapsed ?
            kHeaderHeight :
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
            ImVec2(
                0.0f,
                0.0f
            )
        );

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowRounding,
            kMenuRadius
        );

        ImGui::PushStyleColor(
            ImGuiCol_WindowBg,
            ImVec4(
                0.025f,
                0.030f,
                0.045f,
                0.96f
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

        /*
         * Don't overwrite position while dragging.
         */

        if (!gDraggingMenu)
        {
            gMenuPosition =
                windowPos;
        }

        /*
         * Keep original size stable.
         */

        if (!gMenuCollapsed)
        {
            if (windowSize.x > 100.0f &&
                windowSize.y > 100.0f)
            {
                gMenuSize =
                    windowSize;
            }
        }

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
         * -------------------------------------------------
         * MAIN GLASS BACKGROUND
         * -------------------------------------------------
         */

        draw->AddRectFilled(
            windowPos,
            windowEnd,
            IM_COL32(
                6,
                9,
                16,
                248
            ),
            kMenuRadius
        );

        /*
         * Subtle inner border
         */

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
                72,
                91,
                119,
                90
            ),
            kMenuRadius,
            0,
            1.0f
        );


        /*
         * -------------------------------------------------
         * HEADER
         * -------------------------------------------------
         */

        draw->AddRectFilled(
            windowPos,
            ImVec2(
                windowEnd.x,
                windowPos.y +
                kHeaderHeight
            ),
            IM_COL32(
                11,
                16,
                27,
                255
            ),
            kMenuRadius,
            ImDrawFlags_RoundCornersTop
        );


        /*
         * Header accent glow
         */

        draw->AddRectFilled(
            ImVec2(
                windowPos.x + 18.0f,
                windowPos.y +
                kHeaderHeight -
                2.0f
            ),
            ImVec2(
                windowPos.x + 115.0f,
                windowPos.y +
                kHeaderHeight
            ),
            IM_COL32(
                65,
                145,
                255,
                255
            ),
            1.0f
        );


        /*
         * Header separator
         */

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
                34,
                44,
                62,
                220
            ),
            1.0f
        );


        /*
         * LOGO
         */

        ImGui::SetCursorPos(
            ImVec2(
                19.0f,
                9.0f
            )
        );

        ImGui::TextColored(
            ASASECColor(
                0.30f,
                0.67f,
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
            ASASECColor(
                0.44f,
                0.49f,
                0.58f,
                1.0f
            ),
            "CONTROL"
        );


        /*
         * Header status
         */

        if (!gMenuCollapsed)
        {
            ImGui::SameLine(
                0.0f,
                12.0f
            );

            ImGui::TextColored(
                ASASECColor(
                    0.29f,
                    0.85f,
                    0.56f,
                    1.0f
                ),
                "●"
            );

            ImGui::SameLine(
                0.0f,
                4.0f
            );

            ImGui::TextColored(
                ASASECColor(
                    0.39f,
                    0.44f,
                    0.52f,
                    1.0f
                ),
                "ONLINE"
            );
        }


        /*
         * COLLAPSE
         */

        ImGui::SetCursorPos(
            ImVec2(
                windowSize.x -
                70.0f,
                10.0f
            )
        );

        ImGui::PushStyleColor(
            ImGuiCol_Button,
            ImVec4(
                0.06f,
                0.09f,
                0.15f,
                1.0f
            )
        );

        ImGui::PushStyleColor(
            ImGuiCol_ButtonHovered,
            ImVec4(
                0.11f,
                0.17f,
                0.27f,
                1.0f
            )
        );

        ImGui::PushStyleColor(
            ImGuiCol_ButtonActive,
            ImVec4(
                0.15f,
                0.25f,
                0.40f,
                1.0f
            )
        );

        if (ImGui::Button(
            gMenuCollapsed ? "+" : "—",
            ImVec2(
                28.0f,
                32.0f
            )
        ))
        {
            gMenuCollapsed =
                !gMenuCollapsed;
        }

        ImGui::PopStyleColor(3);


        /*
         * CLOSE
         */

        ImGui::SameLine(
            0.0f,
            6.0f
        );

        ImGui::PushStyleColor(
            ImGuiCol_Button,
            ImVec4(
                0.27f,
                0.055f,
                0.085f,
                1.0f
            )
        );

        ImGui::PushStyleColor(
            ImGuiCol_ButtonHovered,
            ImVec4(
                0.52f,
                0.08f,
                0.13f,
                1.0f
            )
        );

        ImGui::PushStyleColor(
            ImGuiCol_ButtonActive,
            ImVec4(
                0.70f,
                0.12f,
                0.18f,
                1.0f
            )
        );

        if (ImGui::Button(
            "×",
            ImVec2(
                28.0f,
                32.0f
            )
        ))
        {
            gMenuVisible =
                NO;
        }

        ImGui::PopStyleColor(3);


        /*
         * -------------------------------------------------
         * COLLAPSED
         * -------------------------------------------------
         */

        if (gMenuCollapsed)
        {
            ImGui::End();

            ImGui::PopStyleColor();
            ImGui::PopStyleVar(2);
        }
        else
        {
            /*
             * -------------------------------------------------
             * SIDEBAR
             * -------------------------------------------------
             */

            draw->AddRectFilled(
                ImVec2(
                    windowPos.x,
                    windowPos.y +
                    kHeaderHeight
                ),
                ImVec2(
                    windowPos.x +
                    kSidebarWidth,
                    windowEnd.y
                ),
                IM_COL32(
                    9,
                    13,
                    22,
                    255
                ),
                kMenuRadius,
                ImDrawFlags_RoundCornersBottomLeft
            );


            /*
             * Sidebar separator
             */

            draw->AddLine(
                ImVec2(
                    windowPos.x +
                    kSidebarWidth,
                    windowPos.y +
                    kHeaderHeight +
                    12.0f
                ),
                ImVec2(
                    windowPos.x +
                    kSidebarWidth,
                    windowEnd.y -
                    14.0f
                ),
                IM_COL32(
                    29,
                    38,
                    54,
                    230
                ),
                1.0f
            );


            /*
             * MODULES
             */

            ImGui::SetCursorPos(
                ImVec2(
                    18.0f,
                    69.0f
                )
            );

            ImGui::TextColored(
                ASASECColor(
                    0.35f,
                    0.40f,
                    0.49f,
                    1.0f
                ),
                "MODULES"
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
                float itemY =
                    94.0f +
                    i * 52.0f;

                bool active =
                    gSelectedPage == i;


                /*
                 * Active item
                 */

                if (active)
                {
                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x + 10.0f,
                            windowPos.y + itemY
                        ),
                        ImVec2(
                            windowPos.x +
                            kSidebarWidth -
                            10.0f,
                            windowPos.y +
                            itemY +
                            42.0f
                        ),
                        IM_COL32(
                            18,
                            48,
                            84,
                            255
                        ),
                        11.0f
                    );


                    /*
                     * Active left indicator
                     */

                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x + 10.0f,
                            windowPos.y +
                            itemY +
                            10.0f
                        ),
                        ImVec2(
                            windowPos.x + 13.0f,
                            windowPos.y +
                            itemY +
                            32.0f
                        ),
                        IM_COL32(
                            67,
                            150,
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
                        0.16f,
                        0.26f,
                        0.80f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_ButtonActive,
                    ImVec4(
                        0.13f,
                        0.23f,
                        0.38f,
                        1.0f
                    )
                );


                if (ImGui::Button(
                    id,
                    ImVec2(
                        kSidebarWidth -
                        20.0f,
                        42.0f
                    )
                ))
                {
                    gSelectedPage =
                        i;
                }


                ImGui::PopStyleColor(3);
            }


            /*
             * Sidebar footer
             */

            ImGui::SetCursorPos(
                ImVec2(
                    18.0f,
                    windowSize.y -
                    45.0f
                )
            );

            ImGui::TextColored(
                ASASECColor(
                    0.28f,
                    0.84f,
                    0.57f,
                    1.0f
                ),
                "●"
            );

            ImGui::SameLine(
                0.0f,
                5.0f
            );

            ImGui::TextColored(
                ASASECColor(
                    0.38f,
                    0.43f,
                    0.51f,
                    1.0f
                ),
                "SYSTEM READY"
            );


            /*
             * -------------------------------------------------
             * CONTENT
             * -------------------------------------------------
             */

            ImGui::SetCursorPos(
                ImVec2(
                    kSidebarWidth + 1.0f,
                    kHeaderHeight
                )
            );


            ImGui::BeginChild(
                "##Content",
                ImVec2(
                    windowSize.x -
                    kSidebarWidth -
                    1.0f,
                    windowSize.y -
                    kHeaderHeight
                ),
                false,
                ImGuiWindowFlags_NoScrollbar |
                ImGuiWindowFlags_NoScrollWithMouse
            );


            /*
             * Page title
             */

            ImGui::SetCursorPos(
                ImVec2(
                    20.0f,
                    16.0f
                )
            );

            ImGui::TextColored(
                ASASECColor(
                    0.94f,
                    0.96f,
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
                ASASECColor(
                    0.30f,
                    0.35f,
                    0.44f,
                    1.0f
                ),
                "/ ASASEC"
            );


            /*
             * Subtitle
             */

            ImGui::SetCursorPos(
                ImVec2(
                    20.0f,
                    41.0f
                )
            );

            if (gSelectedPage == 0)
            {
                ImGui::TextColored(
                    ASASECColor(
                        0.40f,
                        0.45f,
                        0.53f,
                        1.0f
                    ),
                    "Combat configuration"
                );
            }
            else if (gSelectedPage == 1)
            {
                ImGui::TextColored(
                    ASASECColor(
                        0.40f,
                        0.45f,
                        0.53f,
                        1.0f
                    ),
                    "Visual configuration"
                );
            }
            else
            {
                ImGui::TextColored(
                    ASASECColor(
                        0.40f,
                        0.45f,
                        0.53f,
                        1.0f
                    ),
                    "Application configuration"
                );
            }


            /*
             * -------------------------------------------------
             * COMBAT
             * -------------------------------------------------
             */

            if (gSelectedPage == 0)
            {
                static bool aimbot =
                    false;

                static bool esp =
                    true;

                static bool autoFire =
                    false;

                static float fov =
                    90.0f;


                ImGui::SetCursorPos(
                    ImVec2(
                        20.0f,
                        76.0f
                    )
                );


                ImGui::BeginChild(
                    "##CombatCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x -
                        28.0f,
                        254.0f
                    ),
                    true
                );


                ImGui::TextColored(
                    ASASECColor(
                        0.30f,
                        0.67f,
                        1.0f,
                        1.0f
                    ),
                    "COMBAT FEATURES"
                );

                ImGui::SameLine();

                ImGui::TextColored(
                    ASASECColor(
                        0.34f,
                        0.40f,
                        0.48f,
                        1.0f
                    ),
                    "CONFIGURATION"
                );


                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();


                ASASECToggle(
                    "Aimbot",
                    &aimbot
                );


                ASASECToggle(
                    "Box ESP",
                    &esp
                );


                ASASECToggle(
                    "Auto Fire",
                    &autoFire
                );


                ImGui::Spacing();


                ImGui::TextColored(
                    ASASECColor(
                        0.48f,
                        0.53f,
                        0.61f,
                        1.0f
                    ),
                    "FOV RADIUS"
                );


                ImGui::Spacing();


                ImGui::SetNextItemWidth(
                    ImGui::GetContentRegionAvail().x
                );


                ImGui::SliderFloat(
                    "##FOV",
                    &fov,
                    10.0f,
                    180.0f,
                    "%.0f"
                );


                ImGui::SameLine();


                ImGui::TextColored(
                    ASASECColor(
                        0.30f,
                        0.67f,
                        1.0f,
                        1.0f
                    ),
                    "%.0f°",
                    fov
                );


                ImGui::EndChild();
            }


            /*
             * -------------------------------------------------
             * VISUALS
             * -------------------------------------------------
             */

            else if (gSelectedPage == 1)
            {
                static bool playerESP =
                    true;

                static bool healthBar =
                    true;

                static bool wallhack =
                    false;


                ImGui::SetCursorPos(
                    ImVec2(
                        20.0f,
                        76.0f
                    )
                );


                ImGui::BeginChild(
                    "##VisualCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x -
                        28.0f,
                        232.0f
                    ),
                    true
                );


                ImGui::TextColored(
                    ASASECColor(
                        0.30f,
                        0.82f,
                        0.58f,
                        1.0f
                    ),
                    "VISUAL FEATURES"
                );

                ImGui::SameLine();

                ImGui::TextColored(
                    ASASECColor(
                        0.34f,
                        0.40f,
                        0.48f,
                        1.0f
                    ),
                    "ESP"
                );


                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();


                ASASECToggle(
                    "Player ESP",
                    &playerESP
                );


                ASASECToggle(
                    "Health Bar",
                    &healthBar
                );


                ASASECToggle(
                    "Wallhack",
                    &wallhack
                );


                ImGui::Spacing();

                ImGui::TextColored(
                    ASASECColor(
                        0.37f,
                        0.42f,
                        0.50f,
                        1.0f
                    ),
                    "Visual modules ready."
                );


                ImGui::EndChild();
            }


            /*
             * -------------------------------------------------
             * SETTINGS
             * -------------------------------------------------
             */

            else
            {
                ImGui::SetCursorPos(
                    ImVec2(
                        20.0f,
                        76.0f
                    )
                );


                ImGui::BeginChild(
                    "##SettingsCard",
                    ImVec2(
                        ImGui::GetContentRegionAvail().x -
                        28.0f,
                        225.0f
                    ),
                    true
                );


                ImGui::TextColored(
                    ASASECColor(
                        1.0f,
                        0.66f,
                        0.30f,
                        1.0f
                    ),
                    "SYSTEM"
                );

                ImGui::SameLine();

                ImGui::TextColored(
                    ASASECColor(
                        0.34f,
                        0.40f,
                        0.48f,
                        1.0f
                    ),
                    "INFORMATION"
                );


                ImGui::Spacing();

                ImGui::Separator();

                ImGui::Spacing();


                ImGui::TextColored(
                    ASASECColor(
                        0.48f,
                        0.53f,
                        0.61f,
                        1.0f
                    ),
                    "VERSION"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x -
                    36.0f
                );

                ImGui::TextColored(
                    ASASECColor(
                        0.30f,
                        0.67f,
                        1.0f,
                        1.0f
                    ),
                    "3.1"
                );


                ImGui::Spacing();


                ImGui::TextColored(
                    ASASECColor(
                        0.48f,
                        0.53f,
                        0.61f,
                        1.0f
                    ),
                    "RENDERER"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x -
                    42.0f
                );

                ImGui::Text(
                    "Metal"
                );


                ImGui::Spacing();


                ImGui::TextColored(
                    ASASECColor(
                        0.48f,
                        0.53f,
                        0.61f,
                        1.0f
                    ),
                    "STATUS"
                );

                ImGui::SameLine(
                    ImGui::GetContentRegionAvail().x -
                    48.0f
                );

                ImGui::TextColored(
                    ASASECColor(
                        0.30f,
                        0.86f,
                        0.56f,
                        1.0f
                    ),
                    "ACTIVE"
                );


                ImGui::Spacing();

                ImGui::TextColored(
                    ASASECColor(
                        0.36f,
                        0.41f,
                        0.49f,
                        1.0f
                    ),
                    "ASASEC CONTROL CENTER"
                );


                ImGui::EndChild();
            }


            ImGui::EndChild();

            ImGui::End();

            ImGui::PopStyleColor();
            ImGui::PopStyleVar(2);
        }
    }


    /*
     * ---------------------------------------------------------
     * RENDER
     * ---------------------------------------------------------
     */

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


/*
 * ---------------------------------------------------------
 * GLOBAL RENDERER
 * ---------------------------------------------------------
 */

static ASASECImGuiRenderer *gRenderer = nil;


/*
 * ---------------------------------------------------------
 * STYLE
 * ---------------------------------------------------------
 */

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
            10.0f,
            7.0f
        );

    style.ItemSpacing =
        ImVec2(
            8.0f,
            8.0f
        );

    style.ItemInnerSpacing =
        ImVec2(
            7.0f,
            6.0f
        );


    style.ScrollbarSize =
        7.0f;

    style.GrabMinSize =
        13.0f;


    style.WindowRounding =
        18.0f;

    style.ChildRounding =
        13.0f;

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
            0.93f,
            0.95f,
            1.0f,
            1.0f
        );


    c[ImGuiCol_TextDisabled] =
        ImVec4(
            0.40f,
            0.44f,
            0.52f,
            1.0f
        );


    c[ImGuiCol_WindowBg] =
        ImVec4(
            0.025f,
            0.030f,
            0.045f,
            0.96f
        );


    c[ImGuiCol_ChildBg] =
        ImVec4(
            0.045f,
            0.055f,
            0.078f,
            0.98f
        );


    c[ImGuiCol_Border] =
        ImVec4(
            0.12f,
            0.15f,
            0.21f,
            0.75f
        );


    c[ImGuiCol_FrameBg] =
        ImVec4(
            0.060f,
            0.075f,
            0.105f,
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
            0.13f,
            0.19f,
            0.29f,
            1.0f
        );


    c[ImGuiCol_Button] =
        ImVec4(
            0.060f,
            0.080f,
            0.120f,
            1.0f
        );


    c[ImGuiCol_ButtonHovered] =
        ImVec4(
            0.10f,
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
            0.36f,
            0.70f,
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
            0.14f,
            0.22f,
            0.35f,
            1.0f
        );


    c[ImGuiCol_HeaderActive] =
        ImVec4(
            0.17f,
            0.29f,
            0.46f,
            1.0f
        );


    c[ImGuiCol_Separator] =
        ImVec4(
            0.12f,
            0.15f,
            0.21f,
            0.75f
        );


    c[ImGuiCol_ScrollbarBg] =
        ImVec4(
            0.025f,
            0.032f,
            0.050f,
            0.8f
        );


    c[ImGuiCol_ScrollbarGrab] =
        ImVec4(
            0.12f,
            0.16f,
            0.23f,
            1.0f
        );


    c[ImGuiCol_ScrollbarGrabHovered] =
        ImVec4(
            0.18f,
            0.25f,
            0.36f,
            1.0f
        );


    c[ImGuiCol_ScrollbarGrabActive] =
        ImVec4(
            0.22f,
            0.34f,
            0.50f,
            1.0f
        );
}


/*
 * ---------------------------------------------------------
 * START
 * ---------------------------------------------------------
 */

void ASASECImGuiStart(void)
{
    if (gInitialized)
        return;


    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (gInitialized)
                return;


            UIWindow *window =
                nil;


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
                        window =
                            candidate;

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


            io.IniFilename =
                NULL;


            io.FontGlobalScale =
                1.0f;


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


            if (!gImGuiView)
            {
                ImGui::DestroyContext();

                gCommandQueue =
                    nil;

                return;
            }


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


            if (!gRenderer)
            {
                gImGuiView =
                    nil;

                ImGui::DestroyContext();

                gCommandQueue =
                    nil;

                return;
            }


            gImGuiView.delegate =
                gRenderer;


            [window addSubview:gImGuiView];

            [window bringSubviewToFront:gImGuiView];


            ImGui_ImplMetal_Init(device);


            gMenuVisible =
                YES;

            gMenuCollapsed =
                NO;

            gSelectedPage =
                0;

            gDraggingMenu =
                NO;


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


            gDragStartPoint =
                CGPointZero;


            gDragStartPosition =
                gMenuPosition;


            gInitialized =
                YES;
        }
    );
}


/*
 * ---------------------------------------------------------
 * STOP
 * ---------------------------------------------------------
 */

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


            gDragStartPoint =
                CGPointZero;


            gMenuPosition =
                ImVec2(
                    25.0f,
                    75.0f
                );


            gDragStartPosition =
                gMenuPosition;


            gMenuSize =
                ImVec2(
                    560.0f,
                    390.0f
                );


            gMenuAlpha =
                1.0f;
        }
    );
}
