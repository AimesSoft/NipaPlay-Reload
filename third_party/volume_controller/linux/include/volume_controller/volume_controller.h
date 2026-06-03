#include <flutter_linux/flutter_linux.h>
#include "audio_controller.h"

#ifndef VOLUME_CONTROLLER_H
#define VOLUME_CONTROLLER_H

FlMethodResponse *get_volume(AudioController *controller);
FlMethodResponse *set_volume(AudioController *controller, double volume);
FlMethodResponse *is_muted(AudioController *controller);
FlMethodResponse *set_mute(AudioController *controller, bool mute);

#endif // VOLUME_CONTROLLER_H
