#ifndef CONSTANTS_H
#define CONSTANTS_H

namespace ChannelName
{
    constexpr const char *methodChannel = "com.kurenai7968.volume_controller.method";
    constexpr const char *eventChannel = "com.kurenai7968.volume_controller.volume_listener_event";
}

namespace MethodName
{
    constexpr const char *getVolume = "getVolume";
    constexpr const char *setVolume = "setVolume";
    constexpr const char *isMuted = "isMuted";
    constexpr const char *setMute = "setMute";
}

namespace MethodArgument
{
    constexpr const char *volume = "volume";
    constexpr const char *showSystemUI = "showSystemUI";
    constexpr const char *isMute = "isMute";
}

namespace EventArgument
{
    constexpr const char *fetchInitialVolume = "fetchInitialVolume";
}

#endif // CONSTANTS_H