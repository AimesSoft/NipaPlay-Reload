#include "include/volume_controller/volume_controller_plugin.h"
#include "include/volume_controller/constants.h"
#include "include/volume_controller/volume_controller.h"
#include "include/volume_controller/audio_controller.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <alsa/asoundlib.h>

#include <cstring>

#define VOLUME_CONTROLLER_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), volume_controller_plugin_get_type(), \
                              VolumeControllerPlugin))

struct _VolumeControllerPlugin
{
  GObject parent_instance;

  AudioController *audioController;

  FlEventChannel *event_channel = NULL;
};

G_DEFINE_TYPE(VolumeControllerPlugin, volume_controller_plugin, g_object_get_type())

static void on_volume_changed_callback(double new_volume, gpointer user_data)
{
  VolumeControllerPlugin *plugin = VOLUME_CONTROLLER_PLUGIN(user_data);

  if (plugin && plugin->event_channel)
  {
    fl_event_channel_send(plugin->event_channel, fl_value_new_float(new_volume), NULL, NULL);
  }
}

// Called when a method call is received from Flutter.
static void volume_controller_plugin_handle_method_call(
    VolumeControllerPlugin *self,
    FlMethodCall *method_call)
{
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar *method = fl_method_call_get_name(method_call);
  FlValue *args = fl_method_call_get_args(method_call);

  if (strcmp(method, MethodName::getVolume) == 0)
  {
    response = get_volume(self->audioController);
  }
  else if (strcmp(method, MethodName::setVolume) == 0)
  {
    FlValue *arg = fl_value_lookup_string(args, MethodArgument::volume);
    double volume = fl_value_get_float(arg);

    response = set_volume(self->audioController, volume);
  }
  else if (strcmp(method, MethodName::isMuted) == 0)
  {
    response = is_muted(self->audioController);
  }
  else if (strcmp(method, MethodName::setMute) == 0)
  {
    FlValue *arg = fl_value_lookup_string(args, MethodArgument::isMute);
    bool mute = fl_value_get_bool(arg);
    response = set_mute(self->audioController, mute);
  }
  else
  {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static FlMethodErrorResponse *event_listen_cb(FlEventChannel *channel, FlValue *args, gpointer user_data)
{
  VolumeControllerPlugin *self = VOLUME_CONTROLLER_PLUGIN(user_data);

  if (!self || !self->audioController)
  {
    return FL_METHOD_ERROR_RESPONSE(fl_method_error_response_new("PluginError", "AudioController not initialized.", nullptr));
  }

  if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
  {
    FlValue *fetch_arg = fl_value_lookup_string(args, EventArgument::fetchInitialVolume);
    if (fetch_arg && fl_value_get_type(fetch_arg) == FL_VALUE_TYPE_BOOL)
    {
      self->audioController->fetch_initial_volume = fl_value_get_bool(fetch_arg);
    }
  }

  if (!self->audioController->start_listening_for_volume_changes(on_volume_changed_callback, self))
  {
    return FL_METHOD_ERROR_RESPONSE(fl_method_error_response_new("AudioError", "Failed to start volume listener.", nullptr));
  }

  return NULL;
}

static FlMethodErrorResponse *event_cancel_cb(FlEventChannel *channel, FlValue *args, gpointer user_data)
{
  VolumeControllerPlugin *self = VOLUME_CONTROLLER_PLUGIN(user_data);

  if (!self || !self->audioController)
  {
    return NULL;
  }

  self->audioController->stop_listening_for_volume_changes();

  return NULL;
}

static void volume_controller_plugin_init(VolumeControllerPlugin *self)
{
  try
  {
    self->audioController = new AudioController();
  }
  catch (const std::exception &e)
  {
    g_critical("Failed to create AudioController: %s", e.what());
    self->audioController = nullptr;
  }
}

static void volume_controller_plugin_dispose(GObject *object)
{
  VolumeControllerPlugin *self = VOLUME_CONTROLLER_PLUGIN(object);

  g_object_unref(self->event_channel);

  if (self->audioController)
  {
    delete self->audioController;
    self->audioController = nullptr;
  }

  G_OBJECT_CLASS(volume_controller_plugin_parent_class)->dispose(object);
}

static void volume_controller_plugin_class_init(VolumeControllerPluginClass *klass)
{
  G_OBJECT_CLASS(klass)->dispose = volume_controller_plugin_dispose;
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data)
{
  VolumeControllerPlugin *plugin = VOLUME_CONTROLLER_PLUGIN(user_data);
  volume_controller_plugin_handle_method_call(plugin, method_call);
}

void volume_controller_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
  VolumeControllerPlugin *plugin = VOLUME_CONTROLLER_PLUGIN(
      g_object_new(volume_controller_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            ChannelName::methodChannel,
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  // Register event channel with correct handler signatures
  plugin->event_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      ChannelName::eventChannel,
      FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->event_channel,
                                       event_listen_cb,
                                       event_cancel_cb,
                                       g_object_ref(plugin),
                                       g_object_unref);

  g_object_unref(plugin);
}
