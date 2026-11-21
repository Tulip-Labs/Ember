{
  description = "Ember, a calm full-screen home for the niri compositor";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: rec {
        # Ember 2 is Swift (6.0 or newer), GTK 4 and libadwaita; it has no
        # Swift packages to fetch, so SwiftPM builds it offline
        ember = pkgs.swiftPackages.stdenv.mkDerivation {
          pname = "ember-shell";
          version = "2.0.0";
          src = self;
          sourceRoot = "source/linux";
          nativeBuildInputs = with pkgs; [ swiftPackages.swift swiftPackages.swiftpm pkg-config wrapGAppsHook4 ];
          buildInputs = with pkgs; [ gtk4 libadwaita glib gdk-pixbuf swiftPackages.Foundation ];
          configurePhase = "true";
          buildPhase = ''
            runHook preBuild
            swift build -c release --disable-sandbox
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            install -Dm755 "$(swift build -c release --show-bin-path)/Ember" $out/bin/ember
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "A calm full-screen home for the niri compositor";
            homepage = "https://github.com/Tulip-Labs/Ember";
            license = licenses.gpl3Only;
            platforms = platforms.linux;
            mainProgram = "ember";
          };
        };
        default = ember;
      });
    };
}
