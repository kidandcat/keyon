#import <Cocoa/Cocoa.h>

static NSStatusItem *statusItem = nil;
static void (*quitCallback)(void) = NULL;

@interface StatusBarDelegate : NSObject
- (void)quitApp:(id)sender;
@end

@implementation StatusBarDelegate
- (void)quitApp:(id)sender {
    if (quitCallback) {
        quitCallback();
    }
    exit(0);
}
@end

static StatusBarDelegate *delegate = nil;

void setupStatusBar(void (*onQuit)(void)) {
    quitCallback = onQuit;

    // Ensure we're on the main thread and have an NSApplication
    if (NSApp == nil) {
        [NSApplication sharedApplication];
    }

    // Create status bar item
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    // Set the icon (using SF Symbol or fallback to text)
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:@"cursorarrow.click" accessibilityDescription:@"KeyOn"];
        if (image) {
            [image setTemplate:YES];
            statusItem.button.image = image;
        } else {
            statusItem.button.title = @"K";
        }
    } else {
        statusItem.button.title = @"K";
    }

    // Create menu
    NSMenu *menu = [[NSMenu alloc] init];

    // Create delegate
    delegate = [[StatusBarDelegate alloc] init];

    // Add menu items
    NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"KeyOn" action:nil keyEquivalent:@""];
    [titleItem setEnabled:NO];
    [menu addItem:titleItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *hotkeyItem = [[NSMenuItem alloc] initWithTitle:@"Hotkey: ⌘<" action:nil keyEquivalent:@""];
    [hotkeyItem setEnabled:NO];
    [menu addItem:hotkeyItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quitApp:) keyEquivalent:@"q"];
    [quitItem setTarget:delegate];
    [menu addItem:quitItem];

    statusItem.menu = menu;
}

void removeStatusBar(void) {
    if (statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
        statusItem = nil;
    }
}

void processCocoaEvents(void) {
    @autoreleasepool {
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                           untilDate:nil
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES])) {
            [NSApp sendEvent:event];
        }
    }
}

// Make a window ignore mouse events (pass-through)
void setWindowIgnoresMouseEvents(void *nsWindow, bool ignores) {
    if (nsWindow) {
        NSWindow *window = (__bridge NSWindow *)nsWindow;
        [window setIgnoresMouseEvents:ignores];
    }
}
