{
  description = "Utilities to use betterfox's user.js for Firefox";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/*.tar.gz";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    pre-commit.url = "github:cachix/pre-commit-hooks.nix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    pre-commit,
    flake-utils,
    ...
  }: let
    inherit (nixpkgs.lib) mapAttrs' nameValuePair;

    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forEachSupportedSystem = f:
      nixpkgs.lib.genAttrs supportedSystems (system:
        f {
          pkgs = import nixpkgs {inherit system;};
        });

    ppVer = builtins.replaceStrings ["."] ["_"];
    docs = pkgs:
      (mapAttrs'
        (version: extracted:
          nameValuePair "betterfox-v${ppVer version}-doc-static"
          (pkgs.callPackage ./doc {inherit extracted version;}))
        self.lib.betterfox.extracted)
      // (mapAttrs'
        (version: extracted:
          nameValuePair "betterfox-v${ppVer version}-doc"
          (pkgs.callPackage ./doc {
            inherit extracted version;
            css = "/style.css";
          }))
        self.lib.betterfox.extracted);

    outputs = flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages."${system}";
      extractor = pkgs.callPackage ./extractor {};
      generator = pkgs.callPackage ./generator {betterfox-extractor = extractor;};
    in {
      checks.pre-commit-check = pre-commit.lib."${system}".run {
        src = ./.;
        hooks = {
          alejandra.enable = true;
          deadnix.enable = true;
          statix.enable = true;
          black = {
            enable = true;
            name = "Format Python code with black";
            types = ["python"];
            entry = "${pkgs.python3Packages.black}/bin/black";
          };
        };
        settings = {
          alejandra.exclude = ["autogen"];
          statix.ignore = ["autogen/*"];
        };
      };

      packages =
        {
          betterfox-extractor = extractor;
          betterfox-generator = generator;
          betterfox-doc-css = pkgs.writeText "style.css" (builtins.readFile ./doc/style.css);
          default = extractor;
        }
        // (docs pkgs);
    });
  in
    outputs
    // {
      overlays = {
        betterfox = _: prev: (let
          extractor = prev.callPackage ./extractor {};
        in
          {
            betterfox-extractor = prev.callPackage ./extractor {};
            betterfox-generator = prev.callPackage ./generator {betterfox-extractor = extractor;};
            betterfox-doc-css = prev.writeText "style.css" (builtins.readFile ./doc/style.css);
          }
          // (docs prev));
        default = self.overlays.betterfox;
      };

      devShells = forEachSupportedSystem ({pkgs}: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            cachix
            lorri
            nil
            statix
            vulnix
            haskellPackages.dhall-nix
            python39Packages.requests
          ];
        };
      });

      lib.betterfox = {
        supportedVersions = builtins.attrNames self.lib.betterfox.extracted;
        extracted = import ./autogen;
      };

      hmModules = {
        betterfox = import ./hm.nix self.lib.betterfox.supportedVersions self.lib.betterfox.extracted;
        default = self.hmModules.betterfox;
      };
    };
}
