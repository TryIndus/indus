# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "yaml"

class Phase4RenderTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  ENVIRONMENTS = %w[development staging production].freeze
  DEPLOYMENTS = %w[
    platform-api sidekiq market-data platform-outbox reports-consumer research-worker
  ].freeze
  SERVICE_ACCOUNTS = (DEPLOYMENTS + %w[database-migrator web-publisher]).sort.freeze

  ENVIRONMENTS.each do |environment|
    define_method("test_#{environment}_pins_and_hardens_every_workload") do
      workloads(environment).each do |workload|
        name = workload.dig("metadata", "name")
        pod = workload.dig("spec", "template", "spec")
        pod_security = pod.fetch("securityContext")

        assert_equal true, pod_security["runAsNonRoot"], name
        assert_equal "RuntimeDefault", pod_security.dig("seccompProfile", "type"), name
        refute_equal "default", pod.fetch("serviceAccountName"), name

        pod.fetch("containers").each do |container|
          security = container.fetch("securityContext")
          assert_equal false, security["allowPrivilegeEscalation"], name
          assert_equal true, security["readOnlyRootFilesystem"], name
          assert_equal true, security["runAsNonRoot"], name
          assert_equal [ "ALL" ], security.dig("capabilities", "drop"), name
          assert_match(/@sha256:[0-9a-f]{64}\z/, container.fetch("image"), name)
          assert container.dig("resources", "requests"), "#{name} has no resource requests"
          assert container.dig("resources", "limits"), "#{name} has no resource limits"
        end
      end
    end

    define_method("test_#{environment}_uses_only_explicit_irsa_service_accounts") do
      accounts = documents(environment).select { |document| document["kind"] == "ServiceAccount" }

      assert_equal SERVICE_ACCOUNTS, accounts.map { |account| account.dig("metadata", "name") }.sort
      accounts.each do |account|
        assert_equal true, account["automountServiceAccountToken"]
        assert_match(
          /\Aarn:aws[a-z-]*:iam::[0-9]{12}:role\//,
          account.dig("metadata", "annotations", "eks.amazonaws.com/role-arn")
        )
      end
    end

    define_method("test_#{environment}_projects_only_allowlisted_runtime_secret_keys") do
      expected = {
        "platform-api" => %w[DATABASE_URL GEMINI_API_KEY SECRET_KEY_BASE],
        "market-data" => %w[ALPACA_API_KEY ALPACA_SECRET_KEY DATABASE_URL],
        "research-worker" => %w[DATABASE_URL GEMINI_API_KEY TEMPORAL_API_KEY],
        "database-migration" => %w[DATABASE_URL]
      }
      providers = documents(environment).select { |document| document["kind"] == "SecretProviderClass" }

      assert_equal expected.keys.sort, providers.map { |provider| provider.dig("metadata", "name") }.sort
      providers.each do |provider|
        name = provider.dig("metadata", "name")
        keys = provider.dig("spec", "secretObjects", 0, "data").map { |entry| entry.fetch("key") }.sort
        assert_equal expected.fetch(name), keys
        refute_includes keys, "REDIS_URL"
      end
    end

    define_method("test_#{environment}_scopes_redis_iam_to_api_and_sidekiq") do
      deployment_env = deployments(environment).to_h do |deployment|
        env = deployment.dig("spec", "template", "spec", "containers", 0).fetch("env", [])
        [ deployment.dig("metadata", "name"), env.to_h { |entry| [ entry["name"], entry["value"] ] } ]
      end
      required = %w[REDIS_AUTH_MODE REDIS_ENDPOINT REDIS_PORT REDIS_IAM_CACHE_NAME REDIS_IAM_USER]

      %w[platform-api sidekiq].each do |name|
        assert_empty required - deployment_env.fetch(name).keys
        assert_equal "iam", deployment_env.fetch(name).fetch("REDIS_AUTH_MODE")
      end
      (DEPLOYMENTS - %w[platform-api sidekiq]).each do |name|
        assert_empty required & deployment_env.fetch(name).keys
      end
    end

    define_method("test_#{environment}_separates_platform_and_market_migrations") do
      migrations = documents(environment).select do |document|
        document["kind"] == "Job" && document.dig("metadata", "name").include?("database-migrate")
      end

      assert_equal 2, migrations.length
      options = migrations.to_h do |job|
        pod = job.dig("spec", "template", "spec")
        env = pod.dig("containers", 0, "env")
        pgoptions = env.find { |entry| entry["name"] == "PGOPTIONS" }.fetch("value")
        database_secret = env.find { |entry| entry["name"] == "DATABASE_URL" }
        assert_equal "database-migrator", pod["serviceAccountName"]
        assert_equal "database-migration-runtime", database_secret.dig("valueFrom", "secretKeyRef", "name")
        [ job.dig("metadata", "labels", "app.kubernetes.io/name"), pgoptions ]
      end

      assert_equal "-c role=indus_platform_owner -c search_path=public,pg_catalog", options.fetch("database-migrate")
      assert_equal "-c role=indus_market_owner -c search_path=market_data,pg_catalog", options.fetch("market-database-migrate")
    end

    define_method("test_#{environment}_defaults_to_deny_and_opens_only_named_network_paths") do
      policies = documents(environment).select { |document| document["kind"] == "NetworkPolicy" }
      names = policies.map { |policy| policy.dig("metadata", "name") }

      assert_equal %w[
        allow-dns allow-managed-services-and-https default-deny edge-to-market-data edge-to-platform-api
      ], names.sort
      default_deny = policies.find { |policy| policy.dig("metadata", "name") == "default-deny" }
      assert_equal({}, default_deny.dig("spec", "podSelector"))
      assert_equal %w[Ingress Egress], default_deny.dig("spec", "policyTypes")
    end

    define_method("test_#{environment}_renders_disruption_and_scaling_controls") do
      disruption_budgets = documents(environment).select { |document| document["kind"] == "PodDisruptionBudget" }
      autoscalers = documents(environment).select { |document| document["kind"] == "HorizontalPodAutoscaler" }

      assert_equal DEPLOYMENTS.sort, disruption_budgets.map { |pdb| pdb.dig("metadata", "name") }.sort
      assert_equal %w[market-data platform-api sidekiq], autoscalers.map { |hpa| hpa.dig("metadata", "name") }.sort
      disruption_budgets.each { |pdb| assert_equal 1, pdb.dig("spec", "maxUnavailable") }
      autoscalers.each do |hpa|
        assert_operator hpa.dig("spec", "minReplicas"), :>=, 2
        assert_operator hpa.dig("spec", "maxReplicas"), :>, hpa.dig("spec", "minReplicas")
      end
    end
  end

  class << self
    def documents_for(environment)
      @documents ||= {}
      @documents[environment] ||= begin
        values = File.join(ROOT, "infra", "gitops", "environments", environment, "values.yaml")
        chart = File.join(ROOT, "infra", "helm", "indus-platform")
        stdout, stderr, status = Open3.capture3(
          "helm", "template", "indus", chart, "--namespace", "indus", "--values", values
        )
        raise "Helm render failed for #{environment}: #{stderr}" unless status.success?

        YAML.load_stream(stdout).compact
      end
    end
  end

  private

  def documents(environment)
    self.class.documents_for(environment)
  end

  def deployments(environment)
    documents(environment).select { |document| document["kind"] == "Deployment" }
  end

  def workloads(environment)
    documents(environment).select { |document| %w[Deployment Job].include?(document["kind"]) }
  end
end
