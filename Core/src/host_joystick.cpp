// Game controllers. The app reads them (macOS only sends controller input to
// the frontmost app, and the engine is a background process) and forwards
// them here; we present them to DOS as one virtual SDL joystick laid out like
// an Xbox controller on Windows (XInput order), which is what DOSBox
// Staging's per-game controller mappings assume.

#include "host_state.h"

#include <SDL.h>

namespace {

// XInput order: 0 left X, 1 left Y, 2 left trigger, 3 right X, 4 right Y,
// 5 right trigger
constexpr int AxisCount = 6;
// 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 Back, 7 Start, 8 left stick, 9 right
// stick, 10 Guide
constexpr int ButtonCount = 11;
constexpr int HatCount    = 1;

SDL_Joystick* virtual_joystick = nullptr;

bool ensure_attached()
{
	if (virtual_joystick) {
		return true;
	}
	if (SDL_WasInit(SDL_INIT_JOYSTICK) != SDL_INIT_JOYSTICK) {
		return false;  // the mapper hasn't set up joysticks yet
	}
	const int device = SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_GAMECONTROLLER,
	                                             AxisCount, ButtonCount, HatCount);
	if (device < 0) {
		LOG_WARNING("DOS BOXER: Couldn't add a game controller: %s", SDL_GetError());
		return false;
	}
	virtual_joystick = SDL_JoystickOpen(device);
	LOG_MSG("DOS BOXER: Game controller connected");
	return virtual_joystick != nullptr;
}

} // namespace

void dosboxer::configure_joystick_hints()
{
	// Only our virtual controller: SDL's own drivers can't see controllers
	// from a background process anyway, and would show duplicates if they did
	SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI, "0");
	SDL_SetHint(SDL_HINT_JOYSTICK_IOKIT, "0");
	SDL_SetHint(SDL_HINT_JOYSTICK_MFI, "0");
	// The engine never has a focused window; accept input regardless
	SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
}

void dosboxer::joystick_input(const int kind, const int index, const int value)
{
	if (!ensure_attached()) {
		return;
	}
	switch (kind) {
	case 0:
		if (index >= 0 && index < AxisCount) {
			SDL_JoystickSetVirtualAxis(virtual_joystick, index, static_cast<Sint16>(value));
		}
		break;
	case 1:
		if (index >= 0 && index < ButtonCount) {
			SDL_JoystickSetVirtualButton(virtual_joystick, index, value ? 1 : 0);
		}
		break;
	case 2:
		SDL_JoystickSetVirtualHat(virtual_joystick, 0, static_cast<Uint8>(value));
		break;
	default: break;
	}
}
