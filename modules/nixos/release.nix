# Optional milestone label for this configuration.
# Appears in the systemd-boot menu and in `nixos-rebuild list-generations`
# as part of system.nixos.label (e.g. rofi-cheatsheet-26.11....).
#
# Bump `system.nixos.tags` when you want a readable label on the next rebuild.
# Letters/digits/-/_/./: only. No Git tagging required.

{ ... }:

{
  system.nixos.tags = [ "cursor-meltype-ime" ];
}
