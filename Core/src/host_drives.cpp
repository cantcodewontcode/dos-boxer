// Mounting drives while DOS is running, the way Boxer did: create and swap
// the drive objects directly on the emulator thread instead of typing MOUNT.

#include "host_state.h"

#include "dosbox.h"
#include "config/config.h"
#include "dos/dos.h"
#include "dos/drives.h"
#include "dos/programs/mount_common.h"
#include "misc/support.h"

#include <SDL.h>

#include <cctype>
#include <filesystem>
#include <string>

namespace {

// Same geometry dosbox uses for a plain `MOUNT C folder`:
// 512-byte sectors × 32 per cluster × 32765 clusters ≈ 500 MB, 250 MB free
constexpr uint16_t BytesPerSector    = 512;
constexpr uint8_t SectorsPerCluster  = 32;
constexpr uint16_t TotalClusters     = 32765;
constexpr uint16_t FreeClusters      = 16000;

void unmount(const uint8_t index)
{
	if (!Drives.at(index)) {
		return;
	}
	DriveManager::UnmountDrive(index);
	Drives.at(index) = nullptr;
	mem_writeb(RealToPhysical(dos.tables.mediaid) + index * 9, 0);
	if (index == DOS_GetDefaultDrive()) {
		DOS_SetDrive(ZDRIVE_NUM);
	}
}

/// Presses and releases Enter, so an idle prompt redraws itself.
void tap_enter()
{
	for (const auto type : {SDL_KEYDOWN, SDL_KEYUP}) {
		SDL_Event event           = {};
		event.type                = type;
		event.key.state           = type == SDL_KEYDOWN ? SDL_PRESSED : SDL_RELEASED;
		event.key.keysym.scancode = SDL_SCANCODE_RETURN;
		event.key.keysym.sym      = SDLK_RETURN;
		SDL_PushEvent(&event);
	}
}

} // namespace

bool dosboxer::mount_folder(const char letter, const std::string& path)
{
	const auto upper = static_cast<char>(toupper(letter));
	if (upper < 'C' || upper > 'Y') {
		return false;
	}
	std::error_code error;
	if (!std::filesystem::is_directory(path, error)) {
		LOG_WARNING("DOS BOXER: Can't mount '%s': not a folder", path.c_str());
		return false;
	}

	const auto index    = drive_index(upper);
	const bool was_on_z = DOS_GetDefaultDrive() == ZDRIVE_NUM;

	// localDrive wants a trailing separator
	auto folder = path;
	if (!folder.ends_with('/')) {
		folder += '/';
	}

	unmount(index);

	const auto section = get_section("dosbox");
	auto drive = std::make_shared<localDrive>(folder.c_str(),
	                                          BytesPerSector,
	                                          SectorsPerCluster,
	                                          TotalClusters,
	                                          FreeClusters,
	                                          MediaId::HardDisk,
	                                          false,
	                                          section->GetBool("allow_write_protected_files"));

	DriveManager::RegisterFilesystemImage(index, drive);
	Drives.at(index) = drive;
	mem_writeb(RealToPhysical(dos.tables.mediaid) + index * 9, drive->GetMediaByte());

	const std::string label = std::string(1, upper) + "_DRIVE";
	drive->dirCache.SetLabel(label.c_str(), false, false);

	LOG_MSG("DOS BOXER: Mounted '%s' as drive %c", folder.c_str(), upper);

	// At the bare Z: prompt, move to the new drive so it's ready to use
	if (was_on_z) {
		DOS_SetDrive(index);
		tap_enter();
	}
	return true;
}
