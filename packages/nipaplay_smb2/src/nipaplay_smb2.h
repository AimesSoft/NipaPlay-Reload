#pragma once

#include <stdint.h>
#include <stdlib.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Free memory returned from this library.
FFI_PLUGIN_EXPORT void np_smb2_free(void *ptr);

/// List SMB shares (root path) or directory entries as JSON array.
///
/// `path` accepts `/`, `/share`, `/share/dir`.
/// Returns a malloc-allocated UTF-8 JSON string on success; returns NULL on
/// error and writes a message into `err_buf`.
FFI_PLUGIN_EXPORT char *np_smb2_list_entries_json(const char *host, int port,
                                                  const char *username,
                                                  const char *password,
                                                  const char *domain,
                                                  const char *path,
                                                  char *err_buf, int err_len);

/// Stat a SMB path.
/// Returns 0 on success, <0 on failure (negative errno-like).
FFI_PLUGIN_EXPORT int np_smb2_stat(const char *host, int port,
                                  const char *username, const char *password,
                                  const char *domain, const char *path,
                                  uint32_t *out_type, uint64_t *out_size,
                                  char *err_buf, int err_len);

/// Open a file reader for streaming reads.
/// Returns a non-zero opaque handle on success; 0 on failure.
FFI_PLUGIN_EXPORT intptr_t np_smb2_reader_open(
    const char *host, int port, const char *username, const char *password,
    const char *domain, const char *path, uint64_t *out_size, char *err_buf,
    int err_len);

/// Read bytes at `offset` into `buf`.
/// Returns >=0 bytes read, or <0 on failure (negative errno-like).
FFI_PLUGIN_EXPORT int np_smb2_reader_pread(intptr_t reader, uint64_t offset,
                                          uint8_t *buf, uint32_t count,
                                          char *err_buf, int err_len);

/// Close and free a reader handle.
FFI_PLUGIN_EXPORT void np_smb2_reader_close(intptr_t reader);

#ifdef __cplusplus
} // extern "C"
#endif
