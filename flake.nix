{
  description = "Seamless Coop: a REFramework plugin for Monster Hunter Wilds";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # What tools/check-plugin needs.
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.lua5_4 pkgs.lua54Packages.luacheck pkgs.emmylua-check ];
        };
      });
    };
}
