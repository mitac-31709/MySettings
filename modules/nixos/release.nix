# Milestone label for this configuration.
# Appears in the systemd-boot menu and in `nixos-rebuild list-generations`
# as part of system.nixos.label (e.g. plasma-bt-rbw-eu-26.11....).
#
# Workflow when the config's "story" changes:
# 1. Commit the functional change.
# 2. Update `system.nixos.tags` below to a short slug (letters/digits/-/_/./: only).
# 3. Commit that bump, then: sudo nixos-rebuild switch --flake .#mitac
# 4. Tag the commit: git tag -a "gen/NN-<slug>" -m "..." && git push origin "gen/NN-<slug>"
#
# Do not append rows to the README generations table (frozen / unused).

{ ... }:

{
  system.nixos.tags = [ "libvirt-qemu-kvm" ];
}
