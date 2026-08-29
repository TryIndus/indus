# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

class UpdateGitopsImagesTest < Minitest::Test
  SOURCE_SCRIPT = File.expand_path("../update-gitops-images.rb", __dir__)
  RELEASE_ID = "a" * 40
  DIGEST_A = "1" * 64
  DIGEST_B = "2" * 64
  DIGEST_C = "3" * 64
  IMAGES = {
    "platformApi" => "111111111111.dkr.ecr.ca-central-1.amazonaws.com/indus/platform-api@sha256:#{DIGEST_A}",
    "marketData" => "111111111111.dkr.ecr.ca-central-1.amazonaws.com/indus/market-data@sha256:#{DIGEST_B}",
    "researchWorker" => "111111111111.dkr.ecr.ca-central-1.amazonaws.com/indus/platform-api@sha256:#{DIGEST_A}",
    "web" => "111111111111.dkr.ecr.ca-central-1.amazonaws.com/indus/web@sha256:#{DIGEST_C}"
  }.freeze

  def test_development_release_updates_only_immutable_images_and_release_id
    in_fixture do |root, script|
      _stdout, stderr, status = run_update(script, "development")

      assert status.success?, stderr
      values = load_values(root, "development")
      assert_equal IMAGES, values.fetch("images")
      assert_equal RELEASE_ID, values.dig("webPublisher", "releaseId")
      assert_equal "preserved", values.fetch("unrelated")
    end
  end

  def test_staging_requires_the_exact_development_release
    in_fixture do |root, script|
      _stdout, first_stderr, first_status = run_update(script, "staging")
      refute first_status.success?, first_stderr
      assert_includes first_stderr, "exact image set"

      write_values(root, "development", images: IMAGES, release_id: RELEASE_ID)
      _stdout, second_stderr, second_status = run_update(script, "staging")

      assert second_status.success?, second_stderr
      assert_equal IMAGES, load_values(root, "staging").fetch("images")
    end
  end

  def test_production_requires_the_exact_staging_release_id
    in_fixture do |root, script|
      write_values(root, "staging", images: IMAGES, release_id: "b" * 40)
      _stdout, stderr, status = run_update(script, "production")

      refute status.success?
      assert_includes stderr, "exact release"
    end
  end

  def test_mutable_or_wrong_repository_images_are_rejected
    invalid_sets = [
      image_environment.merge("PLATFORM_API_IMAGE" => "repo/indus/platform-api:latest"),
      image_environment.merge(
        "MARKET_DATA_IMAGE" => "111111111111.dkr.ecr.ca-central-1.amazonaws.com/other/market-data@sha256:#{DIGEST_B}"
      )
    ]

    invalid_sets.each do |environment|
      in_fixture do |_root, script|
        _stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, script, "development")

        refute status.success?, "accepted #{environment.inspect}"
        assert_match(/immutable sha256 digest|unexpected repository/, stderr)
      end
    end
  end

  def test_invalid_environment_and_release_identifier_are_rejected
    in_fixture do |_root, script|
      _stdout, environment_stderr, environment_status = run_update(script, "preview")
      refute environment_status.success?
      assert_includes environment_stderr, "unsupported environment"

      invalid_release = image_environment.merge("RELEASE_ID" => "main")
      _stdout, release_stderr, release_status = Open3.capture3(
        invalid_release, RbConfig.ruby, script, "development"
      )
      refute release_status.success?
      assert_includes release_stderr, "full lowercase Git SHA"
    end
  end

  private

  def in_fixture
    Dir.mktmpdir("indus-image-promotion") do |root|
      script_dir = File.join(root, "scripts")
      FileUtils.mkdir_p(script_dir)
      FileUtils.cp(SOURCE_SCRIPT, script_dir)
      %w[development staging production].each do |environment|
        write_values(root, environment, images: placeholder_images, release_id: "0" * 40)
      end
      yield root, File.join(script_dir, "update-gitops-images.rb")
    end
  end

  def run_update(script, environment)
    Open3.capture3(image_environment, RbConfig.ruby, script, environment)
  end

  def image_environment
    {
      "RELEASE_ID" => RELEASE_ID,
      "PLATFORM_API_IMAGE" => IMAGES.fetch("platformApi"),
      "MARKET_DATA_IMAGE" => IMAGES.fetch("marketData"),
      "WEB_IMAGE" => IMAGES.fetch("web")
    }
  end

  def placeholder_images
    IMAGES.transform_values { |image| image.sub(/sha256:[0-9a-f]{64}\z/, "sha256:#{"0" * 64}") }
  end

  def values_path(root, environment)
    File.join(root, "infra", "gitops", "environments", environment, "values.yaml")
  end

  def write_values(root, environment, images:, release_id:)
    path = values_path(root, environment)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(
      path,
      YAML.dump(
        "images" => images,
        "webPublisher" => { "releaseId" => release_id },
        "unrelated" => "preserved"
      )
    )
  end

  def load_values(root, environment)
    YAML.safe_load(File.read(values_path(root, environment)), permitted_classes: [], permitted_symbols: [], aliases: false)
  end
end
