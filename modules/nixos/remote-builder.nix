# Offload Nix builds to WSL2 on the LAN Windows box (Tailscale: galleria-mitac).
# Local max-jobs stay enabled so builds fall back here if the remote is down.
#
# One-time on the builder: Nix + sshd (port 2222), this host's pubkey in
# authorized_keys, user in trusted-users. Key on this machine:
#   ~/.ssh/id_wsl_builder (passphrase-less; nix-daemon cannot prompt).

{ ... }:

{
  # Tailscale MagicDNS is unreliable while Cloudflare WARP owns resolv.conf;
  # pin the stable CGNAT address (galleria-mitac).
  programs.ssh.extraConfig = ''
    Host wsl-builder galleria-mitac
      HostName 100.102.102.53
      Port 2222
      User mitac
      IdentityFile /home/mitac/.ssh/id_wsl_builder
      IdentitiesOnly yes
  '';

  nix.distributedBuilds = true;
  nix.settings = {
    builders-use-substitutes = true;
    # Fail over to local builds quickly when WSL is asleep / offline.
    connect-timeout = 5;
  };

  nix.buildMachines = [
    {
      hostName = "wsl-builder";
      sshUser = "mitac";
      sshKey = "/home/mitac/.ssh/id_wsl_builder";
      system = "x86_64-linux";
      # WSL is not NixOS; ssh-ng often breaks on non-interactive PATH.
      protocol = "ssh";
      maxJobs = 8;
      speedFactor = 2;
      # Omit kvm: nested virt in WSL is hit-or-miss.
      supportedFeatures = [
        "big-parallel"
        "nixos-test"
      ];
      # ssh-keyscan -p 2222 -t ed25519 galleria-mitac
      publicHostKey = "AAAAC3NzaC1lZDI1NTE5AAAAID+Dgx7oDIHOa5CPTkDbeGqIjGsCf2evYSI/pRIjz7H0";
    }
  ];
}
