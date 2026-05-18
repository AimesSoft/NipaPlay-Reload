{
  description = "NipaPlay-Reload - A cross-platform danmaku video player";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        rustLib = pkgs.rustPlatform.buildRustPackage {
          pname = "rust_lib_nipaplay";
          version = "0.1.0";
          src = ./rust;
          cargoLock.lockFile = ./rust/Cargo.lock;
          nativeBuildInputs = with pkgs; [ pkg-config ];
        };

        rustup-fake = pkgs.writeShellScriptBin "rustup" ''
          case "''${1:-}" in
            toolchain)
              case "''${2:-}" in
                list) echo "stable-''${HOSTTYPE:-x86_64}-unknown-linux-gnu (default)" ;;
                install) exit 0 ;;
                *) exit 0 ;;
              esac ;;
            target)
              case "''${2:-}" in
                list) echo "''${HOSTTYPE:-x86_64}-unknown-linux-gnu" ;;
                add) exit 0 ;;
                *) exit 0 ;;
              esac ;;
            component)
              case "''${2:-}" in
                add) exit 0 ;;
                *) exit 0 ;;
              esac ;;
            run) shift; shift; exec "$@" ;;
            *) exit 0 ;;
          esac
        '';

        deps = with pkgs; [
          alsa-lib
          clang
          cmake
          ffmpeg
          libayatana-appindicator
          libepoxy
          libplacebo
          libunwind
          mpv
          gtk3
          keybinder3
          xz
          libass
          libdeflate
          mesa
          mimalloc
          ninja
          pango
          pkg-config
          libxkbcommon
          libx11
          libxcomposite
          libxcursor
          libxdamage
          libxext
          libxfixes
          libxi
          libxinerama
          libxrandr
          libxrender
          libxtst
          libxcb
        ];

        inherit (pkgs) flutter;
      in
      {
        packages = {
          default = self.packages.${system}.nipaplay-reload;
          nipaplay-reload = flutter.buildFlutterApplication {
            pname = "nipaplay";
            version = "1.10.6";

            src = pkgs.lib.cleanSource self;

            packageRoot = ".";

            pubspecLock = pkgs.lib.importJSON ./pubspec.lock.json;

            targetFlutterPlatform = "linux";

            customSourceBuilders = {
              rust_lib_nipaplay = { version, src, ... }:
                pkgs.runCommand "rust_lib_nipaplay-${version}" {
                  inherit (src) passthru;
                } ''
                  cp -r ${src}/. "$out"
                  chmod -R u+w "$out"
                  cat > "$out/rust_builder/linux/CMakeLists.txt" << CMAKEEOF
                  cmake_minimum_required(VERSION 3.10)
                  set(PROJECT_NAME "rust_lib_nipaplay")
                  project(''${PROJECT_NAME} LANGUAGES CXX)
                  set(rust_lib_nipaplay_bundled_libraries
                    "${rustLib}/lib/librust_lib_nipaplay.so"
                    PARENT_SCOPE
                  )
                  CMAKEEOF
                '';
            };

            nativeBuildInputs = deps ++ (with pkgs; [ rustup-fake ]);

            buildInputs = with pkgs; [
              at-spi2-atk
              at-spi2-core
              cairo
              dbus
              gdk-pixbuf
              glib
            ];

            dontUseCmakeConfigure = true;
          };
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/nipaplay";
        };

        devShells.default = pkgs.mkShell {
          packages = deps ++ (with pkgs; [
            flutter
            cargo
            rustc
            rustup-fake
          ]);

          shellHook = ''
            if [ ! -f "$HOME/.flutter" ]; then
              mkdir -p "$HOME/.flutter"
              flutter config --enable-linux-desktop --no-analytics 2>/dev/null || true
            fi

            echo "=== NipaPlay-Reload Dev Shell ==="
            echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo '${flutter.version}')"
            echo "Rust:    $(rustc --version 2>/dev/null || echo 'unknown')"
            echo "CMake:   $(cmake --version 2>/dev/null | head -1 || echo 'unknown')"
            echo ""
            echo "Build:  flutter build linux --release"
            echo "Server: cd server && python3 server.py"
          '';
        };
      }
    );
}
