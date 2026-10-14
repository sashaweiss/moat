#pragma once

#include <sys/ioctl.h>

/// TIOCSWINSZ, which Swift doesn't import because it's a function-like macro.
static const unsigned long kTIOCSWINSZ = TIOCSWINSZ;
