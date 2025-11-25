abstract class WinError {
  /// Don't bother to edit this. Everything within the interface
  /// block is automatically generated from the ntstatus package.
  static const int ERROR_SUCCESS = 0;
  static const int ERROR_ACCESS_DENIED = 5;
  static const int ERROR_REQ_NOT_ACCEP = 71;
  static const int ERROR_BAD_PIPE = 230;
  static const int ERROR_PIPE_BUSY = 231;
  static const int ERROR_NO_DATA = 232;
  static const int ERROR_PIPE_NOT_CONNECTED = 233;
  static const int ERROR_MORE_DATA = 234;
  static const int ERROR_SERVICE_NOT_INSTALLED = 2184;
  static const int ERROR_NO_BROWSER_SERVERS_FOUND = 6118;

  static const List<int> WINERR_CODES = [
    ERROR_SUCCESS,
    ERROR_ACCESS_DENIED,
    ERROR_REQ_NOT_ACCEP,
    ERROR_BAD_PIPE,
    ERROR_PIPE_BUSY,
    ERROR_NO_DATA,
    ERROR_PIPE_NOT_CONNECTED,
    ERROR_MORE_DATA,
    ERROR_SERVICE_NOT_INSTALLED,
    ERROR_NO_BROWSER_SERVERS_FOUND,
  ];

  static final List<String> WINERR_MESSAGES = [
    "The operation completed successfully.",
    "Access is denied.",
    "No more connections can be made to this remote computer at this time because there are already as many connections as the computer can accept.",
    "The pipe state is invalid.",
    "All pipe instances are busy.",
    "The pipe is being closed.",
    "No process is on the other end of the pipe.",
    "More data is available.",
    "The service is not available",
    "The list of servers for this workgroup is not currently available.",
  ];
}
