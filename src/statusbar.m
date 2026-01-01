#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

static NSStatusItem *statusItem = nil;
static void (*quitCallback)(void) = NULL;
static NSMenuItem *hotkeyMenuItem = nil;

// Current hotkey settings (default: Cmd+<)
static uint16_t currentKeycode = 50; // < key
static uint64_t currentModifiers = 0x100000; // Cmd

@interface StatusBarDelegate : NSObject
- (void)quitApp:(id)sender;
- (void)changeHotkey:(id)sender;
@end

@interface HotkeyRecorderWindow : NSWindow <NSWindowDelegate>
@property (nonatomic, assign) BOOL isRecording;
@end

@implementation HotkeyRecorderWindow

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    if (!self.isRecording) return;

    NSEventModifierFlags flags = event.modifierFlags;

    // Require at least one modifier (Cmd, Ctrl, Alt, or Shift)
    BOOL hasModifier = (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                                  NSEventModifierFlagOption | NSEventModifierFlagShift)) != 0;

    if (!hasModifier) {
        return; // Ignore keys without modifiers
    }

    // Save the new hotkey
    currentKeycode = event.keyCode;
    currentModifiers = 0;
    if (flags & NSEventModifierFlagCommand) currentModifiers |= 0x100000;
    if (flags & NSEventModifierFlagShift) currentModifiers |= 0x20000;
    if (flags & NSEventModifierFlagOption) currentModifiers |= 0x80000;
    if (flags & NSEventModifierFlagControl) currentModifiers |= 0x40000;

    // Update menu item
    [self updateHotkeyMenuTitle];

    // Close window
    self.isRecording = NO;
    [self close];
}

- (void)updateHotkeyMenuTitle {
    if (hotkeyMenuItem) {
        NSString *hotkeyStr = [self hotkeyString];
        [hotkeyMenuItem setTitle:[NSString stringWithFormat:@"Hotkey: %@", hotkeyStr]];
    }
}

- (NSString *)hotkeyString {
    NSMutableString *str = [NSMutableString string];

    if (currentModifiers & 0x40000) [str appendString:@"⌃"];
    if (currentModifiers & 0x80000) [str appendString:@"⌥"];
    if (currentModifiers & 0x20000) [str appendString:@"⇧"];
    if (currentModifiers & 0x100000) [str appendString:@"⌘"];

    // Convert keycode to character using simple mapping for common keys
    NSString *keyChar = nil;
    switch (currentKeycode) {
        case 0: keyChar = @"A"; break;
        case 1: keyChar = @"S"; break;
        case 2: keyChar = @"D"; break;
        case 3: keyChar = @"F"; break;
        case 4: keyChar = @"H"; break;
        case 5: keyChar = @"G"; break;
        case 6: keyChar = @"Z"; break;
        case 7: keyChar = @"X"; break;
        case 8: keyChar = @"C"; break;
        case 9: keyChar = @"V"; break;
        case 11: keyChar = @"B"; break;
        case 12: keyChar = @"Q"; break;
        case 13: keyChar = @"W"; break;
        case 14: keyChar = @"E"; break;
        case 15: keyChar = @"R"; break;
        case 16: keyChar = @"Y"; break;
        case 17: keyChar = @"T"; break;
        case 18: keyChar = @"1"; break;
        case 19: keyChar = @"2"; break;
        case 20: keyChar = @"3"; break;
        case 21: keyChar = @"4"; break;
        case 22: keyChar = @"6"; break;
        case 23: keyChar = @"5"; break;
        case 24: keyChar = @"="; break;
        case 25: keyChar = @"9"; break;
        case 26: keyChar = @"7"; break;
        case 27: keyChar = @"-"; break;
        case 28: keyChar = @"8"; break;
        case 29: keyChar = @"0"; break;
        case 31: keyChar = @"O"; break;
        case 32: keyChar = @"U"; break;
        case 34: keyChar = @"I"; break;
        case 35: keyChar = @"P"; break;
        case 37: keyChar = @"L"; break;
        case 38: keyChar = @"J"; break;
        case 40: keyChar = @"K"; break;
        case 45: keyChar = @"N"; break;
        case 46: keyChar = @"M"; break;
        case 50: keyChar = @"<"; break;
        default: keyChar = [NSString stringWithFormat:@"[%d]", currentKeycode]; break;
    }

    [str appendString:keyChar];
    return str;
}

@end

@implementation StatusBarDelegate

- (void)quitApp:(id)sender {
    if (quitCallback) {
        quitCallback();
    }
    exit(0);
}

- (void)changeHotkey:(id)sender {
    // Create recorder window
    NSRect frame = NSMakeRect(0, 0, 300, 100);
    HotkeyRecorderWindow *window = [[HotkeyRecorderWindow alloc]
        initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered
        defer:NO];

    [window setTitle:@"Press new hotkey"];
    [window setLevel:NSFloatingWindowLevel];
    [window center];

    // Add label
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 260, 40)];
    [label setStringValue:@"Press a key combination\n(must include ⌘, ⌃, ⌥, or ⇧)"];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setAlignment:NSTextAlignmentCenter];
    [[window contentView] addSubview:label];

    window.isRecording = YES;
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:window];
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

    hotkeyMenuItem = [[NSMenuItem alloc] initWithTitle:@"Hotkey: ⌘<" action:@selector(changeHotkey:) keyEquivalent:@""];
    [hotkeyMenuItem setTarget:delegate];
    [menu addItem:hotkeyMenuItem];

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

void hideFromDock(void) {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

uint16_t getCurrentHotkeyKeycode(void) {
    return currentKeycode;
}

uint64_t getCurrentHotkeyModifiers(void) {
    return currentModifiers;
}

void setWindowAboveAll(void) {
    // Set all app windows to be above everything (including other topmost windows)
    for (NSWindow *window in [NSApp windows]) {
        [window setLevel:CGShieldingWindowLevel()];
        [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary];
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
