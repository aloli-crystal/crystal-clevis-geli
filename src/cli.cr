require "option_parser"
require "file_utils"
require "./crystal_clevis_geli"

# Convention (Aloli CLI UX): every long flag has a short equivalent;
# every subcommand has a short alias.
module CrystalClevisGeli::CLI
  extend self

  DEFAULT_KEY_STORE = "/var/db/crystal-clevis-geli"

  def run(argv : Array(String)) : Int32
    if argv.empty?
      print_global_help(STDERR)
      return 64
    end

    case argv.first
    when "bind", "b"
      bind(argv[1..-1])
    when "unlock", "u"
      unlock(argv[1..-1])
    when "version", "v", "--version", "-V"
      puts "crystal-clevis-geli #{CrystalClevisGeli::VERSION}"
      0
    when "help", "h", "--help", "-h"
      print_global_help(STDOUT)
      0
    else
      STDERR.puts "unknown subcommand: #{argv.first}"
      print_global_help(STDERR)
      64
    end
  end

  def bind(argv : Array(String)) : Int32
    device = ""
    tang_url = ""
    key_store = DEFAULT_KEY_STORE
    do_init = false

    OptionParser.parse(argv.dup) do |parser|
      parser.banner = "Usage: crystal-clevis-geli bind -d DEVICE -t TANG_URL [options]"
      parser.on("-d PATH", "--device=PATH", "GELI device (e.g. /dev/ada0p4)") { |v| device = v }
      parser.on("-t URL", "--tang=URL", "Tang server URL") { |v| tang_url = v }
      parser.on("-s PATH", "--key-store=PATH", "JWE storage directory (default: #{DEFAULT_KEY_STORE})") { |v| key_store = v }
      parser.on("-i", "--init", "Run `geli init` instead of `setkey`") { do_init = true }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
      parser.invalid_option do |flag|
        STDERR.puts "invalid option: #{flag}"
        STDERR.puts parser
        exit 64
      end
    end

    if device.empty? || tang_url.empty?
      STDERR.puts "missing -d/--device or -t/--tang"
      return 64
    end

    keyfile = CrystalClevisGeli::Geli.random_keyfile
    if do_init
      CrystalClevisGeli::Geli.init(device, keyfile)
    else
      CrystalClevisGeli::Geli.setkey(device, keyfile)
    end

    tang = CrystalClevisGeli::TangClient.new(tang_url)
    jwe = tang.bind(keyfile)

    Dir.mkdir_p(key_store)
    jwe_path = jwe_path_for(key_store, device)
    File.write(jwe_path, jwe)
    File.chmod(jwe_path, 0o600)

    puts "bound #{device} -> #{jwe_path}"
    0
  rescue ex
    STDERR.puts "bind failed: #{ex.message}"
    1
  end

  def unlock(argv : Array(String)) : Int32
    device = ""
    key_store = DEFAULT_KEY_STORE

    OptionParser.parse(argv.dup) do |parser|
      parser.banner = "Usage: crystal-clevis-geli unlock -d DEVICE [options]"
      parser.on("-d PATH", "--device=PATH", "GELI device to attach") { |v| device = v }
      parser.on("-s PATH", "--key-store=PATH", "JWE storage directory (default: #{DEFAULT_KEY_STORE})") { |v| key_store = v }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
      parser.invalid_option do |flag|
        STDERR.puts "invalid option: #{flag}"
        STDERR.puts parser
        exit 64
      end
    end

    if device.empty?
      STDERR.puts "missing -d/--device"
      return 64
    end

    jwe_path = jwe_path_for(key_store, device)
    unless File.exists?(jwe_path)
      STDERR.puts "no JWE found at #{jwe_path}; was this device ever bound?"
      return 1
    end
    jwe = File.read(jwe_path)

    # The JWE carries `clevis.tang.url`, so we don't need a CLI flag.
    header_b64 = jwe.split('.').first
    header = Hash(String, JSON::Any).from_json(String.new(CrystalJose::Utils.base64url_decode(header_b64)))
    tang_url = header["clevis"].as_h["tang"].as_h["url"].as_s

    tang = CrystalClevisGeli::TangClient.new(tang_url)
    keyfile = tang.recover(jwe)
    CrystalClevisGeli::Geli.attach(device, keyfile)

    puts "attached #{device}"
    0
  rescue ex
    STDERR.puts "unlock failed: #{ex.message}"
    1
  end

  private def jwe_path_for(key_store : String, device : String) : String
    safe = device.gsub('/', '_').sub(/^_/, "")
    File.join(key_store, "#{safe}.jwe")
  end

  private def print_global_help(io : IO)
    io.puts "Usage: crystal-clevis-geli SUBCOMMAND [options]"
    io.puts
    io.puts "Subcommands:"
    io.puts "  bind, b      Bind a GELI device to a Tang server"
    io.puts "  unlock, u    Attach a previously bound GELI device"
    io.puts "  version, v   Print version"
    io.puts "  help, h      Show this help"
    io.puts
    io.puts "Run `crystal-clevis-geli SUBCOMMAND -h` for subcommand-specific options."
  end
end

exit CrystalClevisGeli::CLI.run(ARGV) if PROGRAM_NAME.includes?("crystal-clevis-geli") || PROGRAM_NAME.includes?("cli")
