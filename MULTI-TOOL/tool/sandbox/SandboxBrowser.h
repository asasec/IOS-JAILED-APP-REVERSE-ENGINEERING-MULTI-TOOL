#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SandboxBrowser : NSObject {
    BOOL _isWindowOpen;
    BOOL _isEditorOpen;
}

@property (nonatomic, strong) NSString *currentPath;
@property (nonatomic, strong) NSArray *currentFiles;
@property (nonatomic, assign) BOOL isWindowOpen;

@property (nonatomic, strong) NSString *selectedFilePath;
@property (nonatomic, strong) NSString *fileContentString;
@property (nonatomic, assign) BOOL isEditorOpen;

+ (instancetype)sharedInstance;
- (void)loadDirectoryAtPath:(NSString *)path;
- (void)renderImGuiWindow;

@end
