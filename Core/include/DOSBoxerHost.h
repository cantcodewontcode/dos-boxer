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
