#pragma once

#include <sys/ioctl.h>

// Swift doesn't import these, because they're function-like macros.

/// TIOCGWINSZ, to get a terminal's window size.
static const unsigned long kTIOCGWINSZ = TIOCGWINSZ;

/// TIOCSWINSZ, to set a terminal's window size.
static const unsigned long kTIOCSWINSZ = TIOCSWINSZ;
