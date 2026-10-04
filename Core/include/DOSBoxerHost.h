// DOSBoxerHost — the only header the Swift side sees.
//
// A plain C API around the embedded dosbox-staging core. The emulator runs on
// its own thread; every function here is safe to call from any thread unless
// noted otherwise.

#ifndef DOSBOXER_HOST_H
#define DOSBOXER_HOST_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One finished emulator frame. Pixels are 32-bit BGRA in memory order
/// (alpha is always opaque). Only valid for the duration of the callback.
typedef struct {
	const uint8_t* pixels;
	int32_t width;
	int32_t height;
	int32_t bytes_per_row;
	/// Display aspect ratio (width / height) the frame should be shown at.
	float display_aspect;
} DBXFrame;

typedef void (*DBXFrameCallback)(void* context, const DBXFrame* frame);
typedef void (*DBXExitCallback)(void* context, int32_t exit_code);

/// Starts the emulator on a background thread.
///
/// `args` are dosbox command-line arguments (without the program name), e.g.
/// `-c "MOUNT C /path"`. Returns false if an emulator is already running.
bool dbx_start(const char* const* args, int32_t arg_count,
               DBXFrameCallback on_frame, DBXExitCallback on_exit,
               void* context);

/// Asks the emulator to quit. `on_exit` is called when it has stopped.
void dbx_request_quit(void);

bool dbx_is_running(void);

/// Mounts a host folder as a DOS drive (C–Y) while DOS is running, replacing
/// any drive with that letter. If DOS is sitting at the Z: prompt, it switches
/// to the new drive.
void dbx_mount_folder(char drive_letter, const char* path);

/// Runs one of the emulator's built-in actions by name, as if its hotkey
/// were pressed: "cycleup" (faster), "cycledown" (slower), "swapimg" (next
/// disc).
void dbx_trigger(const char* action);

/// Pauses or resumes the emulator (sound stops while paused).
void dbx_set_paused(bool paused);

/// Types `text` (UTF-8; printable ASCII, tabs and line breaks) into DOS, as
/// if typed on the keyboard.
void dbx_paste_text(const char* text);

/// Game controller input, laid out like an Xbox controller (XInput order).
/// kind 0: axis 0–5 (left X, left Y, left trigger, right X, right Y, right
/// trigger), value -32768…32767. kind 1: button 0–10 (A, B, X, Y, LB, RB,
/// Back, Start, left stick, right stick, Guide), value 0/1. kind 2: d-pad,
/// value = up 1 | right 2 | down 4 | left 8.
void dbx_joystick(int32_t kind, int32_t index, int32_t value);

/// Fills `frame_count` interleaved stereo float frames. Real-time safe:
/// call this from the audio render thread. Writes silence when not running.
void dbx_pull_audio(float* interleaved_stereo, int32_t frame_count);

/// The sample rate the mixer runs at, in Hz.
int32_t dbx_audio_sample_rate(void);

/// Keyboard input by USB HID usage / SDL scancode.
void dbx_key(int32_t scancode, bool down);

/// Relative mouse motion in host points.
void dbx_mouse_motion(float dx, float dy);

/// Mouse buttons: 1 = left, 2 = middle, 3 = right.
void dbx_mouse_button(int32_t button, bool down);

#ifdef __cplusplus
}
#endif

#endif
