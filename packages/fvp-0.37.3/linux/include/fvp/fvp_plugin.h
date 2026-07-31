/*
 * Copyright (c) 2023 WangBin <wbsecg1 at gmail.com>
 */
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef FLUTTER_PLUGIN_FVP_PLUGIN_H_
#define FLUTTER_PLUGIN_FVP_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _FvpPlugin FvpPlugin;
typedef struct {
  GObjectClass parent_class;
} FvpPluginClass;

FLUTTER_PLUGIN_EXPORT GType fvp_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void fvp_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_FVP_PLUGIN_H_
