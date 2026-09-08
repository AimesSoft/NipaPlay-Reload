/// PotPlayer's Windows message API is unavailable in a browser.
abstract class WindowsPotPlayerApi {
  static WindowsPotPlayerApi get instance =>
      throw UnsupportedError('PotPlayer 窗口控制仅支持 Windows');

  int postMessage(int windowHandle, int message, int wParam, int lParam);
  int sendMessage(int windowHandle, int message, int wParam, int lParam);
  int isWindow(int windowHandle);
  int getForegroundWindow();
  int setForegroundWindow(int windowHandle);
  void sendCtrlAltL();
  int findWindowForProcess(int processId);
}
