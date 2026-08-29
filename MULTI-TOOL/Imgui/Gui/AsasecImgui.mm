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

static bool gDraggingMenu = false;
static ImVec2 gDragStartMouse = ImVec2(0.0f, 0.0f);
static ImVec2 gDragStartPosition = ImVec2(0.0f, 0.0f);

static bool gAimbot = false;
static bool gESP = true;
static bool gAutoFire = false;
static float gFOV = 90.0f;

static bool gPlayerESP = true;
static bool gHealthBar = true;
static bool gWallhack = false;

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

- (UIView *)hitTest:(CGPoint)point
           withEvent:(UIEvent *)event
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

    ImGuiIO &io = ImGui::GetIO();

    UITouch *touch = event.allTouches.anyObject;

    if (touch)
    {
        CGPoint point = [touch locationInView:self];

        io.MousePos = ImVec2(
            (float)point.x,
            (float)point.y
        );
    }

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

    if (!touching)
    {
        gDraggingMenu = false;
    }
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

    /*
     Clamp menu position when screen size changes.
    */

    float screenWidth =
        view.bounds.size.width;

    float screenHeight =
        view.bounds.size.height;

    float maxX =
        screenWidth - gMenuSize.x;

    float maxY =
        screenHeight - 50.0f;

    if (maxX < 5.0f)
        maxX = 5.0f;

    if (maxY < 5.0f)
        maxY = 5.0f;

    if (gMenuPosition.x > maxX)
        gMenuPosition.x = maxX;

    if (gMenuPosition.y > maxY)
        gMenuPosition.y = maxY;

    if (gMenuPosition.x < 5.0f)
        gMenuPosition.x = 5.0f;

    if (gMenuPosition.y < 5.0f)
        gMenuPosition.y = 5.0f;
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

    float fps =
        view.preferredFramesPerSecond;

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
                0.025f,
                0.032f,
                0.050f,
                0.985f
            )
        );

        bool windowOpen = true;

        if (ImGui::Begin(
            "##ASASEC_WINDOW",
            &windowOpen,
            flags
        ))
        {
            ImVec2 windowPos =
                ImGui::GetWindowPos();

            ImVec2 windowSize =
                ImGui::GetWindowSize();

            ImDrawList *draw =
                ImGui::GetWindowDrawList();

            /*
             Main background
            */

            draw->AddRectFilled(
                windowPos,
                ImVec2(
                    windowPos.x + windowSize.x,
                    windowPos.y + windowSize.y
                ),
                IM_COL32(7, 10, 17, 250),
                18.0f
            );

            /*
             Subtle border
            */

            draw->AddRect(
                windowPos,
                ImVec2(
                    windowPos.x + windowSize.x,
                    windowPos.y + windowSize.y
                ),
                IM_COL32(42, 52, 72, 180),
                18.0f,
                0,
                1.0f
            );

            /*
             ========================================
             COLLAPSED HEADER
             ========================================
            */

            if (gMenuCollapsed)
            {
                /*
                 Header background
                */

                draw->AddRectFilled(
                    windowPos,
                    ImVec2(
                        windowPos.x + windowSize.x,
                        windowPos.y + 50.0f
                    ),
                    IM_COL32(12, 17, 28, 255),
                    18.0f
                );

                /*
                 Blue accent
                */

                draw->AddRectFilled(
                    ImVec2(
                        windowPos.x,
                        windowPos.y
                    ),
                    ImVec2(
                        windowPos.x + 4.0f,
                        windowPos.y + 50.0f
                    ),
                    IM_COL32(65, 145, 255, 255),
                    2.0f
                );

                ImGui::SetCursorPos(
                    ImVec2(17.0f, 9.0f)
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

                ImGui::SameLine();

                ImGui::TextColored(
                    ImVec4(
                        0.48f,
                        0.53f,
                        0.63f,
                        1.0f
                    ),
                    "CONTROL"
                );

                /*
                 Restore button
                */

                ImGui::SetCursorPos(
                    ImVec2(
                        windowSize.x - 72.0f,
                        9.0f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_Button,
                    ImVec4(
                        0.08f,
                        0.13f,
                        0.21f,
                        1.0f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_ButtonHovered,
                    ImVec4(
                        0.12f,
                        0.22f,
                        0.35f,
                        1.0f
                    )
                );

                if (ImGui::Button(
                    "+",
                    ImVec2(28.0f, 30.0f)
                ))
                {
                    gMenuCollapsed = NO;
                }

                ImGui::PopStyleColor(2);

                /*
                 Close button
                */

                ImGui::SameLine(
                    0.0f,
                    6.0f
                );

                ImGui::PushStyleColor(
                    ImGuiCol_Button,
                    ImVec4(
                        0.34f,
                        0.07f,
                        0.10f,
                        1.0f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_ButtonHovered,
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

                ImGui::PopStyleColor(2);
            }
            else
            {
                /*
                 ========================================
                 SIDEBAR
                 ========================================
                */

                const float sidebarWidth = 145.0f;

                draw->AddRectFilled(
                    windowPos,
                    ImVec2(
                        windowPos.x + sidebarWidth,
                        windowPos.y + windowSize.y
                    ),
                    IM_COL32(11, 15, 24, 255),
                    18.0f,
                    ImDrawFlags_RoundCornersLeft
                );

                /*
                 Sidebar accent line
                */

                draw->AddRectFilled(
                    ImVec2(
                        windowPos.x + sidebarWidth - 1.0f,
                        windowPos.y + 15.0f
                    ),
                    ImVec2(
                        windowPos.x + sidebarWidth,
                        windowPos.y + windowSize.y - 15.0f
                    ),
                    IM_COL32(28, 36, 52, 180)
                );

                /*
                 Logo
                */

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

                ImGui::SameLine();

                ImGui::TextColored(
                    ImVec4(
                        0.42f,
                        0.47f,
                        0.56f,
                        1.0f
                    ),
                    "UI"
                );

                /*
                 Logo separator
                */

                draw->AddLine(
                    ImVec2(
                        windowPos.x + 17.0f,
                        windowPos.y + 42.0f
                    ),
                    ImVec2(
                        windowPos.x + sidebarWidth - 17.0f,
                        windowPos.y + 42.0f
                    ),
                    IM_COL32(35, 44, 61, 200),
                    1.0f
                );

                /*
                 Navigation
                */

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
                    float y =
                        57.0f +
                        ((float)i * 49.0f);

                    bool active =
                        gSelectedPage == i;

                    if (active)
                    {
                        /*
                         Active background
                        */

                        draw->AddRectFilled(
                            ImVec2(
                                windowPos.x + 10.0f,
                                windowPos.y + y
                            ),
                            ImVec2(
                                windowPos.x +
                                sidebarWidth - 10.0f,
                                windowPos.y + y + 40.0f
                            ),
                            IM_COL32(20, 51, 91, 255),
                            9.0f
                        );

                        /*
                         Active indicator
                        */

                        draw->AddRectFilled(
                            ImVec2(
                                windowPos.x + 10.0f,
                                windowPos.y + y + 8.0f
                            ),
                            ImVec2(
                                windowPos.x + 13.0f,
                                windowPos.y + y + 32.0f
                            ),
                            IM_COL32(72, 155, 255, 255),
                            2.0f
                        );
                    }

                    ImGui::SetCursorPos(
                        ImVec2(
                            15.0f,
                            y
                        )
                    );

                    char id[64];

                    snprintf(
                        id,
                        sizeof(id),
                        "%s   %s##NAV_%d",
                        icons[i],
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
                            0.09f,
                            0.15f,
                            0.24f,
                            0.9f
                        )
                    );

                    ImGui::PushStyleColor(
                        ImGuiCol_ButtonActive,
                        ImVec4(
                            0.12f,
                            0.22f,
                            0.36f,
                            1.0f
                        )
                    );

                    if (ImGui::Button(
                        id,
                        ImVec2(
                            sidebarWidth - 25.0f,
                            40.0f
                        )
                    ))
                    {
                        gSelectedPage = i;
                    }

                    ImGui::PopStyleColor(3);
                }

                /*
                 ========================================
                 CONTENT
                 ========================================
                */

                ImGui::SetCursorPos(
                    ImVec2(
                        sidebarWidth,
                        0.0f
                    )
                );

                ImGui::BeginChild(
                    "##ASASEC_CONTENT",
                    ImVec2(
                        windowSize.x -
                        sidebarWidth,
                        windowSize.y
                    ),
                    false,
                    ImGuiWindowFlags_NoScrollbar
                );

                /*
                 ========================================
                 HEADER
                 ========================================
                */

                ImGui::SetCursorPos(
                    ImVec2(17.0f, 10.0f)
                );

                ImGui::TextColored(
                    ImVec4(
                        0.93f,
                        0.95f,
                        0.99f,
                        1.0f
                    ),
                    "%s",
                    pages[gSelectedPage]
                );

                ImGui::SameLine();

                ImGui::TextColored(
                    ImVec4(
                        0.34f,
                        0.39f,
                        0.48f,
                        1.0f
                    ),
                    "  /  ASASEC"
                );

                /*
                 Minimize
                */

                float rightButtons =
                    ImGui::GetWindowWidth() -
                    72.0f;

                ImGui::SetCursorPos(
                    ImVec2(
                        rightButtons,
                        8.0f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_Button,
                    ImVec4(
                        0.07f,
                        0.10f,
                        0.16f,
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

                if (ImGui::Button(
                    "—##MIN",
                    ImVec2(27.0f, 30.0f)
                ))
                {
                    gMenuCollapsed = YES;
                }

                ImGui::PopStyleColor(2);

                /*
                 Close
                */

                ImGui::SameLine(
                    0.0f,
                    6.0f
                );

                ImGui::PushStyleColor(
                    ImGuiCol_Button,
                    ImVec4(
                        0.34f,
                        0.07f,
                        0.10f,
                        1.0f
                    )
                );

                ImGui::PushStyleColor(
                    ImGuiCol_ButtonHovered,
                    ImVec4(
                        0.55f,
                        0.10f,
                        0.14f,
                        1.0f
                    )
                );

                if (ImGui::Button(
                    "×##CLOSE",
                    ImVec2(27.0f, 30.0f)
                ))
                {
                    gMenuVisible = NO;
                }

                ImGui::PopStyleColor(2);

                /*
                 ========================================
                 HEADER DIVIDER
                 ========================================
                */

                draw->AddLine(
                    ImVec2(
                        windowPos.x + sidebarWidth + 17.0f,
                        windowPos.y + 48.0f
                    ),
                    ImVec2(
                        windowPos.x + windowSize.x - 17.0f,
                        windowPos.y + 48.0f
                    ),
                    IM_COL32(31, 40, 56, 220),
                    1.0f
                );

                /*
                 ========================================
                 DRAG AREA
                 ========================================

                 Important:
                 Only the empty header region is draggable.
                */

                ImGui::SetCursorPos(
                    ImVec2(
                        135.0f,
                        0.0f
                    )
                );

                float dragWidth =
                    ImGui::GetWindowWidth() - 225.0f;

                if (dragWidth < 60.0f)
                    dragWidth = 60.0f;

                ImGui::InvisibleButton(
                    "##ASASEC_DRAG",
                    ImVec2(
                        dragWidth,
                        48.0f
                    )
                );

                if (ImGui::IsItemActivated())
                {
                    gDraggingMenu = true;

                    gDragStartMouse =
                        ImGui::GetIO().MousePos;

                    gDragStartPosition =
                        gMenuPosition;
                }

                if (gDraggingMenu)
                {
                    ImGuiIO &dragIO =
                        ImGui::GetIO();

                    if (dragIO.MouseDown[0])
                    {
                        ImVec2 delta =
                            dragIO.MousePos -
                            gDragStartMouse;

                        gMenuPosition =
                            gDragStartPosition +
                            delta;

                        /*
                         Keep menu on screen
                        */

                        float screenWidth =
                            view.bounds.size.width;

                        float screenHeight =
                            view.bounds.size.height;

                        float maxX =
                            screenWidth -
                            gMenuSize.x;

                        float maxY =
                            screenHeight -
                            50.0f;

                        if (maxX < 5.0f)
                            maxX = 5.0f;

                        if (maxY < 5.0f)
                            maxY = 5.0f;

                        if (gMenuPosition.x < 5.0f)
                            gMenuPosition.x = 5.0f;

                        if (gMenuPosition.y < 5.0f)
                            gMenuPosition.y = 5.0f;

                        if (gMenuPosition.x > maxX)
                            gMenuPosition.x = maxX;

                        if (gMenuPosition.y > maxY)
                            gMenuPosition.y = maxY;
                    }
                    else
                    {
                        gDraggingMenu = false;
                    }
                }

                /*
                 ========================================
                 PAGE CONTENT
                 ========================================
                */

                ImGui::SetCursorPos(
                    ImVec2(
                        17.0f,
                        65.0f
                    )
                );

                if (gSelectedPage == 0)
                {
                    /*
                     COMBAT
                    */

                    ImGui::TextColored(
                        ImVec4(
                            0.30f,
                            0.68f,
                            1.0f,
                            1.0f
                        ),
                        "COMBAT"
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.40f,
                            0.45f,
                            0.54f,
                            1.0f
                        ),
                        "Combat configuration"
                    );

                    ImGui::Spacing();

                    ImGui::BeginChild(
                        "##COMBAT_CARD",
                        ImVec2(
                            ImGui::GetContentRegionAvail().x - 18.0f,
                            270.0f
                        ),
                        true,
                        ImGuiWindowFlags_NoScrollbar
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

                    ImGui::SameLine();

                    ImGui::TextColored(
                        ImVec4(
                            0.38f,
                            0.43f,
                            0.52f,
                            1.0f
                        ),
                        "  SETTINGS"
                    );

                    ImGui::Separator();

                    ImGui::Spacing();

                    ImGui::Checkbox(
                        "Enable Aimbot",
                        &gAimbot
                    );

                    ImGui::Checkbox(
                        "Box ESP",
                        &gESP
                    );

                    ImGui::Checkbox(
                        "Auto Fire",
                        &gAutoFire
                    );

                    ImGui::Spacing();

                    ImGui::Text(
                        "FOV Radius"
                    );

                    ImGui::SetNextItemWidth(
                        ImGui::GetContentRegionAvail().x - 8.0f
                    );

                    ImGui::SliderFloat(
                        "##FOV_RADIUS",
                        &gFOV,
                        10.0f,
                        180.0f,
                        "%.0f"
                    );

                    ImGui::Spacing();

                    if (ImGui::Button(
                        "Reset Defaults",
                        ImVec2(125.0f, 34.0f)
                    ))
                    {
                        gAimbot = false;
                        gESP = true;
                        gAutoFire = false;
                        gFOV = 90.0f;
                    }

                    ImGui::EndChild();
                }
                else if (gSelectedPage == 1)
                {
                    /*
                     VISUALS
                    */

                    ImGui::TextColored(
                        ImVec4(
                            0.25f,
                            0.86f,
                            0.58f,
                            1.0f
                        ),
                        "VISUALS"
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.40f,
                            0.45f,
                            0.54f,
                            1.0f
                        ),
                        "Visual configuration"
                    );

                    ImGui::Spacing();

                    ImGui::BeginChild(
                        "##VISUAL_CARD",
                        ImVec2(
                            ImGui::GetContentRegionAvail().x - 18.0f,
                            235.0f
                        ),
                        true,
                        ImGuiWindowFlags_NoScrollbar
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.90f,
                            0.93f,
                            0.98f,
                            1.0f
                        ),
                        "ESP"
                    );

                    ImGui::Separator();

                    ImGui::Spacing();

                    ImGui::Checkbox(
                        "Player ESP",
                        &gPlayerESP
                    );

                    ImGui::Checkbox(
                        "Health Bar",
                        &gHealthBar
                    );

                    ImGui::Checkbox(
                        "Wallhack",
                        &gWallhack
                    );

                    ImGui::EndChild();
                }
                else
                {
                    /*
                     SETTINGS
                    */

                    ImGui::TextColored(
                        ImVec4(
                            1.0f,
                            0.67f,
                            0.30f,
                            1.0f
                        ),
                        "SETTINGS"
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.40f,
                            0.45f,
                            0.54f,
                            1.0f
                        ),
                        "ASASEC configuration"
                    );

                    ImGui::Spacing();

                    ImGui::BeginChild(
                        "##SETTINGS_CARD",
                        ImVec2(
                            ImGui::GetContentRegionAvail().x - 18.0f,
                            235.0f
                        ),
                        true,
                        ImGuiWindowFlags_NoScrollbar
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.90f,
                            0.93f,
                            0.98f,
                            1.0f
                        ),
                        "Application"
                    );

                    ImGui::Separator();

                    ImGui::Spacing();

                    ImGui::Text(
                        "Version"
                    );

                    ImGui::SameLine();

                    ImGui::TextColored(
                        ImVec4(
                            0.30f,
                            0.68f,
                            1.0f,
                            1.0f
                        ),
                        "3.0"
                    );

                    ImGui::Spacing();

                    ImGui::Text(
                        "Renderer"
                    );

                    ImGui::SameLine();

                    ImGui::TextColored(
                        ImVec4(
                            0.65f,
                            0.68f,
                            0.75f,
                            1.0f
                        ),
                        "Metal"
                    );

                    ImGui::Spacing();

                    ImGui::Text(
                        "Interface"
                    );

                    ImGui::SameLine();

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
        }

        ImGui::End();

        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);

        if (!windowOpen)
            gMenuVisible = NO;
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


static ASASECImGuiRenderer *gRenderer = nil;


static void ASASECApplyStyle(void)
{
    ImGuiStyle &style =
        ImGui::GetStyle();

    style.WindowPadding =
        ImVec2(10.0f, 10.0f);

    style.FramePadding =
        ImVec2(9.0f, 7.0f);

    style.ItemSpacing =
        ImVec2(8.0f, 9.0f);

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
            0.025f,
            0.032f,
            0.050f,
            0.985f
        );

    c[ImGuiCol_ChildBg] =
        ImVec4(
            0.045f,
            0.057f,
            0.080f,
            0.98f
        );

    c[ImGuiCol_Border] =
        ImVec4(
            0.13f,
            0.16f,
            0.22f,
            0.8f
        );

    c[ImGuiCol_FrameBg] =
        ImVec4(
            0.070f,
            0.085f,
            0.120f,
            1.0f
        );

    c[ImGuiCol_FrameBgHovered] =
        ImVec4(
            0.105f,
            0.135f,
            0.190f,
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
            0.070f,
            0.090f,
            0.130f,
            1.0f
        );

    c[ImGuiCol_ButtonHovered] =
        ImVec4(
            0.105f,
            0.155f,
            0.235f,
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
            0.13f,
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
            0.13f,
            0.16f,
            0.22f,
            0.75f
        );

    c[ImGuiCol_ScrollbarBg] =
        ImVec4(
            0.025f,
            0.032f,
            0.050f,
            0.7f
        );

    c[ImGuiCol_ScrollbarGrab] =
        ImVec4(
            0.14f,
            0.19f,
            0.27f,
            1.0f
        );

    c[ImGuiCol_ScrollbarGrabHovered] =
        ImVec4(
            0.19f,
            0.28f,
            0.40f,
            1.0f
        );

    c[ImGuiCol_ScrollbarGrabActive] =
        ImVec4(
            0.23f,
            0.36f,
            0.53f,
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

            /*
             Adapt initial menu size
             to smaller displays.
            */

            CGFloat screenWidth =
                window.bounds.size.width;

            CGFloat screenHeight =
                window.bounds.size.height;

            if (screenWidth < 600.0f)
            {
                gMenuSize.x =
                    screenWidth - 20.0f;

                if (gMenuSize.x < 320.0f)
                    gMenuSize.x = 320.0f;
            }

            if (screenHeight < 450.0f)
            {
                gMenuSize.y =
                    screenHeight - 40.0f;

                if (gMenuSize.y < 300.0f)
                    gMenuSize.y = 300.0f;
            }

            gMenuPosition =
                ImVec2(
                    15.0f,
                    65.0f
                );

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


void ASASECImGuiStop(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!gInitialized)
                return;

            gInitialized = NO;

            gDraggingMenu = false;

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

            gAimbot = false;
            gESP = true;
            gAutoFire = false;
            gFOV = 90.0f;

            gPlayerESP = true;
            gHealthBar = true;
            gWallhack = false;

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
