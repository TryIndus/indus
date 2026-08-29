# frozen_string_literal: true

require "minitest/autorun"

class Phase4WorkflowTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  RELEASE = File.read(File.join(ROOT, ".github", "workflows", "release-images.yml"))
  PROMOTE = File.read(File.join(ROOT, ".github", "workflows", "promote-images.yml"))

  def test_every_third_party_action_is_pinned_to_a_commit
    [ RELEASE, PROMOTE ].each do |workflow|
      uses = workflow.lines.map { |line| line[/^\s*uses: \S+@([^\s#]+)/, 1] }.compact

      refute_empty uses
      uses.each { |reference| assert_match(/\A[0-9a-f]{40}\z/, reference) }
    end
  end

  def test_release_uses_keyless_identity_and_immutable_evidence
    assert_includes RELEASE, "id-token: write"
    assert_includes RELEASE, "--provenance mode=max"
    assert_includes RELEASE, "containerimage.digest"
    assert_includes RELEASE, "anchore/sbom-action@"
    assert_includes RELEASE, "severity: HIGH,CRITICAL"
    assert_includes RELEASE, "cosign sign --yes"
    assert_includes RELEASE, "cosign attest --yes --type spdxjson"
    assert_includes RELEASE, "retention-days: 90"
    refute_includes RELEASE, "pull_request_target"
  end

  def test_promotion_verifies_origin_digest_and_attestation_before_editing_gitops
    verification_offset = PROMOTE.index("cosign verify --certificate-identity")
    attestation_offset = PROMOTE.index("cosign verify-attestation --type spdxjson")
    update_offset = PROMOTE.index("ruby scripts/update-gitops-images.rb")

    assert verification_offset
    assert attestation_offset
    assert update_offset
    assert_operator verification_offset, :<, update_offset
    assert_operator attestation_offset, :<, update_offset
    assert_includes PROMOTE, "release-images.yml@refs/heads/main"
    assert_includes PROMOTE, "@sha256:????????????????????????????????????????????????????????????????"
  end

  def test_promotion_is_manual_environment_gated_and_reviewed
    assert_includes PROMOTE, "workflow_dispatch:"
    assert_includes PROMOTE, 'environment: ${{ inputs.environment }}'
    assert_includes PROMOTE, "cancel-in-progress: false"
    assert_includes PROMOTE, "gh pr create --base main"
    assert_includes PROMOTE, "git commit --no-gpg-sign"
    refute_match(/^\s+aws .*terraform apply/, PROMOTE)
    refute_includes PROMOTE, "pull_request_target"
  end
end
