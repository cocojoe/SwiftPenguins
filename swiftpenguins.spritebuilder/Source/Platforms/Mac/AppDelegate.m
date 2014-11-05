#import "AppDelegate.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet CCGLView *glView;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Incorporate Mac Fixes http://forum.spritebuilder.com/t/mac-target-window-size/2161/4
    
    // Fix - Window Size
    [self.glView setFrameSize:self.window.frame.size];
    [self.glView setFrameOrigin:CGPointZero];
    
    CCDirectorMac *director = (CCDirectorMac*) [CCDirector sharedDirector];

    // enable FPS and SPF
    // [director setDisplayStats:YES];

    // connect the OpenGL view with the director
    [director setView:self.glView];

    // 'Effects' don't work correctly when autoscale is turned on.
    // Use kCCDirectorResize_NoScale if you don't want auto-scaling.
    [director setResizeMode:kCCDirectorResize_NoScale];

    // Enable "moving" mouse event. Default no.
    [self.window setAcceptsMouseMovedEvents:NO];

    // Center main window
    [self.window center];
    
    // Fix - Layout (Penguins uses 2x Assets so not required)
    //director.contentScaleFactor *= 2.0;
    //director.UIScaleFactor = 0.5;
    //[[CCFileUtils sharedFileUtils] setMacContentScaleFactor:2.0];

    // Configure CCFileUtils to work with SpriteBuilder
    [CCBReader configureCCFileUtils];

    [director runWithScene:[CCBReader loadAsScene:@"MainScene"]];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
}

@end
