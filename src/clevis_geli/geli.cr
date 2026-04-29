require "process"
require "file_utils"
require "random/secure"

module ClevisGeli
  # Thin wrapper around geli(8) on FreeBSD.
  #
  # All key material passes through a temporary file with mode 600
  # in `/var/run` (tmpfs by default on FreeBSD). The file is removed
  # immediately after geli has consumed it.
  module Geli
    extend self

    class Error < Exception
    end

    # Returns the path to the geli binary. Override `GELI_BIN` env
    # variable for testing.
    def binary : String
      ENV["GELI_BIN"]? || "/sbin/geli"
    end

    def keyfile_dir : String
      ENV["CRYSTAL_CLEVIS_GELI_TMPDIR"]? || "/var/run"
    end

    # Initialize a new GELI provider on `device` keyed with `keyfile_bytes`.
    # `-P` disables the interactive passphrase prompt: the keyfile is the
    # only key. Extra options can be passed (e.g. ["-l", "256"] for AES-XTS-256).
    def init(device : String, keyfile_bytes : Bytes, options : Array(String) = [] of String)
      with_keyfile(keyfile_bytes) do |path|
        run!([binary, "init", "-P", "-K", path] + options + [device])
      end
    end

    # Attach (open) an existing GELI provider with the given key.
    # `-p` disables the interactive passphrase prompt for keyfile-only
    # providers (those initialized with `init -P`).
    def attach(device : String, keyfile_bytes : Bytes)
      with_keyfile(keyfile_bytes) do |path|
        run!([binary, "attach", "-p", "-k", path, device])
      end
    end

    # Detach (close) a previously attached GELI device. Pass the
    # provider name (the underlying device, geli will resolve `.eli`).
    def detach(device : String)
      run!([binary, "detach", device])
    end

    # Replace the keyfile in slot 0 of the provider. Useful when
    # rotating keys via crystal-clevis-geli `bind`.
    # `-P` makes the new key keyfile-only.
    def setkey(device : String, keyfile_bytes : Bytes, slot : Int32 = 0)
      with_keyfile(keyfile_bytes) do |path|
        run!([binary, "setkey", "-P", "-n", slot.to_s, "-K", path, device])
      end
    end

    # Generate a fresh random GELI keyfile (default size: 64 bytes).
    def random_keyfile(size : Int32 = 64) : Bytes
      Random::Secure.random_bytes(size)
    end

    private def with_keyfile(bytes : Bytes, &)
      Dir.mkdir_p(keyfile_dir)
      path = File.join(keyfile_dir, "ccg-#{Random::Secure.hex(8)}.key")
      File.open(path, "w") do |f|
        f.write(bytes)
      end
      File.chmod(path, 0o600)
      begin
        yield path
      ensure
        # Best-effort overwrite then unlink. GELI has already consumed
        # the file; we just don't want it lingering on disk.
        begin
          File.open(path, "w") { |f| f.write(Bytes.new(bytes.size, 0_u8)) }
        rescue
          # ignore
        end
        File.delete(path) if File.exists?(path)
      end
    end

    private def run!(cmd : Array(String))
      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Process.run(cmd[0], cmd[1..-1], output: stdout, error: stderr)
      unless status.success?
        raise Error.new("#{cmd.join(' ')} failed (exit #{status.exit_code}): #{stderr.to_s.strip}")
      end
    end
  end
end
