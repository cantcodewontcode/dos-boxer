// Internal state shared between the host API and the host renderer.

#ifndef DOSBOXER_HOST_STATE_H
#define DOSBOXER_HOST_STATE_H

#include "DOSBoxerHost.h"

namespace dosboxer {

void deliver_frame(const DBXFrame& frame);

} // namespace dosboxer

#endif
