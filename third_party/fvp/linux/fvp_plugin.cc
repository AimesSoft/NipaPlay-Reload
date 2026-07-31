/*
 * Copyright (c) 2023-2025 WangBin <wbsecg1 at gmail.com>
 */
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include "include/fvp/fvp_plugin.h"

#include <algorithm>
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <gdk/gdkx.h>
#include <gdk/gdkwayland.h>

#include <cstring>
#include <cstdlib>
#include <iostream>
#include <list>
#include <memory>
#include <string>
#include <thread>
#include <unordered_map>
#include <epoxy/gl.h>

#include "mdk/RenderAPI.h"
#include "mdk/Player.h"

using namespace std;

class TexturePlayer;

G_DECLARE_FINAL_TYPE(PlayerTexture, player_texture, FL, PLAYER_TEXTURE, FlTextureGL)

#define PLAYER_TEXTURE(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), player_texture_get_type(), PlayerTexture))


class CleanupTask {
public:
  CleanupTask(GdkGLContext* ctx, function<void()>&& callback) : ctx_(ctx), cb_(std::move(callback)) {}
  ~CleanupTask() {
    auto ctx = gdk_gl_context_get_current();
    if (ctx_ != ctx) {
      clog << "gdk gl context change: " << ctx_ << " => " << ctx << endl;
      gdk_gl_context_make_current(ctx_);
    }
    cb_();
    if (ctx_ != ctx) {
      gdk_gl_context_make_current(ctx);
    }
  }

  bool disposed = false;
private:
  GdkGLContext* ctx_;
  function<void()> cb_;
};
static thread_local list<shared_ptr<CleanupTask>> gCleanupTasks;

struct _PlayerTexture {
  FlTextureGL parent_instance;

  GdkGLContext* ctx;
  GLuint texture_id;
  GLuint fbo;

  TexturePlayer* player;
  CleanupTask* cleanup;
};

G_DEFINE_TYPE(PlayerTexture, player_texture, fl_texture_gl_get_type())

class TexturePlayer final : public mdk::Player
{
public:
  TexturePlayer(int64_t handle, PlayerTexture* tex, int w, int h, FlTextureRegistrar* texRegistrar)
    : mdk::Player(reinterpret_cast<mdkPlayerAPI*>(handle))
    , width(w)
    , height(h)
    , texReg(texRegistrar)
    , flTex(tex)
  {
    flTex->player = this;

    if (!fl_texture_registrar_register_texture(texReg, FL_TEXTURE(flTex))) {
      clog << "fl_texture_registrar_register_texture error" << endl;
      return;
    }
    textureId = fl_texture_get_id(FL_TEXTURE(flTex)); // MUST be after fl_texture_registrar_register_texture(), id is set there

    scale(1, -1); // y is flipped
    setVideoSurfaceSize(width, height);
    setRenderCallback([this](void*) {
      //renderVideo(); // need a gl context
      fl_texture_registrar_mark_texture_frame_available(texReg, FL_TEXTURE(flTex));
      });
  }

  ~TexturePlayer() override {
    if (!fl_texture_registrar_unregister_texture(texReg, FL_TEXTURE(flTex))) {
      clog << "fl_texture_registrar_unregister_texture error" << endl;
    }
    setRenderCallback(nullptr);
    setVideoSurfaceSize(-1, -1);

    g_object_unref(flTex);
  }

  int64_t textureId;
  int width;
  int height;
private:
  FlTextureRegistrar* texReg;
  PlayerTexture* flTex; // hold ref
};

// NipaPlay patch for AimesSoft/NipaPlay-Reload#639 (see also wang-bin/fvp#258):
// renderVideo() runs inside flutter's raster GL context. Skia caches GL state and
// mdk inherits whatever Skia left behind, so both renderers corrupt each other's
// assumptions (symptom: frames alternating between normal and inverted colors).
// Snapshot the shared state, reset it to defaults for mdk, and restore it after.
class GLStateGuard {
public:
  GLStateGuard() {
    hasVao_ = epoxy_gl_version() >= 30 || epoxy_has_gl_extension("GL_OES_vertex_array_object")
        || epoxy_has_gl_extension("GL_ARB_vertex_array_object");
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo_);
    glGetIntegerv(GL_CURRENT_PROGRAM, &program_);
    if (hasVao_)
      glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao_);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &arrayBuffer_);
    glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexture_);
    for (int i = 0; i < kTextureUnits; ++i) { // mdk binds up to 4 planes for yuv
      glActiveTexture(GL_TEXTURE0 + i);
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture2d_[i]);
    }
    glGetIntegerv(GL_VIEWPORT, viewport_);
    glGetIntegerv(GL_SCISSOR_BOX, scissorBox_);
    glGetBooleanv(GL_COLOR_WRITEMASK, colorMask_);
    glGetIntegerv(GL_BLEND_SRC_RGB, &blendSrcRgb_);
    glGetIntegerv(GL_BLEND_DST_RGB, &blendDstRgb_);
    glGetIntegerv(GL_BLEND_SRC_ALPHA, &blendSrcAlpha_);
    glGetIntegerv(GL_BLEND_DST_ALPHA, &blendDstAlpha_);
    glGetIntegerv(GL_BLEND_EQUATION_RGB, &blendEqRgb_);
    glGetIntegerv(GL_BLEND_EQUATION_ALPHA, &blendEqAlpha_);
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpackAlignment_);
    blend_ = glIsEnabled(GL_BLEND);
    scissor_ = glIsEnabled(GL_SCISSOR_TEST);
    depth_ = glIsEnabled(GL_DEPTH_TEST);
    stencil_ = glIsEnabled(GL_STENCIL_TEST);
    cull_ = glIsEnabled(GL_CULL_FACE);
    // defaults mdk's video pass must not inherit from skia
    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST);
    glDisable(GL_CULL_FACE);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  }

  ~GLStateGuard() {
    glUseProgram(program_);
    if (hasVao_)
      glBindVertexArray(vao_);
    glBindBuffer(GL_ARRAY_BUFFER, arrayBuffer_);
    for (int i = 0; i < kTextureUnits; ++i) {
      glActiveTexture(GL_TEXTURE0 + i);
      glBindTexture(GL_TEXTURE_2D, texture2d_[i]);
    }
    glActiveTexture(activeTexture_);
    setEnabled(GL_BLEND, blend_);
    setEnabled(GL_SCISSOR_TEST, scissor_);
    setEnabled(GL_DEPTH_TEST, depth_);
    setEnabled(GL_STENCIL_TEST, stencil_);
    setEnabled(GL_CULL_FACE, cull_);
    glBlendFuncSeparate(blendSrcRgb_, blendDstRgb_, blendSrcAlpha_, blendDstAlpha_);
    glBlendEquationSeparate(blendEqRgb_, blendEqAlpha_);
    glColorMask(colorMask_[0], colorMask_[1], colorMask_[2], colorMask_[3]);
    glPixelStorei(GL_UNPACK_ALIGNMENT, unpackAlignment_);
    glViewport(viewport_[0], viewport_[1], viewport_[2], viewport_[3]);
    glScissor(scissorBox_[0], scissorBox_[1], scissorBox_[2], scissorBox_[3]);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
  }

private:
  static void setEnabled(GLenum cap, GLboolean on) {
    if (on)
      glEnable(cap);
    else
      glDisable(cap);
  }

  static constexpr int kTextureUnits = 4;
  bool hasVao_ = false;
  GLint fbo_ = 0, program_ = 0, vao_ = 0, arrayBuffer_ = 0, activeTexture_ = GL_TEXTURE0;
  GLint texture2d_[kTextureUnits] = {};
  GLint viewport_[4] = {}, scissorBox_[4] = {};
  GLboolean colorMask_[4] = {};
  GLint blendSrcRgb_ = 0, blendDstRgb_ = 0, blendSrcAlpha_ = 0, blendDstAlpha_ = 0;
  GLint blendEqRgb_ = 0, blendEqAlpha_ = 0;
  GLint unpackAlignment_ = 4;
  GLboolean blend_ = GL_FALSE, scissor_ = GL_FALSE, depth_ = GL_FALSE, stencil_ = GL_FALSE, cull_ = GL_FALSE;
};

// called in a current gl context
static gboolean player_texture_populate(FlTextureGL *texture, uint32_t *target, uint32_t *name,
                        uint32_t *width, uint32_t *height, GError **error) {
  // cleanup ASAP before drawing the next frame
  if (auto count = std::erase_if(gCleanupTasks, [](auto task) { return task->disposed; })) {
    clog << std::to_string(count) + " cleanup tasks executed in raster thread " << this_thread::get_id() << endl;
  }
  PlayerTexture *self = PLAYER_TEXTURE(texture);

  GLStateGuard stateGuard; // isolate mdk's GL usage from skia's cached state (#639)

  if (self->fbo == 0) {
    self->ctx = gdk_gl_context_get_current(); // fbo can not be shared
    glGenFramebuffers(1, &self->fbo);
    assert(self->texture_id == 0);
    GLint prevFbo = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prevFbo);
    glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);
    glGenTextures(1, &self->texture_id);
    clog << "created fbo: " + std::to_string(self->fbo) + " tex: " + std::to_string(self->texture_id) + " in raster thread " << this_thread::get_id() << endl;
    auto task = make_shared<CleanupTask>(self->ctx, [tex = self->texture_id, fbo = self->fbo]() {
      clog << "delete fbo: " + std::to_string(fbo) + " tex: " + std::to_string(tex) << endl;
      glDeleteTextures(1, &tex);
      glDeleteFramebuffers(1, &fbo);
    });
    self->cleanup = task.get();
    gCleanupTasks.push_back(std::move(task));

    glBindTexture(GL_TEXTURE_2D, self->texture_id);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, self->player->width, self->player->height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + 0, GL_TEXTURE_2D, self->texture_id, 0);
    const GLenum err = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    glBindFramebuffer(GL_FRAMEBUFFER, prevFbo);
    if (err != GL_FRAMEBUFFER_COMPLETE) {
        //glDeleteFramebuffers(1, &fbo);
        clog << "glFramebufferTexture2D error" << endl;
        return FALSE;
    }
    mdk::GLRenderAPI ra{};
    ra.fbo = self->fbo;
    self->player->setRenderAPI(&ra);
  }

  self->player->renderVideo();

  *target = GL_TEXTURE_2D;
  *name = self->texture_id;
  *width = self->player->width;
  *height = self->player->height;

  return TRUE;
}

static void player_texture_dispose(GObject* obj) {
  G_OBJECT_CLASS(player_texture_parent_class)->dispose(obj);
  auto self = PLAYER_TEXTURE(obj);
  if (!self->texture_id && !self->fbo) {
    clog << "texture and fbo are not created yet" << endl;
    return;
  }
  if (self->cleanup) {
    self->cleanup->disposed = true;
    clog << "try to cleanup gl resources in dispose thread " << this_thread::get_id() << endl;
    if (auto count = std::erase_if(gCleanupTasks, [](auto task) { return task->disposed; })) {
      clog << std::to_string(count) + " cleanup tasks executed in dispose thread " << this_thread::get_id() << endl;
    }
  }
}

static void player_texture_class_init(PlayerTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = player_texture_populate;
  auto gklass = G_OBJECT_CLASS(klass);
  gklass->dispose = player_texture_dispose;
}

static void player_texture_init(PlayerTexture* self) {
  self->texture_id = 0;
  self->fbo = 0;
  self->player = nullptr;
  self->ctx = nullptr;
  self->cleanup = nullptr;
}


#define FVP_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), fvp_plugin_get_type(), \
                              FvpPlugin))

using PlayerMap = unordered_map<int64_t, shared_ptr<TexturePlayer>>;
struct _FvpPlugin {
  GObject parent_instance;

  FlTextureRegistrar* tex_registrar;
  PlayerMap players;
};

G_DEFINE_TYPE(FvpPlugin, fvp_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void fvp_plugin_handle_method_call(
    FvpPlugin* self,
    FlMethodCall* method_call) {
  // static PlayerMap players; // here is also fine, will be destroyed earlier than libmdk global objects(Context::current() map)
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "CreateRT") == 0) {
    const auto args = fl_method_call_get_args(method_call);
    const auto handle = fl_value_get_int(fl_value_lookup_string(args, "player"));
    const auto width = (int)fl_value_get_int(fl_value_lookup_string(args, "width"));
    const auto height = (int)fl_value_get_int(fl_value_lookup_string(args, "height"));
    auto tex = PLAYER_TEXTURE(g_object_new(player_texture_get_type(), nullptr));
    auto player = make_shared<TexturePlayer>(handle, tex, width, height, self->tex_registrar);
    self->players[player->textureId] = player;
    g_autoptr(FlValue) result = fl_value_new_int(player->textureId);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "ReleaseRT") == 0) {
    const auto args = fl_method_call_get_args(method_call);
    const auto texId = fl_value_get_int(fl_value_lookup_string(args, "texture"));
    if (auto it = self->players.find(texId); it != self->players.cend()) {
        self->players.erase(it);
    }
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "MixWithOthers") == 0) {
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void fvp_plugin_dispose(GObject* object) { // seems never be invoked
  auto self = FVP_PLUGIN(object);
  self->players.~PlayerMap();
  G_OBJECT_CLASS(fvp_plugin_parent_class)->dispose(object);
}

static void fvp_plugin_class_init(FvpPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = fvp_plugin_dispose;
}

static void fvp_plugin_init(FvpPlugin* self) {
  self->tex_registrar = nullptr;
  new(&self->players) PlayerMap;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  FvpPlugin* plugin = FVP_PLUGIN(user_data);
  fvp_plugin_handle_method_call(plugin, method_call);
}

void fvp_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FvpPlugin* plugin = FVP_PLUGIN(
      g_object_new(fvp_plugin_get_type(), nullptr));
  plugin->tex_registrar = fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "fvp",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);

  auto gdisp = gdk_display_get_default();
  if (GDK_IS_X11_DISPLAY(gdisp)) {
    mdk::SetGlobalOption("X11Display", GDK_DISPLAY_XDISPLAY(gdisp));
  } else if (GDK_IS_WAYLAND_DISPLAY(gdisp)) {
    mdk::SetGlobalOption("wl_display*", gdk_wayland_display_get_wl_display(gdisp));
  }
  mdk::SetGlobalOption("MDK_KEY", "980B9623276F746C5FBB5EC5120D4A99A0B58B635592EAEE41F6817FDF3B28B96AC4A49866257726C19B246863B5ADAF5D17464E86D72A90634E8AE8418F810967F469DCD8908B93A044A13AEDF2B566E0B5810523E2B59E2D83E616B1B807B66253E1607A79BC86AEDE1AEF46F79AA60F36BE44DDEE47B84E165AF2788F8109");
}

__attribute__((constructor, used))
static void init_xlib() {
  XInitThreads();
}
