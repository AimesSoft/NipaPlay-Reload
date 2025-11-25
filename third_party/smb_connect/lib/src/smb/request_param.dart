///
/// Internal use only
///
/// @author mbechler
enum RequestParam {
  NONE,

  /// Wait indefinitely for a response
  NO_TIMEOUT,

  /// Do not retry request on failure
  NO_RETRY,

  /// Save the raw payload for further inspection
  RETAIN_PAYLOAD
}
