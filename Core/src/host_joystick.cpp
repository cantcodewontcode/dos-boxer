// Game controllers. The app reads them (macOS only sends controller input to
// the frontmost app, and the engine is a background process) and forwards
// them here; we present them to DOS as virtual SDL joysticks laid out like
// an Xbox controller on Windows (XInput order), which is what DOSBox
// Staging's per-game controller mappings assume. Player 1's is always the
// first; adding player 2's switches DOS to two joysticks.

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

constexpr int PlayerCount = 2;
SDL_Joystick* virtual_joysticks[PlayerCount] = {nullptr, nullptr};

SDL_Joystick* attached(const int player)
{
	if (player < 0 || player >= PlayerCount) {
		return nullptr;
	}
	if (virtual_joysticks[player]) {
		return virtual_joysticks[player];
	}
	if (SDL_WasInit(SDL_INIT_JOYSTICK) != SDL_INIT_JOYSTICK) {
		return nullptr;  // the mapper hasn't set up joysticks yet
	}
	// Player 1's joystick comes first, so DOS sees it as joystick 1
	if (player > 0 && !attached(player - 1)) {
		return nullptr;
	}
	const int device = SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_GAMECONTROLLER,
	                                             AxisCount, ButtonCount, HatCount);
	if (device < 0) {
		LOG_WARNING("DOS BOXER: Couldn't add a game controller: %s", SDL_GetError());
		return nullptr;
	}
	virtual_joysticks[player] = SDL_JoystickOpen(device);
	LOG_MSG("DOS BOXER: Game controller for player %d connected", player + 1);
	return virtual_joysticks[player];
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

void dosboxer::joystick_input(const int player_and_kind, const int index, const int value)
{
	// Player (0 or 1) in the high bits, the kind of input in the low four
	SDL_Joystick* virtual_joystick = attached(player_and_kind >> 4);
	if (!virtual_joystick) {
		return;
	}
	switch (player_and_kind & 0xF) {
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
