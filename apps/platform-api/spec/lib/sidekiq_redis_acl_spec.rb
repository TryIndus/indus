require "spec_helper"

RSpec.describe "the production Sidekiq Redis ACL" do
  it "allows the pinned Sidekiq command contract without broad command categories" do
    root = File.expand_path("../../../..", __dir__)
    terraform = File.read(File.join(root, "infra/terraform/modules/environment/data.tf"))
    fixture = File.readlines(File.join(__dir__, "../fixtures/files/sidekiq_redis_commands.txt"), chomp: true)
    allowed = terraform.scan(/"\+([^" ]+)"/).flatten

    expect(allowed).to include(*fixture)
    expect(allowed.grep(/\A@/)).to be_empty
    expect(allowed).not_to include("acl", "config", "flushall", "flushdb", "module", "shutdown")
  end
end
