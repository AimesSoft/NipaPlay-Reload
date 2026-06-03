#include "include/volume_controller/audio_controller.h"

#include <flutter_linux/flutter_linux.h>

FlMethodResponse *get_volume(AudioController *controller)
{
    try
    {
        double volume = controller->get_volume();
        g_autoptr(FlValue) result = fl_value_new_float(volume);
        return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
    catch (const std::exception &e)
    {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("Error", e.what(), NULL));
    }
}

FlMethodResponse *set_volume(AudioController *controller, double volume)
{
    try
    {
        if (volume < 0.0 || volume > 1.0)
        {
            return FL_METHOD_RESPONSE(fl_method_error_response_new("InvalidArgument", "Volume must be between 0 and 1", NULL));
        }
        controller->set_volume(volume);
        return FL_METHOD_RESPONSE(fl_method_success_response_new(NULL));
    }
    catch (const std::exception &e)
    {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("Error", e.what(), NULL));
    }
}

FlMethodResponse *is_muted(AudioController *controller)
{
    try
    {
        bool muted = controller->is_muted();
        g_autoptr(FlValue) result = fl_value_new_bool(muted);
        return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
    catch (const std::exception &e)
    {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("Error", e.what(), NULL));
    }
}

FlMethodResponse *set_mute(AudioController *controller, bool mute)
{
    try
    {
        controller->set_mute(mute);
        return FL_METHOD_RESPONSE(fl_method_success_response_new(NULL));
    }
    catch (const std::exception &e)
    {
        return FL_METHOD_RESPONSE(fl_method_error_response_new("Error", e.what(), NULL));
    }
}