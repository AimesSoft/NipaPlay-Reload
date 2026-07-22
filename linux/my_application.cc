#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <algorithm>
#include <cmath>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* main_window;
  FlMethodChannel* desktop_window_channel;
  gboolean picture_in_picture_has_restore_bounds;
  gint picture_in_picture_restore_x;
  gint picture_in_picture_restore_y;
  gint picture_in_picture_restore_width;
  gint picture_in_picture_restore_height;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static double fl_value_as_double(FlValue* value, double fallback = 0.0) {
  if (value == nullptr) {
    return fallback;
  }
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_FLOAT:
      return fl_value_get_float(value);
    case FL_VALUE_TYPE_INT:
      return static_cast<double>(fl_value_get_int(value));
    default:
      return fallback;
  }
}

static gboolean fl_value_as_bool(FlValue* value, gboolean fallback = FALSE) {
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

static const gchar* fl_value_as_string(FlValue* value,
                                       const gchar* fallback = "") {
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return fallback;
  }
  return fl_value_get_string(value);
}

static GtkWindow* find_secondary_flutter_window(MyApplication* self) {
  GList* windows = gtk_window_list_toplevels();
  GtkWindow* result = nullptr;
  for (GList* item = windows; item != nullptr; item = item->next) {
    if (!GTK_IS_WINDOW(item->data)) {
      continue;
    }
    GtkWindow* candidate = GTK_WINDOW(item->data);
    if (candidate == self->main_window) {
      continue;
    }
    // Same-engine regular Flutter windows are the only other normal
    // application toplevels created by NipaPlay.
    result = candidate;
    break;
  }
  g_list_free(windows);
  return result;
}

static void apply_linux_window_aspect_ratio(GtkWindow* window, double ratio) {
  if (!std::isfinite(ratio) || ratio <= 0.0) {
    return;
  }
  GdkGeometry geometry = {};
  geometry.min_aspect = ratio;
  geometry.max_aspect = ratio;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_ASPECT);
}

static void apply_linux_always_on_top(GtkWindow* window, gboolean enabled) {
  gtk_window_set_keep_above(window, enabled);
  if (enabled) {
    // GTK maps this to the window manager's all-workspaces behavior.
    gtk_window_stick(window);
  } else {
    gtk_window_unstick(window);
  }
}

static void apply_linux_picture_in_picture(MyApplication* self,
                                           GtkWindow* window,
                                           FlValue* args) {
  const gboolean enabled =
      fl_value_as_bool(fl_value_lookup_string(args, "enabled"));
  if (!enabled) {
    if (!self->picture_in_picture_has_restore_bounds) {
      return;
    }
    self->picture_in_picture_has_restore_bounds = FALSE;
    gtk_window_resize(window, self->picture_in_picture_restore_width,
                      self->picture_in_picture_restore_height);
    gtk_window_move(window, self->picture_in_picture_restore_x,
                    self->picture_in_picture_restore_y);
    g_message("[DesktopMultiWindow][PiP] restored %dx%d at %d,%d",
              self->picture_in_picture_restore_width,
              self->picture_in_picture_restore_height,
              self->picture_in_picture_restore_x,
              self->picture_in_picture_restore_y);
    return;
  }

  if (!self->picture_in_picture_has_restore_bounds) {
    gtk_window_get_position(window, &self->picture_in_picture_restore_x,
                            &self->picture_in_picture_restore_y);
    gtk_window_get_size(window, &self->picture_in_picture_restore_width,
                        &self->picture_in_picture_restore_height);
    self->picture_in_picture_has_restore_bounds = TRUE;
  }

  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkMonitor* monitor = gdk_window != nullptr
                            ? gdk_display_get_monitor_at_window(display,
                                                                gdk_window)
                            : gdk_display_get_primary_monitor(display);
  if (monitor == nullptr) {
    return;
  }
  GdkRectangle work = {};
  gdk_monitor_get_workarea(monitor, &work);
  const double ratio = std::clamp(
      fl_value_as_double(fl_value_lookup_string(args, "aspectRatio"),
                         16.0 / 9.0),
      0.5, 3.0);
  const gint margin = static_cast<gint>(std::lround(std::max(
      0.0, fl_value_as_double(fl_value_lookup_string(args, "margin"), 16.0))));
  const gint available_width = std::max(1, work.width - margin * 2);
  double height = std::min(
      work.height / 3.0,
      static_cast<double>(std::max(1, work.height - margin * 2)));
  double width = height * ratio;
  if (width > available_width) {
    width = available_width;
    height = width / ratio;
  }
  const gint target_width = static_cast<gint>(std::lround(width));
  const gint target_height = static_cast<gint>(std::lround(height));
  const gchar* placement = fl_value_as_string(
      fl_value_lookup_string(args, "placement"), "topRight");
  const gboolean place_left = g_strcmp0(placement, "topLeft") == 0 ||
                               g_strcmp0(placement, "bottomLeft") == 0;
  const gboolean place_bottom = g_strcmp0(placement, "bottomLeft") == 0 ||
                                 g_strcmp0(placement, "bottomRight") == 0;
  const gint x = place_left ? work.x + margin
                            : work.x + work.width - target_width - margin;
  const gint y = place_bottom ? work.y + work.height - target_height - margin
                              : work.y + margin;
  gtk_window_resize(window, target_width, target_height);
  // Compositors using Wayland may choose to ignore absolute window placement.
  gtk_window_move(window, x, y);
  g_message(
      "[DesktopMultiWindow][PiP] dock placement=%s work=%d,%d %dx%d size=%dx%d",
      placement, work.x, work.y, work.width, work.height, target_width,
      target_height);
}

static void desktop_window_method_call_cb(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  FlValue* args = fl_method_call_get_args(method_call);
  GtkWindow* window = find_secondary_flutter_window(self);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP ||
      window == nullptr) {
    fl_method_call_respond_error(
        method_call, "WINDOW_NOT_FOUND",
        "No same-engine Flutter secondary window is available", nullptr,
        nullptr);
    return;
  }

  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, "configureWindow") == 0) {
    self->picture_in_picture_has_restore_bounds = FALSE;
    if (fl_value_as_bool(fl_value_lookup_string(args, "frameless"))) {
      gtk_window_set_decorated(window, FALSE);
    }
    apply_linux_window_aspect_ratio(
        window,
        fl_value_as_double(fl_value_lookup_string(args, "aspectRatio")));
    const double width =
        fl_value_as_double(fl_value_lookup_string(args, "width"));
    const double height =
        fl_value_as_double(fl_value_lookup_string(args, "height"));
    if (width > 0.0 && height > 0.0) {
      gtk_window_resize(window, static_cast<gint>(std::lround(width)),
                        static_cast<gint>(std::lround(height)));
    }
    const gboolean always_on_top =
        fl_value_as_bool(fl_value_lookup_string(args, "alwaysOnTop"));
    apply_linux_always_on_top(window, always_on_top);
    g_autoptr(FlValue) response = fl_value_new_bool(always_on_top);
    fl_method_call_respond_success(method_call, response, nullptr);
    return;
  }
  if (strcmp(method, "setAspectRatio") == 0) {
    apply_linux_window_aspect_ratio(
        window,
        fl_value_as_double(fl_value_lookup_string(args, "aspectRatio")));
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (strcmp(method, "setAlwaysOnTop") == 0) {
    const gboolean always_on_top =
        fl_value_as_bool(fl_value_lookup_string(args, "alwaysOnTop"));
    apply_linux_always_on_top(window, always_on_top);
    g_autoptr(FlValue) response = fl_value_new_bool(always_on_top);
    fl_method_call_respond_success(method_call, response, nullptr);
    return;
  }
  if (strcmp(method, "setPictureInPictureMode") == 0) {
    apply_linux_picture_in_picture(self, window, args);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (strcmp(method, "startDragging") == 0) {
    GdkEvent* event = gtk_get_current_event();
    if (event != nullptr) {
      gdouble root_x = 0.0;
      gdouble root_y = 0.0;
      gdk_event_get_root_coords(event, &root_x, &root_y);
      guint button = 1;
      if (event->type == GDK_BUTTON_PRESS ||
          event->type == GDK_2BUTTON_PRESS ||
          event->type == GDK_3BUTTON_PRESS) {
        button = event->button.button;
      }
      gtk_window_begin_move_drag(
          window, static_cast<gint>(button), static_cast<gint>(root_x),
          static_cast<gint>(root_y), gdk_event_get_time(event));
      gdk_event_free(event);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (strcmp(method, "updateDragging") == 0 ||
      strcmp(method, "endDragging") == 0) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  fl_method_call_respond_not_implemented(method_call, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->main_window = window;

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0 &&
        g_strcmp0(wm_name, "KWin") != 0) {
        use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "nipaplay");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "nipaplay");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  g_autoptr(FlStandardMethodCodec) desktop_window_codec =
      fl_standard_method_codec_new();
  self->desktop_window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "nipaplay/desktop_multi_window_host",
      FL_METHOD_CODEC(desktop_window_codec));
  fl_method_channel_set_method_call_handler(
      self->desktop_window_channel, desktop_window_method_call_cb, self,
      nullptr);
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->desktop_window_channel);
  self->main_window = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
