#include "include/volume_controller/audio_controller.h"
#include <iostream>
#include <chrono>
#include <thread>

AudioController::AudioController()
    : cardName_("default")
{
    open_mixer();
}

AudioController::AudioController(const std::string cardName)
    : cardName_(cardName)
{
    open_mixer();
}

AudioController::~AudioController()
{
    stop_listening_for_volume_changes();

    if (master_element_)
    {
        master_element_ = nullptr;
    }
    if (mixerHandle_)
    {
        snd_mixer_close(mixerHandle_);
        mixerHandle_ = nullptr;
    }
}

void AudioController::open_mixer()
{
    if (snd_mixer_open(&mixerHandle_, 0))
    {
        throw std::runtime_error("Failed to open mixer");
    }

    if (snd_mixer_attach(mixerHandle_, cardName_.c_str()))
    {
        snd_mixer_close(mixerHandle_);
        mixerHandle_ = nullptr;
        throw std::runtime_error("Failed to attach mixer to card: " + cardName_);
    }

    if (snd_mixer_selem_register(mixerHandle_, nullptr, nullptr))
    {
        snd_mixer_close(mixerHandle_);
        mixerHandle_ = nullptr;
        throw std::runtime_error("Failed to register mixer elements");
    }

    if (snd_mixer_load(mixerHandle_))
    {
        snd_mixer_close(mixerHandle_);
        mixerHandle_ = nullptr;
        throw std::runtime_error("Failed to load mixer controls");
    }

    snd_mixer_elem_t *elem = get_mixer_element("Master");
    if (elem)
    {
        master_element_ = elem;
    }
    else
    {
        std::cerr << "Failed to find master mixer element." << std::endl;
        throw std::runtime_error("Master mixer element not found");
    }
}

snd_mixer_elem_t *AudioController::get_mixer_element(const std::string &channel) const
{
    if (!mixerHandle_)
    {
        throw std::runtime_error("Mixer not open");
    }
    snd_mixer_selem_id_t *sid;
    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_name(sid, channel.c_str());

    snd_mixer_elem_t *elem = snd_mixer_find_selem(mixerHandle_, sid);
    if (!elem)
    {
        throw std::runtime_error("Unable to find mixer control: " + channel);
    }
    return elem;
}

double AudioController::get_volume()
{
    if (!master_element_)
    {
        throw std::runtime_error("Mixer or master element not initialized for get_volume");
    }

    // Handle events to ensure we have the latest state
    snd_mixer_handle_events(mixerHandle_);

    long min, max;
    snd_mixer_selem_get_playback_volume_range(master_element_, &min, &max);
    if (max - min == 0)
        return 0.0;

    long volume;
    if (snd_mixer_selem_get_playback_volume(master_element_, SND_MIXER_SCHN_FRONT_LEFT, &volume))
    {
        throw std::runtime_error("Failed to get volume for Master channel");
    }

    return (double)(volume - min) / (max - min);
}

void AudioController::set_volume(double volume_percent)
{
    double volume_decimal = volume_percent;

    if (!master_element_ && !mixerHandle_)
    {
        throw std::runtime_error("Mixer or master element not initialized for set_volume");
    }
    snd_mixer_elem_t *elem_to_use = master_element_;
    if (!elem_to_use)
    {
        throw std::runtime_error("Failed to get Master element for set_volume");
    }

    long min, max;
    snd_mixer_selem_get_playback_volume_range(elem_to_use, &min, &max);

    long rawVolume = min + (long)((max - min) * volume_decimal);

    if (snd_mixer_selem_set_playback_volume_all(elem_to_use, rawVolume))
    {
        throw std::runtime_error("Failed to set volume for Master channel");
    }
}

bool AudioController::is_muted()
{
    if (!master_element_ && !mixerHandle_)
    {
        throw std::runtime_error("Mixer or master element not initialized for is_muted");
    }
    snd_mixer_elem_t *elem_to_use = master_element_;
    if (!elem_to_use)
    {
        throw std::runtime_error("Failed to get Master element for is_muted");
    }

    int mute_state;
    if (snd_mixer_selem_get_playback_switch(elem_to_use, SND_MIXER_SCHN_FRONT_LEFT, &mute_state))
    {
        throw std::runtime_error("Failed to get mute state for Master channel");
    }

    return mute_state == 0;
}

void AudioController::set_mute(bool mute)
{
    if (!master_element_ && !mixerHandle_)
    {
        throw std::runtime_error("Mixer or master element not initialized for set_mute");
    }
    snd_mixer_elem_t *elem_to_use = master_element_;
    if (!elem_to_use)
    {
        throw std::runtime_error("Failed to get Master element for set_mute");
    }

    if (snd_mixer_selem_set_playback_switch_all(elem_to_use, mute ? 0 : 1))
    {
        throw std::runtime_error("Failed to set mute state for Master channel");
    }
}

void AudioController::check_volume_and_notify()
{
    if (!master_element_ || !volume_change_callback_)
    {
        return;
    }

    double volume = get_volume();

    if (last_known_volume_ != volume)
    {
        last_known_volume_ = volume;
        volume_change_callback_(volume, callback_user_data_);
    }
}

gpointer AudioController::volume_listener_thread_func_static(gpointer data)
{
    AudioController *self = static_cast<AudioController *>(data);
    self->volume_listener_loop();
    return nullptr;
}

void AudioController::volume_listener_loop()
{
    bool fetch_initial_volume = this->fetch_initial_volume;
    bool check_volume_and_notify_called = false;
    double initial_volume = get_volume();

    if (fetch_initial_volume)
    {
        check_volume_and_notify_called = true;
    }

    while (listening_for_volume_changes_)
    {
        if (!listening_for_volume_changes_)
        {
            break;
        }

        if (check_volume_and_notify_called)
        {
            check_volume_and_notify();
        }
        else if (initial_volume != get_volume())
        {
            check_volume_and_notify_called = true;
            check_volume_and_notify();
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
}

bool AudioController::start_listening_for_volume_changes(VolumeChangeCallback callback, gpointer user_data)
{
    if (listening_for_volume_changes_)
    {
        return true;
    }

    volume_change_callback_ = callback;
    callback_user_data_ = user_data;
    listening_for_volume_changes_ = true;

    GError *error = nullptr;
    volume_listener_thread_ = g_thread_try_new("volume-listener", volume_listener_thread_func_static, this, &error);
    if (!volume_listener_thread_)
    {
        std::cerr << "Failed to create volume listener thread: " << (error ? error->message : "Unknown error") << std::endl;
        if (error)
            g_error_free(error);
        listening_for_volume_changes_ = false;
        return false;
    }

    return true;
}

void AudioController::stop_listening_for_volume_changes()
{
    if (!listening_for_volume_changes_)
    {
        return;
    }

    listening_for_volume_changes_ = false;

    if (volume_listener_thread_)
    {
        g_thread_join(volume_listener_thread_);
        volume_listener_thread_ = nullptr;
    }
}