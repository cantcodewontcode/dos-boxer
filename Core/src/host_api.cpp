// The DOSBoxerHost C API: runs dosbox-staging's main() on a background thread
// and bridges video, audio and input to the embedding app.

#include "DOSBoxerHost.h"
#include "host_renderer.h"
#include "host_state.h"

#include "dosbox.h"
#include "dosboxer/dosboxer_hooks.h"

#include <SDL.h>

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// dosbox-staging's main(), renamed at compile time (see Core/CMakeLists.txt)
int dosbox_staging_main(int argc, char* argv[]);

namespace {

constexpr int32_t SampleRateHz = 48000;

std::mutex lifecycle_mutex;
std::thread emulator_thread;
std::atomic<bool> is_running = false;

// Written before the thread starts, read on the emulator thread
DBXFrameCallback frame_callback = nullptr;
DBXExitCallback exit_callback   = nullptr;
void* callback_context          = nullptr;

// Work for the emulator thread, queued from any thread
std::mutex request_mutex;
std::vector<std::function<void()>> requests;
std::atomic<bool> has_requests = false;

void queue_request(std::function<void()> request)
{
	std::lock_guard lock(request_mutex);
	requests.push_back(std::move(request));
	has_requests = true;
}

void push_event(SDL_Event& event)
{
	if (is_running) {
		SDL_PushEvent(&event);
	}
}

} // namespace

// --- Hooks called by the patched core ---------------------------------------

RenderBackend* DOSBOXER_CreateRenderBackend()
{
	return new HostRenderer();
}

void DOSBOXER_ProcessHostRequests()
{
	if (!has_requests) {
		return;
	}
	std::vector<std::function<void()>> pending;
	{
		std::lock_guard lock(request_mutex);
		pending.swap(requests);
		has_requests = false;
	}
	for (auto& request : pending) {
		request();
	}
}

bool DOSBOXER_IgnoreSdlQuit()
{
	return true;
}

bool DOSBOXER_HostAudioEnabled()
{
	return true;
}

void dosboxer::deliver_frame(const DBXFrame& frame)
{
	if (frame_callback) {
		frame_callback(callback_context, &frame);
	}
}

// --- Public API -------------------------------------------------------------

bool dbx_start(const char* const* args, const int32_t arg_count,
               const DBXFrameCallback on_frame, const DBXExitCallback on_exit,
               void* const context)
{
	std::lock_guard lock(lifecycle_mutex);
	if (is_running) {
		return false;
	}
	if (emulator_thread.joinable()) {
		emulator_thread.join();
	}

	// Keep SDL away from Cocoa: no real windows, no main-thread requirements
	setenv("SDL_VIDEODRIVER", "dummy", 1);

	// SDL outlives each run; drop any events left over from a previous one
	SDL_FlushEvents(SDL_FIRSTEVENT, SDL_LASTEVENT);

	std::vector<std::string> owned_args = {"dosbox"};
	for (int32_t i = 0; i < arg_count; ++i) {
		owned_args.emplace_back(args[i]);
	}
	// Settings the embedded renderer relies on
	for (const char* setting : {"sdl fullscreen=false",
	                            "render integer_scaling=off",
	                            "mixer rate=48000",
	                            "sdl presentation_mode=dos-rate"}) {
		owned_args.emplace_back("--set");
		owned_args.emplace_back(setting);
	}

	frame_callback   = on_frame;
	exit_callback    = on_exit;
	callback_context = context;
	is_running       = true;

	emulator_thread = std::thread([owned_args = std::move(owned_args)]() mutable {
		std::vector<char*> argv;
		for (auto& arg : owned_args) {
			argv.push_back(arg.data());
		}
		argv.push_back(nullptr);

		const int exit_code = dosbox_staging_main(static_cast<int>(owned_args.size()),
		                                          argv.data());
		is_running = false;
		if (exit_callback) {
			exit_callback(callback_context, exit_code);
		}
	});
	return true;
}

void dbx_request_quit(void)
{
	if (is_running) {
		DOSBOX_RequestShutdown();
	}
}

bool dbx_is_running(void)
{
	return is_running;
}

void dbx_mount_folder(const char drive_letter, const char* const path)
{
	if (!is_running || !path) {
		return;
	}
	queue_request([drive_letter, folder = std::string(path)] {
		dosboxer::mount_folder(drive_letter, folder);
	});
}

void dbx_pull_audio(float* const interleaved_stereo, const int32_t frame_count)
{
	if (!is_running) {
		std::memset(interleaved_stereo, 0, sizeof(float) * 2 * frame_count);
		return;
	}
	DOSBOXER_MixerPull(interleaved_stereo, frame_count);
}

int32_t dbx_audio_sample_rate(void)
{
	return SampleRateHz;
}

void dbx_key(const int32_t scancode, const bool down)
{
	SDL_Event event          = {};
	event.type               = down ? SDL_KEYDOWN : SDL_KEYUP;
	event.key.state          = down ? SDL_PRESSED : SDL_RELEASED;
	event.key.keysym.scancode = static_cast<SDL_Scancode>(scancode);
	event.key.keysym.sym     = SDL_GetKeyFromScancode(event.key.keysym.scancode);
	push_event(event);
}

void dbx_mouse_motion(const float dx, const float dy)
{
	SDL_Event event    = {};
	event.type         = SDL_MOUSEMOTION;
	event.motion.xrel  = static_cast<Sint32>(dx);
	event.motion.yrel  = static_cast<Sint32>(dy);
	push_event(event);
}

void dbx_mouse_button(const int32_t button, const bool down)
{
	SDL_Event event      = {};
	event.type           = down ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
	event.button.button  = static_cast<Uint8>(button);
	event.button.state   = down ? SDL_PRESSED : SDL_RELEASED;
	event.button.clicks  = 1;
	push_event(event);
}
