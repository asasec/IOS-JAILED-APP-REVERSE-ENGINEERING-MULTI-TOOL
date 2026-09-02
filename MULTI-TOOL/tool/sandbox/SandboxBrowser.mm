#import "SandboxBrowser.h"

#include <string>
#include <cstring>

#include "../../ASASECUI/imgui/imgui.h"

@implementation SandboxBrowser

@synthesize isWindowOpen = _isWindowOpen;
@synthesize isEditorOpen = _isEditorOpen;

#pragma mark - Browser Screen State

static BOOL gSandboxBrowserScreen = NO;

#pragma mark - Singleton

+ (instancetype)sharedInstance
{
    static SandboxBrowser *sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedInstance = [[SandboxBrowser alloc] init];
    });

    return sharedInstance;
}

#pragma mark - Open / Close

+ (void)openBrowser
{
    SandboxBrowser *browser =
        [SandboxBrowser sharedInstance];

    browser.isWindowOpen = YES;
    browser.isEditorOpen = NO;

    gSandboxBrowserScreen = YES;
}

+ (void)closeBrowser
{
    SandboxBrowser *browser =
        [SandboxBrowser sharedInstance];

    browser.isWindowOpen = NO;
    browser.isEditorOpen = NO;

    gSandboxBrowserScreen = NO;
}

+ (BOOL)isBrowserOpen
{
    return gSandboxBrowserScreen;
}

#pragma mark - Init

- (instancetype)init
{
    self = [super init];

    if (self) {

        [self loadDirectoryAtPath:NSHomeDirectory()];

        _isWindowOpen = NO;
        _isEditorOpen = NO;
    }

    return self;
}

#pragma mark - Directory

- (void)loadDirectoryAtPath:(NSString *)path
{
    if (!path || path.length == 0)
        return;

    self.currentPath = path;

    NSError *error = nil;

    NSArray *contents =
        [[NSFileManager defaultManager]
            contentsOfDirectoryAtPath:path
            error:&error];

    if (!error) {

        self.currentFiles =
            [contents sortedArrayUsingSelector:
                @selector(compare:)];

    } else {

        NSLog(
            @"SandboxBrowser Error: %@",
            error.localizedDescription
        );

        self.currentFiles = @[];
    }
}

#pragma mark - ImGui Browser

- (void)renderImGuiWindow
{
    if (!gSandboxBrowserScreen)
        return;

    if (!_isWindowOpen) {

        gSandboxBrowserScreen = NO;

        return;
    }

    ImGuiIO &io =
        ImGui::GetIO();

    ImVec2 displaySize =
        io.DisplaySize;

    if (displaySize.x <= 0.0f ||
        displaySize.y <= 0.0f) {

        return;
    }

    /*
     Full-screen Browser Window

     SetNextWindowViewport()
     kullanılmıyor.

     Böylece eski / farklı ImGui
     sürümleriyle uyumlu kalır.
    */

    ImGui::SetNextWindowPos(
        ImVec2(0.0f, 0.0f),
        ImGuiCond_Always
    );

    ImGui::SetNextWindowSize(
        displaySize,
        ImGuiCond_Always
    );

    ImGuiWindowFlags flags =
        ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoSavedSettings;

    bool windowVisible =
        ImGui::Begin(
            "Advanced Sandbox Browser",
            &_isWindowOpen,
            flags
        );

    if (windowVisible) {

        #pragma mark - Header

        ImGui::TextUnformatted(
            "SANDBOX BROWSER"
        );

        float windowWidth =
            ImGui::GetWindowWidth();

        ImGui::SameLine(
            windowWidth - 95.0f
        );

        if (ImGui::Button("Geri")) {

            [SandboxBrowser closeBrowser];
        }

        ImGui::Separator();

        #pragma mark - Current Path

        ImGui::TextUnformatted(
            "Aktif Konum:"
        );

        ImGui::BeginChild(
            "PathChild",
            ImVec2(0, 34),
            true,
            ImGuiWindowFlags_HorizontalScrollbar
        );

        if (self.currentPath) {

            const char *pathString =
                [self.currentPath UTF8String];

            if (pathString) {

                ImGui::Text(
                    "%s",
                    pathString
                );
            }
        }

        ImGui::EndChild();

        #pragma mark - Navigation

        if (![self.currentPath
              isEqualToString:NSHomeDirectory()]) {

            if (ImGui::Button(
                    "<- Bir Üst Dizin")) {

                NSString *parentPath =
                    [self.currentPath
                        stringByDeletingLastPathComponent];

                [self loadDirectoryAtPath:
                    parentPath];
            }

            ImGui::SameLine();
        }

        if (ImGui::Button(
                "Ev Dizini")) {

            [self loadDirectoryAtPath:
                NSHomeDirectory()];
        }

        ImGui::SameLine();

        if (ImGui::Button(
                "Yenile")) {

            [self loadDirectoryAtPath:
                self.currentPath];
        }

        ImGui::Separator();

        #pragma mark - File Table

        float footerHeight =
            32.0f;

        if (ImGui::BeginTable(
                "SandboxTable",
                4,
                ImGuiTableFlags_Borders |
                ImGuiTableFlags_RowBg |
                ImGuiTableFlags_ScrollY |
                ImGuiTableFlags_SizingFixedFit,
                ImVec2(0, -footerHeight))) {

            ImGui::TableSetupColumn(
                "İsim",
                ImGuiTableColumnFlags_WidthStretch
            );

            ImGui::TableSetupColumn(
                "Tür",
                ImGuiTableColumnFlags_WidthFixed,
                70.0f
            );

            ImGui::TableSetupColumn(
                "Boyut",
                ImGuiTableColumnFlags_WidthFixed,
                85.0f
            );

            ImGui::TableSetupColumn(
                "İşlemler",
                ImGuiTableColumnFlags_WidthFixed,
                145.0f
            );

            ImGui::TableHeadersRow();

            NSFileManager *fileManager =
                [NSFileManager defaultManager];

            for (NSString *fileName
                 in self.currentFiles) {

                NSString *fullPath =
                    [self.currentPath
                        stringByAppendingPathComponent:
                            fileName];

                BOOL isDirectory = NO;

                [fileManager
                    fileExistsAtPath:fullPath
                    isDirectory:&isDirectory];

                NSDictionary *attrs =
                    [fileManager
                        attributesOfItemAtPath:
                            fullPath
                        error:nil];

                unsigned long long fileSize =
                    [attrs fileSize];

                ImGui::TableNextRow();

                #pragma mark - Name

                ImGui::TableSetColumnIndex(0);

                const char *utfName =
                    [fileName UTF8String];

                std::string displayName =
                    (isDirectory
                        ? "[D] "
                        : "[F] ") +
                    std::string(
                        utfName
                            ? utfName
                            : ""
                    );

                if (ImGui::Selectable(
                        displayName.c_str(),
                        false,
                        ImGuiSelectableFlags_SpanAllColumns)) {

                    if (isDirectory) {

                        [self loadDirectoryAtPath:
                            fullPath];

                        break;
                    }
                }

                #pragma mark - Type

                ImGui::TableSetColumnIndex(1);

                ImGui::Text(
                    "%s",
                    isDirectory
                        ? "Dir"
                        : "File"
                );

                #pragma mark - Size

                ImGui::TableSetColumnIndex(2);

                if (!isDirectory) {

                    if (fileSize < 1024) {

                        ImGui::Text(
                            "%llu B",
                            fileSize
                        );

                    } else if (
                        fileSize <
                        1024ULL * 1024ULL) {

                        ImGui::Text(
                            "%.1f KB",
                            (float)fileSize /
                            1024.0f
                        );

                    } else {

                        ImGui::Text(
                            "%.2f MB",
                            (float)fileSize /
                            (1024.0f * 1024.0f)
                        );
                    }

                } else {

                    ImGui::TextUnformatted(
                        "--"
                    );
                }

                #pragma mark - Actions

                ImGui::TableSetColumnIndex(3);

                const char *baseName =
                    [fileName UTF8String];

                std::string baseID =
                    baseName
                        ? baseName
                        : "";

                if (!isDirectory) {

                    std::string viewBtnID =
                        "Oku##" +
                        baseID;

                    if (ImGui::Button(
                            viewBtnID.c_str())) {

                        self.selectedFilePath =
                            fullPath;

                        NSError *readError =
                            nil;

                        NSString *content =
                            [NSString
                                stringWithContentsOfFile:
                                    fullPath
                                encoding:
                                    NSUTF8StringEncoding
                                error:
                                    &readError];

                        if (content) {

                            self.fileContentString =
                                content;

                        } else {

                            NSString *errorMessage =
                                readError
                                    ? readError.localizedDescription
                                    : @"Bilinmeyen okuma hatası";

                            self.fileContentString =
                                [NSString stringWithFormat:
                                    @"[Okunamadı]: %@",
                                    errorMessage];
                        }

                        _isEditorOpen = YES;
                    }

                    ImGui::SameLine();
                }

                std::string delBtnID =
                    "Sil##" +
                    baseID;

                if (ImGui::Button(
                        delBtnID.c_str())) {

                    NSError *delError =
                        nil;

                    [fileManager
                        removeItemAtPath:
                            fullPath
                        error:
                            &delError];

                    if (!delError) {

                        [self loadDirectoryAtPath:
                            self.currentPath];

                        break;
                    }
                }
            }

            ImGui::EndTable();
        }

        ImGui::Text(
            "Toplam Öğe: %lu",
            (unsigned long)
                self.currentFiles.count
        );
    }

    ImGui::End();

    #pragma mark - Editor

    if (_isEditorOpen) {

        ImGui::SetNextWindowSize(
            ImVec2(600.0f, 450.0f),
            ImGuiCond_FirstUseEver
        );

        if (ImGui::Begin(
                "File Inspector / Editor",
                &_isEditorOpen,
                ImGuiWindowFlags_None)) {

            if (self.selectedFilePath) {

                const char *selectedName =
                    [[self.selectedFilePath
                        lastPathComponent]
                            UTF8String];

                ImGui::Text(
                    "Dosya: %s",
                    selectedName
                        ? selectedName
                        : ""
                );

                static char textBuffer[16384];

                static NSString *
                    lastLoadedPath = nil;

                if (lastLoadedPath !=
                    self.selectedFilePath) {

                    memset(
                        textBuffer,
                        0,
                        sizeof(textBuffer)
                    );

                    if (self.fileContentString) {

                        [self.fileContentString
                            getCString:
                                textBuffer
                            maxLength:
                                sizeof(textBuffer)
                            encoding:
                                NSUTF8StringEncoding];
                    }

                    lastLoadedPath =
                        [self.selectedFilePath copy];
                }

                ImGui::InputTextMultiline(
                    "##source",
                    textBuffer,
                    sizeof(textBuffer),
                    ImVec2(-1.0f, -45.0f),
                    ImGuiInputTextFlags_AllowTabInput
                );

                if (ImGui::Button(
                        "Değişiklikleri Kaydet")) {

                    NSString *updatedString =
                        [NSString
                            stringWithUTF8String:
                                textBuffer];

                    if (!updatedString) {

                        updatedString = @"";
                    }

                    NSError *writeError =
                        nil;

                    [updatedString
                        writeToFile:
                            self.selectedFilePath
                        atomically:
                            YES
                        encoding:
                            NSUTF8StringEncoding
                        error:
                            &writeError];

                    if (writeError) {

                        NSLog(
                            @"Kayıt hatası: %@",
                            writeError.localizedDescription
                        );

                    } else {

                        self.fileContentString =
                            updatedString;

                        lastLoadedPath =
                            [self.selectedFilePath copy];
                    }
                }

                ImGui::SameLine();

                if (ImGui::Button(
                        "Kapat")) {

                    _isEditorOpen = NO;
                }
            }
        }

        ImGui::End();
    }
}

@end
