require "./spec_helper"
require "file_utils"

# End-to-end CLI test: write a fake `geli` binary that records its
# arguments, point ClevisGeli::Geli at it, and run the
# bind/unlock helpers directly (skipping the network by using
# MockTangClient).
describe "CLI e2e" do
  it "binds then unlocks, exercising both Tang and GELI shell-outs" do
    Dir.mkdir_p("/tmp/ccg-e2e")
    fake_geli = "/tmp/ccg-e2e/geli"
    File.write(fake_geli, <<-SH)
    #!/bin/sh
    # Fake geli — just exit 0; real geli would consume the keyfile.
    echo "fake geli called: $@" >> /tmp/ccg-e2e/calls.log
    exit 0
    SH
    File.chmod(fake_geli, 0o755)
    File.write("/tmp/ccg-e2e/calls.log", "")

    ENV["GELI_BIN"] = fake_geli
    ENV["CRYSTAL_CLEVIS_GELI_TMPDIR"] = "/tmp/ccg-e2e"
    key_store = "/tmp/ccg-e2e/store"
    Dir.mkdir_p(key_store)

    # We bypass the network entirely by injecting a MockTangClient.
    tang = MockTangClient.new("http://mock-tang.example.com")
    keyfile = ClevisGeli::Geli.random_keyfile
    ClevisGeli::Geli.setkey("/dev/fake0", keyfile)
    jwe = tang.bind(keyfile)

    jwe_path = File.join(key_store, "dev_fake0.jwe")
    File.write(jwe_path, jwe)

    # Now reverse: read the JWE, recover via the same mock, attach.
    read_back = File.read(jwe_path)
    recovered_keyfile = tang.recover(read_back)
    recovered_keyfile.should eq(keyfile)
    ClevisGeli::Geli.attach("/dev/fake0", recovered_keyfile)

    log = File.read("/tmp/ccg-e2e/calls.log")
    log.should contain("setkey")
    log.should contain("attach")
  ensure
    FileUtils.rm_rf("/tmp/ccg-e2e")
    ENV.delete("GELI_BIN")
    ENV.delete("CRYSTAL_CLEVIS_GELI_TMPDIR")
  end
end
