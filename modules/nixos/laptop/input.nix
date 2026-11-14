# Shared keyboard daemon (keyd): manual kernel OOM killer via Ctrl+Alt+Del
# (and Ctrl+Alt+Backspace) + virtual keyboard libinput quirk.
{
  lib,
  pkgs,
  ...
}:

let
  # keyd command(): invoke kernel OOM killer (SysRq-f). Prefer this over a
  # Sway bind — compositor may be wedged.
  sysrqOom = pkgs.writeShellScript "sysrq-oom" ''
    ${pkgs.coreutils}/bin/printf f > /proc/sysrq-trigger
  '';
in
{
  # Allow Magic SysRq via keyboard too (Alt+SysRq+letter). /proc/sysrq-trigger
  # ignores this mask; kept so classic SysRq still works if needed.
  boot.kernel.sysctl."kernel.sysrq" = 244;

  # keyd drops privileges to group "keyd"; NixOS module never creates it.
  users.groups.keyd = { };

  # nixpkgs keyd.nix: RestrictSUIDSGID + missing CAP_SETGID break setgid("keyd")
  # ("setgid: Operation not permitted"); ProcSubset=pid and
  # ProtectKernelTunables hide/RO-mount /proc/sysrq-trigger (sysrqOom).
  systemd.services.keyd.serviceConfig = {
    CapabilityBoundingSet = lib.mkForce [
      "CAP_SYS_NICE"
      "CAP_IPC_LOCK"
      "CAP_SETGID"
    ];
    RestrictSUIDSGID = lib.mkForce false;
    ProtectKernelTunables = lib.mkForce false;
    ProcSubset = lib.mkForce "all";
  };

  services.keyd = {
    enable = true;
    keyboards = {
      # Matches all keyboards (VAIO internal + external USB/BT keyboards) unless
      # a more specific host id block (e.g. chromebook/input.nix cros) matches.
      ctrl-alt-del-oom = {
        ids = [ "*" ];
        extraConfig = ''
          [control+alt]
          delete = command(${sysrqOom})
          backspace = command(${sysrqOom})
        '';
      };
    };
  };

  # Mark keyd's virtual keyboard as internal for libinput palm rejection.
  # Chromebook overrides this with ModelTabletModeNoSuspend=1.
  environment.etc."libinput/local-overrides.quirks".text = lib.mkDefault ''
    [keyd virtual keyboard]
    MatchName=keyd virtual keyboard
    AttrKeyboardIntegration=internal
  '';
}
