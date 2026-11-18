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
        ember = pkgs.buildGoModule {
          pname = "ember-shell";
          version = "1.0.5";
          src = self;
          modRoot = "linux";
          vendorHash = "sha256-N98D/+RfTCw4Ui7b0liVWqyVXp2qtRzSK3g2PgTxVzE=";
          subPackages = [ "cmd/ember" ];
          tags = [ "novulkan" ];
          ldflags = [ "-s" "-w" ];
          doCheck = false;
          nativeBuildInputs = with pkgs; [ pkg-config makeWrapper ];
          buildInputs = with pkgs; [
            wayland libxkbcommon libGL xorg.libX11 xorg.libXcursor xorg.libXfixes xorg.libxcb
          ];
          # Gio opens EGL, OpenGL ES and the Wayland libraries at run time
          postFixup = ''
            wrapProgram $out/bin/ember --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath (with pkgs; [ libGL wayland libxkbcommon xorg.libX11 xorg.libXcursor ])}
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
