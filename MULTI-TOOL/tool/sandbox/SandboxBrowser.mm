#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <string>
#include <vector>

@interface SandboxBrowser : NSObject

@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSArray *currentFiles;
@property (nonatomic, assign) BOOL isWindowOpen;

// Dosya içerik görüntüleme/düzenleme için state değişkenleri
@property (nonatomic, strong) NSString *selectedFilePath;
@property (nonatomic, strong) NSString *fileContentString;
@property (nonatomic, assign) BOOL isEditorOpen;

+ (instancetype)sharedInstance;
- (void)loadDirectoryAtPath:(NSString *)path;
- (void)renderImGuiWindow;

@end

@implementation SandboxBrowser

+ (instancetype)sharedInstance {
    static SandboxBrowser *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[SandboxBrowser alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Varsayılan olarak uygulamanın ev (sandbox) dizini ile başla
        [self loadDirectoryAtPath:NSHomeDirectory()];
        self.isWindowOpen = YES;
        self.isEditorOpen = NO;
    }
    return self;
}

- (void)loadDirectoryAtPath:(NSString *)path {
    self.currentPath = path;
    NSError *error = nil;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
    if (!error) {
        // Alfabetik sıralama (Klasörler üstte, dosyalar altta olacak şekilde optimize edilebilir)
        self.currentFiles = [contents sortedArrayUsingSelector:@compare:];
    } else {
        NSLog(@"SandboxBrowser Error: %@", error.localizedDescription);
        self.currentFiles = @[];
    }
}

- (void)renderImGuiWindow {
    if (!self.isWindowOpen) return;

    // Ana Dosya Yöneticisi Penceresi
    ImGui::SetNextWindowSize(ImVec2(600, 450), ImGuiCond_FirstUseEver);
    if (ImGui::Begin("Advanced Sandbox Browser", &self.isWindowOpen, ImGuiWindowFlags_None)) {
        
        // Üst Kısım: Yol Bilgisi ve Navigasyon Butonları
        ImGui::Text("Aktif Konum:");
        ImGui::BeginChild("PathChild", ImVec2(0, 30), false, ImGuiWindowFlags_HorizontalScrollbar);
        ImGui::Text("%s", [self.currentPath UTF8String]);
        ImGui::EndChild();

        if (![self.currentPath isEqualToString:NSHomeDirectory()]) {
            if (ImGui::Button("<- Bir Üst Dizin")) {
                NSString *parentPath = [self.currentPath stringByDeletingLastPathComponent];
                [self loadDirectoryAtPath:parentPath];
            }
            ImGui::SameLine();
        }

        if (ImGui::Button("Ev Dizini (Home)")) {
            [self loadDirectoryAtPath:NSHomeDirectory()];
        }
        ImGui::SameLine();

        if (ImGui::Button("Yenile")) {
            [self loadDirectoryAtPath:self.currentPath];
        }

        ImGui::Separator();

        // Dosya Tablosu
        float footerHeight = 40.0f;
        if (ImGui::BeginTable("SandboxTable", 4, ImGuiTableFlags_Borders | ImGuiTableFlags_RowBg | ImGuiTableFlags_ScrollY | ImGuiTableFlags_SizingFixedFit, ImVec2(0, -footerHeight))) {
            
            ImGui::TableSetupColumn("İsim", ImGuiTableColumnFlags_WidthStretch);
            ImGui::TableSetupColumn("Tür", ImGuiTableColumnFlags_WidthFixed, 50.0f);
            ImGui::TableSetupColumn("Boyut", ImGuiTableColumnFlags_WidthFixed, 70.0f);
            ImGui::TableSetupColumn("İşlemler", ImGuiTableColumnFlags_WidthFixed, 130.0f);
            ImGui::TableHeadersRow();

            NSFileManager *fileManager = [NSFileManager defaultManager];

            for (NSString *fileName in self.currentFiles) {
                NSString *fullPath = [self.currentPath stringByAppendingPathComponent:fileName];
                
                BOOL isDirectory = NO;
                [fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory];

                // Dosya özniteliklerini al (Boyut için)
                NSDictionary *attrs = [fileManager attributesOfItemAtPath:fullPath error:nil];
                unsigned long long fileSize = [attrs fileSize];

                ImGui::TableNextRow();
                
                // Sütun 0: İsim
                ImGui::TableSetColumnIndex(0);
                std::string displayName = (isDirectory ? "[D] " : "[F] ") + std::string([fileName UTF8String]);
                
                if (ImGui::Selectable(displayName.c_str(), false, ImGuiSelectableFlags_SpanAllColumns)) {
                    if (isDirectory) {
                        [self loadDirectoryAtPath:fullPath];
                        break; // Döngü güvenliği
                    }
                }

                // Sütun 1: Tür
                ImGui::TableSetColumnIndex(1);
                ImGui::Text(isDirectory ? "Dir" : "File");

                // Sütun 2: Boyut
                ImGui::TableSetColumnIndex(2);
                if (!isDirectory) {
                    if (fileSize < 1024) {
                        ImGui::Text("%llu B", fileSize);
                    } else if (fileSize < 1024 * 1024) {
                        ImGui::Text("%.1f KB", (float)fileSize / 1024.0f);
                    } else {
                        ImGui::Text("%.2f MB", (float)fileSize / (1024.0f * 1024.0f));
                    }
                } else {
                    ImGui::Text("--");
                }

                // Sütun 3: İşlemler (Görüntüle / Sil)
                ImGui::TableSetColumnIndex(3);
                std::string baseID = std::string([fileName UTF8String]);
                
                if (!isDirectory) {
                    std::string viewBtnID = "Oku##" + baseID;
                    if (ImGui::Button(viewBtnID.c_str())) {
                        self.selectedFilePath = fullPath;
                        NSError *readError = nil;
                        NSString *content = [NSString stringWithContentsOfFile:fullPath encoding:NSUTF8StringEncoding error:&readError];
                        if (content) {
                            self.fileContentString = content;
                        } else {
                            self.fileContentString = [NSString stringWithFormat:@"[Okunamadı veya Binary Dosya]: %@", readError.localizedDescription];
                        }
                        self.isEditorOpen = YES;
                    }
                    ImGui::SameLine();
                }

                std::string delBtnID = "Sil##" + baseID;
                if (ImGui::Button(delBtnID.c_str())) {
                    NSError *delError = nil;
                    [fileManager removeItemAtPath:fullPath error:&delError];
                    if (!delError) {
                        [self loadDirectoryAtPath:self.currentPath];
                        break;
                    }
                }
            }
            ImGui::EndTable();
        }

        // Alt Bilgi
        ImGui::Text("Toplam Öğe: %lu", (unsigned long)self.currentFiles.count);
    }
    ImGui::End();

    // İkinci Pencere: Dosya İçerik / Düzenleme Görüntüleyicisi
    if (self.isEditorOpen) {
        ImGui::SetNextWindowSize(ImVec2(500, 400), ImGuiCond_FirstUseEver);
        if (ImGui::Begin("File Inspector / Editor", &self.isEditorOpen, ImGuiWindowFlags_None)) {
            
            if (self.selectedFilePath) {
                ImGui::Text("Dosya: %s", [[self.selectedFilePath lastPathComponent] UTF8String]);
                
                // İçeriği göstermek için statik buffer yönetimi
                static char textBuffer[16384];
                static NSString *lastLoadedPath = nil;
                
                if (lastLoadedPath != self.selectedFilePath) {
                    memset(textBuffer, 0, sizeof(textBuffer));
                    [self.fileContentString getCString:textBuffer maxLength:sizeof(textBuffer) encoding:NSUTF8StringEncoding];
                    lastLoadedPath = self.selectedFilePath;
                }

                ImGui::InputTextMultiline("##source", textBuffer, sizeof(textBuffer), ImVec2(-1, -40), ImGuiInputTextFlags_AllowTabInput);

                if (ImGui::Button("Değişiklikleri Kaydet")) {
                    NSString *updatedString = [NSString stringWithUTF8String:textBuffer];
                    NSError *writeError = nil;
                    [updatedString writeToFile:self.selectedFilePath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
                    if (writeError) {
                        NSLog(@"Kayıt hatası: %@", writeError.localizedDescription);
                    }
                }
            }
        }
        ImGui::End();
    }
}

@end
