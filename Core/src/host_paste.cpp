// Pasting text into DOS: characters go straight into the BIOS keyboard
// buffer (as typed keys would), so they come out right whatever the
// keyboard layout. The buffer only holds a few keys, so we top it up a
// little every millisecond until the text is done.

#include "host_state.h"

#include "ints/bios.h"

#include <array>

namespace {

/// US keyboard scancodes for printable ASCII (the high byte DOS programs
/// see next to the character). Index = character - 32.
constexpr std::array<uint8_t, 95> scancodes = {
	0x39, 0x02, 0x28, 0x04, 0x05, 0x06, 0x08, 0x28, 0x0A, 0x0B, 0x09, 0x0D, 0x33, 0x0C, 0x34, 0x35, // space…/
	0x0B, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A,                                     // 0…9
	0x27, 0x27, 0x33, 0x0D, 0x34, 0x35, 0x03,                                                       // :…@
	0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32,                   // A…M
	0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C,                   // N…Z
	0x1A, 0x2B, 0x1B, 0x07, 0x0C, 0x29,                                                             // [ \ ] ^ _ `
	0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32,                   // a…m
	0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C,                   // n…z
	0x1A, 0x2B, 0x1B, 0x29,                                                                         // { | } ~
};

/// The BIOS keycode for a character, or 0 to skip it.
uint16_t keycode(const char character)
{
	if (character == '\n') {
		return 0x1C0D;  // Enter
	}
	if (character == '\t') {
		return 0x0F09;
	}
	const auto value = static_cast<unsigned char>(character);
	if (value < 32 || value > 126) {
		return 0;
	}
	return static_cast<uint16_t>(scancodes[value - 32] << 8 | value);
}

} // namespace

void dosboxer::feed_paste_queue(std::mutex& mutex, std::string& queue)
{
	std::lock_guard lock(mutex);
	// A few characters per tick; the buffer holds 15
	size_t fed = 0;
	while (fed < queue.size() && fed < 4) {
		const auto code = keycode(queue[fed] == '\r' ? '\n' : queue[fed]);
		if (queue[fed] == '\r' && fed + 1 < queue.size() && queue[fed + 1] == '\n') {
			++fed;  // CRLF → one Enter
		}
		if (code != 0 && !BIOS_AddKeyToBuffer(code)) {
			break;  // full: try again next tick
		}
		++fed;
	}
	queue.erase(0, fed);
}
