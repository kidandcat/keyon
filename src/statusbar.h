#ifndef STATUSBAR_H
#define STATUSBAR_H

#include <stdbool.h>
#include <stdint.h>

void setupStatusBar(void (*onQuit)(void));
void removeStatusBar(void);
void hideFromDock(void);
uint16_t getCurrentHotkeyKeycode(void);
uint64_t getCurrentHotkeyModifiers(void);
void setWindowAboveAll(void);
void processCocoaEvents(void);
void setWindowIgnoresMouseEvents(void *nsWindow, bool ignores);

#endif
