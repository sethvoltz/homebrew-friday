# typed: true
# frozen_string_literal: true

# Friday — local-first headless agent daemon + SvelteKit dashboard.
#
# Production supervision via launchd (this formula's `service do` block
# generates `homebrew.mxcl.friday.plist`). The plist runs
# `friday-supervisor`, which forks daemon + dashboard + zero-cache as
# children with proper process-group cascade-stop semantics. See
# `docs/decisions.md` ADR-028 in the source repo for the full design.
#
# Source install (not binary tarball) — first install builds Friday's
# TypeScript + SvelteKit on the user's machine via `pnpm -r build`
# (~5-10 minutes). Subsequent `brew upgrade friday` runs pull the
# latest commit on `main` and rebuild.
class Friday < Formula
  desc "Local-first headless agent daemon + SvelteKit dashboard"
  homepage "https://github.com/sethvoltz/friday"
  url "https://github.com/sethvoltz/friday.git", branch: "main"
  version "0.0.1"
  license "MIT"
  head "https://github.com/sethvoltz/friday.git", branch: "main"

  depends_on "node"
  depends_on "pnpm"
  depends_on "postgresql@18"

  # Optional but recommended: Cloudflare Tunnel for public reachability.
  # cloudflared runs as its own brew service
  # (`brew services start cloudflared`); Friday's supervisor doesn't
  # manage its lifecycle. The formula lives in homebrew/core, no tap
  # required.
  depends_on "cloudflared" => :recommended

  def install
    # Build Friday in the source tree, then install the whole repo to
    # libexec/ so the supervisor's path-resolution (which walks up to
    # the repo root via pnpm-workspace.yaml) works identically to the
    # dev checkout.
    #
    # We install with devDependencies because the build step needs
    # `tsc` (TypeScript compiler is a devDep at the root) and
    # `vite-build` (devDep at the dashboard). After `pnpm -r build`
    # we could `pnpm prune --prod` to shrink, but the savings are
    # marginal (~tens of MB) compared to the libexec total, and
    # pruning then re-installing on `brew upgrade` adds another
    # several minutes. Skip the prune for v1.
    system "pnpm", "install", "--frozen-lockfile"
    system "pnpm", "-r", "build"

    libexec.install Dir["*"]

    # bin wrappers. `write_env_script` generates a shell shim that
    # exec's the target with the supplied env. We extend PATH so the
    # supervisor (and its children) can find `pnpm`, `node`,
    # `postgresql`, and `cloudflared` regardless of launchd's
    # minimal `PATH`.
    env_path = "#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
    (bin/"friday").write_env_script libexec/"bin/friday", PATH: env_path
    (bin/"friday-supervisor").write_env_script libexec/"bin/friday-supervisor",
                                                PATH: env_path
  end

  # `service do` is brew's DSL for launchd plist generation. The
  # resulting plist lands at
  # `~/Library/LaunchAgents/homebrew.mxcl.friday.plist` after
  # `brew services start friday`.
  #
  # `keep_alive: { successful_exit: false }` — launchd respawns the
  # supervisor on any non-zero exit. Clean exits (the supervisor's own
  # cascade-stop path during `brew services stop friday`) don't
  # trigger a respawn.
  #
  # `run_at_load: true` — Friday comes back automatically after Mac
  # reboot / login. This is the FRI-88 acceptance criterion #3.
  service do
    run [opt_bin/"friday-supervisor"]
    keep_alive successful_exit: false
    run_at_load true
    log_path var/"log/friday.log"
    error_log_path var/"log/friday.err.log"
    environment_variables PATH: std_service_path_env
    working_dir HOMEBREW_PREFIX
  end

  def caveats
    <<~EOS
      Friday is now installed. To bring up the stack:

        brew services start friday

      First run: `friday setup` to provision the Postgres database +
      primary account (idempotent — re-run anytime).

      Cascade-stop is verified: `brew services stop friday` leaves zero
      zero-cache, daemon, or dashboard descendants alive within 5s.
      Confirm with: `pgrep -f "rocicorp.+zero"` returning empty.

      For public reachability via Cloudflare Tunnel, install cloudflared
      and run it as its own brew service:

        brew install cloudflared
        friday setup --cloudflare           # paste tunnel token
        brew services start cloudflared

      See `docs/setup.md` in the source repo for the full walkthrough.
    EOS
  end

  test do
    # `friday --version` should print the formula's version. citty (the
    # CLI framework Friday uses) emits to stdout when `--version` is
    # passed.
    assert_match version.to_s, shell_output("#{bin}/friday --version")
  end
end
