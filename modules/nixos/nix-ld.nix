# nix-ld: run unpatched FHS/ELF binaries (dynamic linker + common libs).
#
# Needed so ChatGPT Desktop / Codex can execute its downloaded primary-runtime
# tools — especially bundled `git` under ~/.cache/codex-runtimes/.../native/git
# (otherwise stub-ld refuses them and the Codex git-worker misbehaves).

{
  lib,
  pkgs,
  ...
}:

let
  # Debian-style SONAME + CURL_GNUTLS_3; stock openssl curl only ships libcurl.so.4.
  # HTTP/3 must stay off: ngtcp2's gnutls crypto header is not wired for this combo.
  curlGnutls = pkgs.curl.override {
    gnutlsSupport = true;
    opensslSupport = false;
    http3Support = false;
  };
in
{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Extra libs beyond nixpkgs' nix-ld defaults (zlib, curl/openssl, libstdc++, …)
      # for Codex primary-runtime natives (git helpers, poppler, fonts, …).
      curlGnutls
      nss
      nspr
      fontconfig
      freetype
      lcms2
      pixman
      expat
      libxcrypt
    ];
  };
}
