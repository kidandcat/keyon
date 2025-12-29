#ifndef STATUSBAR_H
#define STATUSBAR_H

#include <stdbool.h>

void setupStatusBar(void (*onQuit)(void));
void removeStatusBar(void);
void hideFromDock(void);
void setWindowAboveAll(void);
void processCocoaEvents(void);
void setWindowIgnoresMouseEvents(void *nsWindow, bool ignores);

#endif
