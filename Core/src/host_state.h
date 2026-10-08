// Internal state shared between the host API and the host renderer.

#ifndef DOSBOXER_HOST_STATE_H
#define DOSBOXER_HOST_STATE_H

#include "DOSBoxerHost.h"

#include <mutex>
#include <string>

#include "misc/logging.h"

namespace dosboxer {

void deliver_frame(const DBXFrame& frame);

// Emulator thread only: mounts a host folder as a DOS drive, replacing any
// drive already using that letter.
bool mount_folder(char letter, const std::string& path);

// Emulator thread only: moves a few queued characters into DOS's keyboard
// buffer, as it has room.
void feed_paste_queue(std::mutex& mutex, std::string& queue);

// Before SDL starts: use only the virtual game controller.
void configure_joystick_hints();
// Connects virtual joysticks for this many players (0–2) before DOSBox starts.
void connect_joysticks(int players);

// Emulator thread only: kind 0 axis (-32768…32767), 1 button (0/1), 2 hat
// (SDL_HAT_* bits).
void joystick_input(int kind, int index, int value);

} // namespace dosboxer

#endif
