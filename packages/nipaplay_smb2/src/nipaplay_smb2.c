#include "nipaplay_smb2.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include <smb2/libsmb2-dcerpc-srvsvc.h>
#include <smb2/libsmb2.h>
#include <smb2/libsmb2-raw.h>

typedef struct np_smb2_reader {
  struct smb2_context *ctx;
  struct smb2fh *fh;
  uint64_t size;
} np_smb2_reader_t;

static void np_set_err(char *err_buf, int err_len, const char *fmt, ...) {
  if (err_buf == NULL || err_len <= 0) {
    return;
  }
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(err_buf, (size_t)err_len, fmt, ap);
  va_end(ap);
}

static bool np_is_empty(const char *s) { return s == NULL || s[0] == '\0'; }

static char *np_strdup_or_empty(const char *s) {
  if (s == NULL) {
    char *out = (char *)malloc(1);
    if (out) {
      out[0] = '\0';
    }
    return out;
  }
  const size_t n = strlen(s);
  char *out = (char *)malloc(n + 1);
  if (out == NULL) {
    return NULL;
  }
  memcpy(out, s, n + 1);
  return out;
}

static char *np_normalize_path(const char *raw) {
  if (raw == NULL || raw[0] == '\0') {
    return np_strdup_or_empty("/");
  }

  const size_t n = strlen(raw);
  char *tmp = (char *)malloc(n + 2);
  if (tmp == NULL) {
    return NULL;
  }

  size_t j = 0;
  if (raw[0] != '/' && raw[0] != '\\') {
    tmp[j++] = '/';
  }
  for (size_t i = 0; i < n; i++) {
    char c = raw[i];
    if (c == '\\') {
      c = '/';
    }
    if (c == '/' && j > 0 && tmp[j - 1] == '/') {
      continue;
    }
    tmp[j++] = c;
  }
  if (j == 0) {
    tmp[j++] = '/';
  }
  tmp[j] = '\0';
  return tmp;
}

static int np_build_server(const char *host, int port, char *out,
                           size_t out_len) {
  if (out == NULL || out_len == 0) {
    return -EINVAL;
  }
  if (np_is_empty(host)) {
    return -EINVAL;
  }
  if (port <= 0 || port > 65535) {
    port = 445;
  }
  if (port == 445) {
    return snprintf(out, out_len, "%s", host) < 0 ? -EINVAL : 0;
  }
  return snprintf(out, out_len, "%s:%d", host, port) < 0 ? -EINVAL : 0;
}

static int np_parse_share_and_path(const char *normalized_path, char *share_out,
                                   size_t share_len, char *path_out,
                                   size_t path_len) {
  if (normalized_path == NULL || normalized_path[0] == '\0') {
    return -EINVAL;
  }
  if (strcmp(normalized_path, "/") == 0) {
    return -EINVAL;
  }
  const char *p = normalized_path;
  if (*p == '/') {
    p++;
  }
  const char *slash = strchr(p, '/');
  size_t share_n = slash ? (size_t)(slash - p) : strlen(p);
  if (share_n == 0) {
    return -EINVAL;
  }
  if (share_n + 1 > share_len) {
    return -ENAMETOOLONG;
  }
  memcpy(share_out, p, share_n);
  share_out[share_n] = '\0';

  const char *rest = slash ? slash : "";
  if (np_is_empty(rest)) {
    snprintf(path_out, path_len, "/");
    return 0;
  }
  if (strlen(rest) + 1 > path_len) {
    return -ENAMETOOLONG;
  }
  // rest already starts with '/'
  memcpy(path_out, rest, strlen(rest) + 1);
  return 0;
}

static void np_json_append(char **buf, size_t *len, size_t *cap,
                           const char *s) {
  if (buf == NULL || len == NULL || cap == NULL || s == NULL) {
    return;
  }
  const size_t add = strlen(s);
  if (*buf == NULL) {
    *cap = add + 64;
    *buf = (char *)malloc(*cap);
    if (*buf == NULL) {
      *cap = 0;
      *len = 0;
      return;
    }
    (*buf)[0] = '\0';
    *len = 0;
  }
  if (*len + add + 1 > *cap) {
    size_t new_cap = (*cap) * 2;
    if (new_cap < *len + add + 1) {
      new_cap = *len + add + 1;
    }
    char *next = (char *)realloc(*buf, new_cap);
    if (next == NULL) {
      return;
    }
    *buf = next;
    *cap = new_cap;
  }
  memcpy(*buf + *len, s, add);
  *len += add;
  (*buf)[*len] = '\0';
}

static char *np_json_escape(const char *s) {
  if (s == NULL) {
    return np_strdup_or_empty("");
  }
  const size_t n = strlen(s);
  // Worst case every char becomes two chars.
  char *out = (char *)malloc(n * 2 + 1);
  if (out == NULL) {
    return NULL;
  }
  size_t j = 0;
  for (size_t i = 0; i < n; i++) {
    const unsigned char c = (unsigned char)s[i];
    switch (c) {
    case '\\':
      out[j++] = '\\';
      out[j++] = '\\';
      break;
    case '"':
      out[j++] = '\\';
      out[j++] = '"';
      break;
    case '\n':
      out[j++] = '\\';
      out[j++] = 'n';
      break;
    case '\r':
      out[j++] = '\\';
      out[j++] = 'r';
      break;
    case '\t':
      out[j++] = '\\';
      out[j++] = 't';
      break;
    default:
      out[j++] = (char)c;
      break;
    }
  }
  out[j] = '\0';
  return out;
}

static void np_apply_credentials(struct smb2_context *ctx, const char *username,
                                 const char *password, const char *domain) {
  if (ctx == NULL) {
    return;
  }
  if (!np_is_empty(domain)) {
    smb2_set_domain(ctx, domain);
  }
  if (!np_is_empty(username)) {
    smb2_set_user(ctx, username);
  } else {
    smb2_set_user(ctx, "guest");
  }
  if (password != NULL) {
    smb2_set_password(ctx, password);
  }
}

struct np_share_enum_state {
  volatile int done;
  int status;
  struct srvsvc_NetrShareEnum_rep *rep;
};

static void np_share_enum_cb(struct smb2_context *smb2, int status,
                             void *command_data, void *cb_data) {
  (void)smb2;
  struct np_share_enum_state *state = (struct np_share_enum_state *)cb_data;
  state->status = status;
  state->rep = (struct srvsvc_NetrShareEnum_rep *)command_data;
  state->done = 1;
}

static int np_run_until_done(struct smb2_context *ctx,
                             struct np_share_enum_state *state) {
  while (state->done == 0) {
    const int fd = smb2_get_fd(ctx);
    const int events = smb2_which_events(ctx);

    struct pollfd pfd;
    memset(&pfd, 0, sizeof(pfd));
    pfd.fd = fd;
    pfd.events = (short)events;

    int rc = poll(&pfd, 1, 1000);
    if (rc < 0) {
      if (errno == EINTR) {
        continue;
      }
      return -errno;
    }

    rc = smb2_service(ctx, rc > 0 ? pfd.revents : 0);
    if (rc < 0) {
      return rc;
    }
  }
  return 0;
}

static int np_share_enum_sync(struct smb2_context *ctx,
                              struct srvsvc_NetrShareEnum_rep **out_rep) {
  if (ctx == NULL || out_rep == NULL) {
    return -EINVAL;
  }

  struct np_share_enum_state state;
  memset(&state, 0, sizeof(state));
  state.done = 0;
  state.status = 0;
  state.rep = NULL;

  int rc = smb2_share_enum_async(ctx, SHARE_INFO_1, np_share_enum_cb, &state);
  if (rc != 0) {
    return rc;
  }

  rc = np_run_until_done(ctx, &state);
  if (rc != 0) {
    if (state.rep != NULL) {
      smb2_free_data(ctx, state.rep);
    }
    return rc;
  }

  if (state.status != 0 || state.rep == NULL) {
    if (state.rep != NULL) {
      smb2_free_data(ctx, state.rep);
    }
    return -EIO;
  }

  *out_rep = state.rep;
  return 0;
}

static char *np_list_shares_json(const char *host, int port,
                                 const char *username, const char *password,
                                 const char *domain, char *err_buf,
                                 int err_len) {
  struct smb2_context *ctx = smb2_init_context();
  if (ctx == NULL) {
    np_set_err(err_buf, err_len, "smb2_init_context failed");
    return NULL;
  }

  np_apply_credentials(ctx, username, password, domain);

  char server[1024];
  const int server_rc = np_build_server(host, port, server, sizeof(server));
  if (server_rc != 0) {
    np_set_err(err_buf, err_len, "Invalid server");
    smb2_destroy_context(ctx);
    return NULL;
  }

  const char *user_for_connect =
      (!np_is_empty(username)) ? username : "guest";

  int rc = smb2_connect_share(ctx, server, "IPC$", user_for_connect);
  if (rc != 0) {
    np_set_err(err_buf, err_len, "SMB connect IPC$ failed: %s",
               smb2_get_error(ctx));
    smb2_destroy_context(ctx);
    return NULL;
  }

  struct srvsvc_NetrShareEnum_rep *rep = NULL;
  rc = np_share_enum_sync(ctx, &rep);
  if (rc != 0 || rep == NULL) {
    np_set_err(err_buf, err_len, "SMB share enum failed: %s", smb2_get_error(ctx));
    smb2_destroy_context(ctx);
    return NULL;
  }

  char *json = NULL;
  size_t len = 0;
  size_t cap = 0;
  np_json_append(&json, &len, &cap, "[");

  bool first = true;

  if (rep->ses.ShareInfo.Level == SHARE_INFO_1) {
    const uint32_t count = rep->ses.ShareInfo.Level1.EntriesRead;
    struct srvsvc_SHARE_INFO_1_carray *buffer = rep->ses.ShareInfo.Level1.Buffer;
    if (buffer != NULL && buffer->share_info_1 != NULL) {
      for (uint32_t i = 0; i < count; i++) {
        struct srvsvc_SHARE_INFO_1 *info = &buffer->share_info_1[i];
        const uint32_t type = info->type & 0x3;
        if (type != SHARE_TYPE_DISKTREE) {
          continue;
        }
        const char *name = info->netname.utf8;
        if (np_is_empty(name)) {
          continue;
        }
        // Skip hidden shares by default.
        const size_t name_len = strlen(name);
        if (name_len > 0 && name[name_len - 1] == '$') {
          continue;
        }

        char *escaped_name = np_json_escape(name);
        if (escaped_name == NULL) {
          continue;
        }

        char path_buf[2048];
        snprintf(path_buf, sizeof(path_buf), "/%s", name);
        char *escaped_path = np_json_escape(path_buf);

        if (!first) {
          np_json_append(&json, &len, &cap, ",");
        }
        first = false;

        np_json_append(&json, &len, &cap, "{\"name\":\"");
        np_json_append(&json, &len, &cap, escaped_name);
        np_json_append(&json, &len, &cap,
                       "\",\"path\":\"");
        np_json_append(&json, &len, &cap, escaped_path ? escaped_path : "");
        np_json_append(&json, &len, &cap,
                       "\",\"isDirectory\":true,\"size\":0,\"isShare\":true}");

        free(escaped_name);
        if (escaped_path) {
          free(escaped_path);
        }
      }
    }
  }

  np_json_append(&json, &len, &cap, "]");

  smb2_free_data(ctx, rep);
  smb2_destroy_context(ctx);
  return json;
}

static char *np_list_dir_json(const char *host, int port, const char *username,
                              const char *password, const char *domain,
                              const char *normalized_path, char *err_buf,
                              int err_len) {
  char share[512];
  char inner_path[4096];
  const int parse_rc = np_parse_share_and_path(normalized_path, share,
                                               sizeof(share), inner_path,
                                               sizeof(inner_path));
  if (parse_rc != 0) {
    np_set_err(err_buf, err_len, "Invalid SMB path: %s", normalized_path);
    return NULL;
  }

  struct smb2_context *ctx = smb2_init_context();
  if (ctx == NULL) {
    np_set_err(err_buf, err_len, "smb2_init_context failed");
    return NULL;
  }
  np_apply_credentials(ctx, username, password, domain);

  char server[1024];
  const int server_rc = np_build_server(host, port, server, sizeof(server));
  if (server_rc != 0) {
    np_set_err(err_buf, err_len, "Invalid server");
    smb2_destroy_context(ctx);
    return NULL;
  }

  const char *user_for_connect =
      (!np_is_empty(username)) ? username : "guest";

  int rc = smb2_connect_share(ctx, server, share, user_for_connect);
  if (rc != 0) {
    np_set_err(err_buf, err_len, "SMB connect share failed: %s",
               smb2_get_error(ctx));
    smb2_destroy_context(ctx);
    return NULL;
  }

  struct smb2dir *dir = smb2_opendir(ctx, inner_path);
  if (dir == NULL) {
    np_set_err(err_buf, err_len, "SMB opendir failed: %s", smb2_get_error(ctx));
    smb2_destroy_context(ctx);
    return NULL;
  }

  char *json = NULL;
  size_t len = 0;
  size_t cap = 0;
  np_json_append(&json, &len, &cap, "[");
  bool first = true;

  struct smb2dirent *ent;
  while ((ent = smb2_readdir(ctx, dir)) != NULL) {
    const char *name = ent->name;
    if (name == NULL) {
      continue;
    }
    if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) {
      continue;
    }

    const bool is_dir = ent->st.smb2_type == SMB2_TYPE_DIRECTORY;
    const uint64_t size = ent->st.smb2_size;

    char full_path[8192];
    if (strcmp(inner_path, "/") == 0) {
      snprintf(full_path, sizeof(full_path), "/%s/%s", share, name);
    } else {
      // inner_path starts with '/', and may end with '/'.
      if (inner_path[strlen(inner_path) - 1] == '/') {
        snprintf(full_path, sizeof(full_path), "/%s%s%s", share, inner_path,
                 name);
      } else {
        snprintf(full_path, sizeof(full_path), "/%s%s/%s", share, inner_path,
                 name);
      }
    }

    char *escaped_name = np_json_escape(name);
    char *escaped_path = np_json_escape(full_path);
    if (escaped_name == NULL || escaped_path == NULL) {
      if (escaped_name)
        free(escaped_name);
      if (escaped_path)
        free(escaped_path);
      continue;
    }

    if (!first) {
      np_json_append(&json, &len, &cap, ",");
    }
    first = false;

    char size_buf[64];
    snprintf(size_buf, sizeof(size_buf), "%llu",
             (unsigned long long)(is_dir ? 0 : size));

    np_json_append(&json, &len, &cap, "{\"name\":\"");
    np_json_append(&json, &len, &cap, escaped_name);
    np_json_append(&json, &len, &cap, "\",\"path\":\"");
    np_json_append(&json, &len, &cap, escaped_path);
    np_json_append(&json, &len, &cap, "\",\"isDirectory\":");
    np_json_append(&json, &len, &cap, is_dir ? "true" : "false");
    np_json_append(&json, &len, &cap, ",\"size\":");
    np_json_append(&json, &len, &cap, size_buf);
    np_json_append(&json, &len, &cap, ",\"isShare\":false}");

    free(escaped_name);
    free(escaped_path);
  }

  np_json_append(&json, &len, &cap, "]");
  smb2_closedir(ctx, dir);
  smb2_destroy_context(ctx);
  return json;
}

FFI_PLUGIN_EXPORT void np_smb2_free(void *ptr) { free(ptr); }

FFI_PLUGIN_EXPORT char *np_smb2_list_entries_json(const char *host, int port,
                                                  const char *username,
                                                  const char *password,
                                                  const char *domain,
                                                  const char *path,
                                                  char *err_buf, int err_len) {
  char *normalized = np_normalize_path(path);
  if (normalized == NULL) {
    np_set_err(err_buf, err_len, "Out of memory");
    return NULL;
  }

  char *result = NULL;
  if (strcmp(normalized, "/") == 0) {
    result = np_list_shares_json(host, port, username, password, domain,
                                 err_buf, err_len);
  } else {
    result = np_list_dir_json(host, port, username, password, domain,
                              normalized, err_buf, err_len);
  }

  free(normalized);
  return result;
}

FFI_PLUGIN_EXPORT int np_smb2_stat(const char *host, int port,
                                  const char *username, const char *password,
                                  const char *domain, const char *path,
                                  uint32_t *out_type, uint64_t *out_size,
                                  char *err_buf, int err_len) {
  if (out_type == NULL || out_size == NULL) {
    np_set_err(err_buf, err_len, "Invalid output pointers");
    return -EINVAL;
  }

  char *normalized = np_normalize_path(path);
  if (normalized == NULL) {
    np_set_err(err_buf, err_len, "Out of memory");
    return -ENOMEM;
  }
  if (strcmp(normalized, "/") == 0) {
    free(normalized);
    np_set_err(err_buf, err_len, "Cannot stat root path");
    return -EINVAL;
  }

  char share[512];
  char inner_path[4096];
  const int parse_rc = np_parse_share_and_path(normalized, share, sizeof(share),
                                               inner_path, sizeof(inner_path));
  free(normalized);
  if (parse_rc != 0) {
    np_set_err(err_buf, err_len, "Invalid SMB path");
    return parse_rc;
  }

  struct smb2_context *ctx = smb2_init_context();
  if (ctx == NULL) {
    np_set_err(err_buf, err_len, "smb2_init_context failed");
    return -ENOMEM;
  }

  np_apply_credentials(ctx, username, password, domain);

  char server[1024];
  const int server_rc = np_build_server(host, port, server, sizeof(server));
  if (server_rc != 0) {
    np_set_err(err_buf, err_len, "Invalid server");
    smb2_destroy_context(ctx);
    return server_rc;
  }

  const char *user_for_connect =
      (!np_is_empty(username)) ? username : "guest";

  int rc = smb2_connect_share(ctx, server, share, user_for_connect);
  if (rc != 0) {
    np_set_err(err_buf, err_len, "SMB connect share failed: %s",
               smb2_get_error(ctx));
    smb2_destroy_context(ctx);
    return rc;
  }

  struct smb2_stat_64 st;
  memset(&st, 0, sizeof(st));
  rc = smb2_stat(ctx, inner_path, &st);
  if (rc != 0) {
    np_set_err(err_buf, err_len, "SMB stat failed: %s", smb2_get_error(ctx));
    smb2_destroy_context(ctx);
    return rc;
  }

  *out_type = st.smb2_type;
  *out_size = st.smb2_size;
  smb2_destroy_context(ctx);
  return 0;
}

FFI_PLUGIN_EXPORT intptr_t np_smb2_reader_open(
    const char *host, int port, const char *username, const char *password,
    const char *domain, const char *path, uint64_t *out_size, char *err_buf,
    int err_len) {
  if (out_size == NULL) {
    np_set_err(err_buf, err_len, "Invalid out_size");
    return (intptr_t)0;
  }

  char *normalized = np_normalize_path(path);
  if (normalized == NULL) {
    np_set_err(err_buf, err_len, "Out of memory");
    return (intptr_t)0;
  }
  if (strcmp(normalized, "/") == 0) {
    free(normalized);
    np_set_err(err_buf, err_len, "Cannot open root path");
    return (intptr_t)0;
  }

  char share[512];
  char inner_path[4096];
  const int parse_rc = np_parse_share_and_path(normalized, share, sizeof(share),
                                               inner_path, sizeof(inner_path));
  free(normalized);
  if (parse_rc != 0) {
    np_set_err(err_buf, err_len, "Invalid SMB path");
    return (intptr_t)0;
  }

  struct smb2_context *ctx = smb2_init_context();
  if (ctx == NULL) {
    np_set_err(err_buf, err_len, "smb2_init_context failed");
    return (intptr_t)0;
  }
  np_apply_credentials(ctx, username, password, domain);

  char server[1024];
  const int server_rc = np_build_server(host, port, server, sizeof(server));
  if (server_rc != 0) {
    np_set_err(err_buf, err_len, "Invalid server");
    smb2_destroy_context(ctx);
    return (intptr_t)0;
  }

  const char *user_for_connect =
      (!np_is_empty(username)) ? username : "guest";

  int rc = smb2_connect_share(ctx, server, share, user_for_connect);
  if (rc != 0) {
    np_set_err(err_buf, err_len, "SMB connect share failed: %s",
               smb2_get_error(ctx));
    smb2_destroy_context(ctx);
    return (intptr_t)0;
  }

  struct smb2fh *fh = smb2_open(ctx, inner_path, O_RDONLY);
  if (fh == NULL) {
    np_set_err(err_buf, err_len, "SMB open failed: %s", smb2_get_error(ctx));
    smb2_destroy_context(ctx);
    return (intptr_t)0;
  }

  struct smb2_stat_64 st;
  memset(&st, 0, sizeof(st));
  rc = smb2_fstat(ctx, fh, &st);
  if (rc != 0) {
    np_set_err(err_buf, err_len, "SMB fstat failed: %s", smb2_get_error(ctx));
    smb2_close(ctx, fh);
    smb2_destroy_context(ctx);
    return (intptr_t)0;
  }
  if (st.smb2_type == SMB2_TYPE_DIRECTORY) {
    np_set_err(err_buf, err_len, "Path is a directory");
    smb2_close(ctx, fh);
    smb2_destroy_context(ctx);
    return (intptr_t)0;
  }

  np_smb2_reader_t *reader = (np_smb2_reader_t *)calloc(1, sizeof(*reader));
  if (reader == NULL) {
    np_set_err(err_buf, err_len, "Out of memory");
    smb2_close(ctx, fh);
    smb2_destroy_context(ctx);
    return (intptr_t)0;
  }

  reader->ctx = ctx;
  reader->fh = fh;
  reader->size = st.smb2_size;

  *out_size = reader->size;
  return (intptr_t)reader;
}

FFI_PLUGIN_EXPORT int np_smb2_reader_pread(intptr_t reader_ptr,
                                          uint64_t offset, uint8_t *buf,
                                          uint32_t count, char *err_buf,
                                          int err_len) {
  if (reader_ptr == 0 || buf == NULL || count == 0) {
    np_set_err(err_buf, err_len, "Invalid arguments");
    return -EINVAL;
  }
  np_smb2_reader_t *reader = (np_smb2_reader_t *)reader_ptr;
  if (reader->ctx == NULL || reader->fh == NULL) {
    np_set_err(err_buf, err_len, "Reader is closed");
    return -EINVAL;
  }
  const int rc = smb2_pread(reader->ctx, reader->fh, buf, count, offset);
  if (rc < 0) {
    np_set_err(err_buf, err_len, "SMB read failed: %s",
               smb2_get_error(reader->ctx));
  }
  return rc;
}

FFI_PLUGIN_EXPORT void np_smb2_reader_close(intptr_t reader_ptr) {
  if (reader_ptr == 0) {
    return;
  }
  np_smb2_reader_t *reader = (np_smb2_reader_t *)reader_ptr;
  if (reader->ctx != NULL && reader->fh != NULL) {
    smb2_close(reader->ctx, reader->fh);
    reader->fh = NULL;
  }
  if (reader->ctx != NULL) {
    smb2_destroy_context(reader->ctx);
    reader->ctx = NULL;
  }
  free(reader);
}
