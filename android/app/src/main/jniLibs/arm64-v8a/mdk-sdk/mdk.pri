# for qmake

MDK_SDK = $$PWD
# CONFIG -= rtti exceptions # build with abi sdk

INCLUDEPATH += $$MDK_SDK/include
contains(QT_ARCH, x.*64) {
  android: MDK_ARCH = x86_64
  else:linux: MDK_ARCH = amd64
  else: MDK_ARCH = x64
} else:contains(QT_ARCH, .*86) {
  MDK_ARCH = x86
} else:contains(QT_ARCH, a.*64.*) { # arm64-v8a
  android: MDK_ARCH = arm64-v8a
  else: MDK_ARCH = arm64
} else:contains(QT_ARCH, arm.*) {
  android: MDK_ARCH = armeabi-v7a
  else:linux: MDK_ARCH = armhf
  else: MDK_ARCH = arm
}
!exists($$MDK_SDK/lib/$$MDK_ARCH): MDK_ARCH=  # mac or local builds

macx|ios {
  MDK_FWK_DIR = $$MDK_SDK/lib
  MDK_XCFWK_DIR = $$MDK_SDK/lib/mdk.xcframework
  exists($$MDK_XCFWK_DIR): {
    macx: MDK_FWK_DIR = $$MDK_XCFWK_DIR/macos-arm64_x86_64
    ios: MDK_FWK_DIR = $$MDK_XCFWK_DIR/ios-arm64
  }
  message("MDK_FWK_DIR:$$MDK_FWK_DIR, MDK_SDK:$$MDK_SDK")
  QMAKE_CXXFLAGS += -F$$MDK_FWK_DIR
  LIBS += -F$$MDK_FWK_DIR -framework mdk
} else {
  LIBS += -L$$MDK_SDK/lib/$$MDK_ARCH -lmdk
  win32: LIBS += -L$$MDK_SDK/bin/$$MDK_ARCH # qtcreator will prepend $$LIBS to PATH to run targets
}
linux: LIBS += -Wl,-rpath-link,$$MDK_SDK/lib/$$MDK_ARCH # for libc++ symbols
linux: LIBS += -Wl,-rpath,$$MDK_SDK/lib/$$MDK_ARCH

mac {
  RPATHDIR *= @executable_path/Frameworks $$MDK_SDK/lib
  QMAKE_LFLAGS_SONAME = -Wl,-install_name,@rpath/
  isEmpty(QMAKE_LFLAGS_RPATH): QMAKE_LFLAGS_RPATH=-Wl,-rpath,
  for(R,RPATHDIR) {
    QMAKE_LFLAGS *= \'$${QMAKE_LFLAGS_RPATH}$$R\'
  }
}
