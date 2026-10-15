# nix-ld: run unpatched FHS/ELF binaries (dynamic linker + common libs).
#
# Needed so ChatGPT Desktop / Codex can execute its downloaded primary-runtime
# tools — especially bundled `git` under ~/.cache/codex-runtimes/.../native/git
# (otherwise stub-ld refuses them and the Codex git-worker misbehaves).

{ pkgs, ... }:

let
  # Codex's bundled git-http-* needs SONAME libcurl-gnutls.so.4 with version
  # CURL_GNUTLS_3. Current nixpkgs curl only tags CURL_GNUTLS_4, so retag the
  # version script. HTTP/3 stays off (ngtcp2 gnutls crypto not wired here).
  curlGnutls3 =
    (pkgs.curl.override {
      gnutlsSupport = true;
      opensslSupport = false;
      http3Support = false;
    }).overrideAttrs
      (old: {
        pname = "curl-gnutls3";
        postPatch = (old.postPatch or "") + ''
          substituteInPlace lib/libcurl.vers.in \
            --replace-fail \
              "CURL_@CURL_LIBCURL_VERSIONED_SYMBOLS_PREFIX@@CURL_LIBCURL_VERSIONED_SYMBOLS_SONAME@" \
              "CURL_GNUTLS_3"
        '';
      });
in
{
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # Beyond nixpkgs nix-ld defaults (zlib, openssl curl, libstdc++, …):
      # Codex primary-runtime natives (git helpers, poppler/fonts, …).
      curlGnutls3
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
