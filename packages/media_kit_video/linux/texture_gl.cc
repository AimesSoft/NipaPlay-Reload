// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "include/media_kit_video/texture_gl.h"

#include <epoxy/gl.h>
#include <epoxy/egl.h>

struct _TextureGL {
  FlTextureGL parent_instance;
  guint32 name;              // Flutter-owned texture name
  guint32 fbo;               // FBO attached to |name|
  guint32 current_width;
  guint32 current_height;
  VideoOutput* video_output;
};

G_DEFINE_TYPE(TextureGL, texture_gl, fl_texture_gl_get_type())

static void texture_gl_init(TextureGL* self) {
  self->name = 0;
  self->fbo = 0;
  self->current_width = 1;
  self->current_height = 1;
  self->video_output = NULL;
}

static void texture_gl_dispose(GObject* object) {
  TextureGL* self = TEXTURE_GL(object);

  if (self->name != 0) {
    glDeleteTextures(1, &self->name);
    self->name = 0;
  }

  if (self->fbo != 0) {
    glDeleteFramebuffers(1, &self->fbo);
    self->fbo = 0;
  }

  self->current_width = 1;
  self->current_height = 1;
  self->video_output = NULL;
  G_OBJECT_CLASS(texture_gl_parent_class)->dispose(object);
}

static void texture_gl_class_init(TextureGLClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = texture_gl_populate_texture;
  G_OBJECT_CLASS(klass)->dispose = texture_gl_dispose;
}

TextureGL* texture_gl_new(VideoOutput* video_output) {
  TextureGL* self = TEXTURE_GL(g_object_new(texture_gl_get_type(), NULL));
  self->video_output = video_output;
  return self;
}

static void texture_gl_create_or_resize(TextureGL* self,
                                        guint32 required_width,
                                        guint32 required_height) {
  GLint previous_fbo = 0;
  GLint previous_texture = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previous_fbo);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &previous_texture);

  if (self->name != 0) {
    glDeleteTextures(1, &self->name);
    self->name = 0;
  }
  if (self->fbo != 0) {
    glDeleteFramebuffers(1, &self->fbo);
    self->fbo = 0;
  }

  glGenTextures(1, &self->name);
  glBindTexture(GL_TEXTURE_2D, self->name);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, required_width, required_height,
               0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);

  glGenFramebuffers(1, &self->fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                         GL_TEXTURE_2D, self->name, 0);
  glBindFramebuffer(GL_FRAMEBUFFER, previous_fbo);
  glBindTexture(GL_TEXTURE_2D, previous_texture);

  self->current_width = required_width;
  self->current_height = required_height;
}

gboolean texture_gl_populate_texture(FlTextureGL* texture,
                                     guint32* target,
                                     guint32* name,
                                     guint32* width,
                                     guint32* height,
                                     GError** error) {
  TextureGL* self = TEXTURE_GL(texture);
  VideoOutput* video_output = self->video_output;
  
  gint32 required_width = (guint32)video_output_get_width(video_output);
  gint32 required_height = (guint32)video_output_get_height(video_output);
  
  if (required_width > 0 && required_height > 0) {
    gboolean first_frame = self->name == 0 || self->fbo == 0;
    gboolean resize = self->current_width != required_width ||
                      self->current_height != required_height;

    if (first_frame || resize) {
      texture_gl_create_or_resize(self, required_width, required_height);

      // Notify Flutter about dimension change.
      video_output_notify_texture_update(video_output);
    }

    mpv_render_context* render_context = video_output_get_render_context(video_output);

    GLint previous_fbo = 0;
    GLint previous_viewport[4] = {0, 0, 0, 0};
    GLint previous_scissor_box[4] = {0, 0, 0, 0};
    GLfloat previous_clear_color[4] = {0.f, 0.f, 0.f, 0.f};
    GLboolean scissor_enabled = glIsEnabled(GL_SCISSOR_TEST);

    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previous_fbo);
    glGetIntegerv(GL_VIEWPORT, previous_viewport);
    glGetIntegerv(GL_SCISSOR_BOX, previous_scissor_box);
    glGetFloatv(GL_COLOR_CLEAR_VALUE, previous_clear_color);

    glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);

    mpv_opengl_fbo fbo{(gint32)self->fbo, required_width, required_height, 0};
    int flip_y = 0;
    int block_for_target_time = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block_for_target_time},
        {MPV_RENDER_PARAM_INVALID, NULL},
    };
    mpv_render_context_render(render_context, params);

    glBindFramebuffer(GL_FRAMEBUFFER, previous_fbo);
    glViewport(previous_viewport[0], previous_viewport[1],
               previous_viewport[2], previous_viewport[3]);
    if (scissor_enabled) {
      glEnable(GL_SCISSOR_TEST);
    } else {
      glDisable(GL_SCISSOR_TEST);
    }
    glScissor(previous_scissor_box[0], previous_scissor_box[1],
              previous_scissor_box[2], previous_scissor_box[3]);
    glClearColor(previous_clear_color[0], previous_clear_color[1],
                 previous_clear_color[2], previous_clear_color[3]);
  }

  *target = GL_TEXTURE_2D;
  *name = self->name;
  *width = self->current_width;
  *height = self->current_height;

  if (self->name == 0) {
    // First frame not yet available.
    glGenTextures(1, &self->name);
    glBindTexture(GL_TEXTURE_2D, self->name);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glBindTexture(GL_TEXTURE_2D, 0);
    *name = self->name;
    *width = 1;
    *height = 1;
  }
  
  return TRUE;
}
