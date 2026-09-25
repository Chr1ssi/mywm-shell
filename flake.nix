{
  description = "Compositor-independent Quickshell desktop shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          shell = pkgs.writeShellApplication {
            name = "mywm-shell";
            runtimeInputs = with pkgs; [
              coreutils
              findutils
              niri
              quickshell
              swayidle
              swaylock
              systemd
              wlopm
            ];
            text = builtins.readFile ./scripts/mywm-shell;
            runtimeEnv.MYWM_SHELL_DIR = "${self}/quickshell";
          };
        in
        {
          default = shell;
          mywm-shell = shell;
        });
    };
}
