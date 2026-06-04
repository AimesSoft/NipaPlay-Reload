String buildTargetLabelFromParts({
  required String architecture,
  required String platform,
}) {
  final formattedArchitecture = _formatArchitecture(architecture);
  final formattedPlatform = _formatPlatform(platform);

  if (formattedArchitecture.isEmpty) {
    return formattedPlatform;
  }
  if (formattedPlatform.isEmpty) {
    return formattedArchitecture;
  }
  return '$formattedArchitecture $formattedPlatform';
}

String _formatArchitecture(String rawValue) {
  final value =
      rawValue.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
  if (value.isEmpty) {
    return '';
  }
  if (value.contains('riscv64')) {
    return 'RISC-V 64';
  }
  if (value.contains('riscv32')) {
    return 'RISC-V 32';
  }
  if (value.contains('arm64') ||
      value.contains('aarch64') ||
      value.contains('armv8')) {
    return 'Arm64';
  }
  if (value.contains('armv7') || value.contains('armeabiv7')) {
    return 'Armv7';
  }
  if (value == 'arm' || value.contains('armv6')) {
    return 'Arm';
  }
  if (value.contains('x8664') || value.contains('amd64') || value == 'x64') {
    return 'X64';
  }
  if (value.contains('ia32') ||
      value == 'x86' ||
      value.contains('i386') ||
      value.contains('i686')) {
    return 'X86';
  }
  return '';
}

String _formatPlatform(String rawValue) {
  final value = rawValue.trim().toLowerCase();
  if (value.isEmpty) {
    return '';
  }
  if (value.contains('ios')) {
    return 'iOS';
  }
  if (value.contains('android')) {
    return 'Android';
  }
  if (value.contains('macos') ||
      value.contains('mac os') ||
      value.contains('darwin')) {
    return 'macOS';
  }
  if (value.contains('windows')) {
    return 'Windows';
  }
  if (value.contains('linux')) {
    return 'Linux';
  }
  if (value.contains('web') || value.contains('browser')) {
    return 'Web';
  }
  if (value.contains('fuchsia')) {
    return 'Fuchsia';
  }
  return '';
}
