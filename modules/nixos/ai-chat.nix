# LibreChat (local ChatGPT-style UI) + bootstrap for credentials / API keys.
# Codex CLI and DeepSeek Harness (dsh) are user packages in home/programs.nix.
{
  pkgs,
  ...
}:

let
  credsFile = "/var/lib/librechat/credentials.env";
  # dsh web defaults to 3080; keep LibreChat on a distinct loopback port.
  librechatPort = 3081;
in
{
  services.librechat = {
    enable = true;
    enableLocalDB = true;
    openFirewall = false;
    credentialsFile = credsFile;
    env = {
      HOST = "127.0.0.1";
      PORT = librechatPort;
      ALLOW_REGISTRATION = true;
      # Built-in OpenAI endpoint activates when OPENAI_API_KEY is in credentials.env.
    };
    settings = {
      version = "1.2.1";
      cache = true;
      endpoints = {
        custom = [
          {
            name = "Deepseek";
            apiKey = "\${DEEPSEEK_API_KEY}";
            baseURL = "https://api.deepseek.com/v1";
            models = {
              default = [
                "deepseek-chat"
                "deepseek-reasoner"
              ];
              fetch = false;
            };
            titleConvo = true;
            titleModel = "deepseek-chat";
            modelDisplayLabel = "Deepseek";
          }
        ];
      };
    };
  };

  # nixpkgs librechat module does not wait on mongodb when enableLocalDB is set.
  systemd.services.librechat = {
    after = [ "mongodb.service" ];
    requires = [ "mongodb.service" ];
  };

  systemd.services.librechat-bootstrap-creds = {
    description = "Create LibreChat credentials.env if missing";
    wantedBy = [ "librechat.service" ];
    before = [ "librechat.service" ];
    requiredBy = [ "librechat.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.coreutils
      pkgs.openssl
    ];
    script = ''
      set -eu
      dir=/var/lib/librechat
      file=${credsFile}
      mkdir -p "$dir"
      if [ ! -f "$file" ]; then
        umask 077
        {
          echo "# LibreChat secrets (auto-generated). Edit to add API keys, then:"
          echo "#   sudo systemctl restart librechat"
          echo "CREDS_KEY=$(openssl rand -hex 32)"
          echo "CREDS_IV=$(openssl rand -hex 16)"
          echo "JWT_SECRET=$(openssl rand -hex 32)"
          echo "JWT_REFRESH_SECRET=$(openssl rand -hex 32)"
          echo "# OPENAI_API_KEY=sk-..."
          echo "# DEEPSEEK_API_KEY=sk-..."
        } > "$file"
        if id librechat >/dev/null 2>&1; then
          chown librechat:librechat "$file"
        fi
        chmod 600 "$file"
      fi
    '';
  };
}
