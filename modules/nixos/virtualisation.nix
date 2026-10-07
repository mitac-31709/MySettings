# libvirt + QEMU/KVM host (virt-manager GUI).
{ pkgs, ... }:

{
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      vhostUserPackages = with pkgs; [ virtiofsd ];
    };
  };

  # USB redirect to guests (Spice).
  virtualisation.spiceUSBRedirection.enable = true;

  programs.virt-manager.enable = true;

  users.users.mitac.extraGroups = [
    "libvirtd"
    "kvm"
  ];

  # Default NAT network (virbr0) needs the bridge trusted / DHCP+DNS open.
  networking.firewall.trustedInterfaces = [ "virbr0" ];

  environment.systemPackages = with pkgs; [
    virt-viewer
    qemu_kvm
  ];
}
