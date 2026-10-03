// Internal state shared between the host API and the host renderer.

#ifndef DOSBOXER_HOST_STATE_H
#define DOSBOXER_HOST_STATE_H

#include "DOSBoxerHost.h"

#include <string>

namespace dosboxer {

void deliver_frame(const DBXFrame& frame);

// Emulator thread only: mounts a host folder as a DOS drive, replacing any
// drive already using that letter.
bool mount_folder(char letter, const std::string& path);

} // namespace dosboxer

#endif
