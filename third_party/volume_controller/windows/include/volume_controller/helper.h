#ifndef HELPER_H_
#define HELPER_H_

#include <flutter/encodable_value.h>

const flutter::EncodableValue *GetArgValue(const flutter::EncodableMap &map, const char *key);

#endif // HELPER_H_