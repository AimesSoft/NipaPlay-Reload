enum BackgroundImageRenderMode { opacity, softLight }

extension BackgroundImageRenderModeStorage on BackgroundImageRenderMode {
  String get storageKey {
    switch (this) {
      case BackgroundImageRenderMode.softLight:
        return 'soft_light';
      case BackgroundImageRenderMode.opacity:
      default:
        return 'opacity';
    }
  }

  static BackgroundImageRenderMode fromString(String? value) {
    if (value == 'soft_light') {
      return BackgroundImageRenderMode.softLight;
    }
    return BackgroundImageRenderMode.opacity;
  }
}
