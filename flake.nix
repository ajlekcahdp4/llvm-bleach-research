{
  description = "llvm-bleach presentation";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      flake-parts,
      treefmt-nix,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ treefmt-nix.flakeModule ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { pkgs, self', ... }:
        {
          packages = {
            python3 = pkgs.python3.override {
              packageOverrides = pyself: _pyprev: {
                presenterm-export = pyself.callPackage ./presenterm-export.nix { };
              };
            };

            presenterm-export = self'.packages.python3.pkgs.presenterm-export;
          };
          imports = [ ./nix/treefmt.nix ];
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              mermaid-cli
              presenterm
              self'.packages.presenterm-export
            ];
          };
        };
    };
}
