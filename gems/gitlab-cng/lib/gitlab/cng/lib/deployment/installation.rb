# frozen_string_literal: true

require "socket"
require "yaml"
require "active_support/core_ext/hash"

module Gitlab
  module Cng
    module Deployment
      # Class handling all the pre and post deployment setup steps and gitlab helm chart installation
      #
      class Installation
        include Helpers::Output
        include Helpers::Shell

        LICENSE_SECRET = "gitlab-license"

        def initialize(name, configuration:, namespace:, ci:, gitlab_domain: nil, set: [])
          @name = name
          @configuration = configuration
          @namespace = namespace
          @ci = ci
          @gitlab_domain = gitlab_domain
          @set = set
        end

        # Perform deployment with all the additional setup
        #
        # @return [void]
        def create
          log("Creating CNG deployment '#{name}' using '#{configuration}' configuration", :info, bright: true)
          run_pre_deploy_setup
          run_deploy
          run_post_deploy_setup
        rescue Helpers::Shell::CommandFailure
          exit(1)
        end

        private

        attr_reader :name, :configuration, :namespace, :ci, :set
        alias_method :cli_values, :set

        # Kubectl client instance
        #
        # @return [Kubectl::Client]
        def kubeclient
          @kubeclient ||= Kubectl::Client.new(namespace)
        end

        # Gitlab app domain
        #
        # @return [String]
        def gitlab_domain
          @gitlab_domain ||= "#{Socket.ip_address_list.detect(&:ipv4_private?).ip_address}.nip.io"
        end

        # Configuration class instance
        #
        # @return [Configuration::Base]
        def config_instance
          @config_instance ||= Configurations.const_get(configuration.capitalize, false).new(
            namespace,
            kubeclient,
            ci,
            gitlab_domain
          )
        end

        # Gitlab license
        #
        # @return [String]
        def license
          @license ||= ENV["QA_EE_LICENSE"] || ENV["EE_LICENSE"]
        end

        # Helm values for license secret
        #
        # @return [Hash]
        def license_values
          return {} unless license

          {
            global: {
              extraEnv: {
                GITLAB_LICENSE_MODE: "test",
                CUSTOMER_PORTAL_URL: "https://customers.staging.gitlab.com"
              }
            },
            gitlab: {
              license: {
                secret: LICENSE_SECRET
              }
            }
          }
        end

        # Execute pre-deployment setup
        #
        # @return [void]
        def run_pre_deploy_setup
          Helpers::Spinner.spin("running pre-deployment setup") do
            add_helm_chart
            update_helm_chart_repo
            create_namespace
            create_license

            config_instance.run_pre_deployment_setup
          end
        end

        # Run helm deployment
        #
        # @return [void]
        def run_deploy
          cmd = [
            "upgrade",
            "--install", name, "gitlab/gitlab",
            "--namespace", namespace,
            "--timeout", "5m",
            "--wait"
          ]
          cmd.push(*DefaultValues.component_ci_versions.flat_map { |k, v| ["--set", "gitlab.#{k}=#{v}"] }) if ci
          cmd.push(*cli_values.flat_map { |v| ["--set", v] })
          cmd.push("--values", "-")
          values = DefaultValues.common_values(gitlab_domain)
            .deep_merge(license_values)
            .deep_merge(config_instance.values)
            .deep_stringify_keys

          Helpers::Spinner.spin("running helm deployment") { puts run_helm_cmd(cmd, values.to_yaml) }
          log("Deployment successfull and app is available via: #{config_instance.gitlab_url}", :success, bright: true)
        end

        # Execute post-deployment setup
        #
        # @return [void]
        def run_post_deploy_setup
          Helpers::Spinner.spin("running post-deployment setup") { config_instance.run_post_deployment_setup }
        end

        # Add helm chart repo
        #
        # @return [void]
        def add_helm_chart
          log("Adding gitlab helm chart", :info)
          puts run_helm_cmd(%w[repo add gitlab https://charts.gitlab.io])
        rescue Helpers::Shell::CommandFailure => e
          return log("helm repo already exists, skipping", :warn) if e.message.include?("already exists")

          raise(e)
        end

        # Update helm chart repo
        #
        # @return [void]
        def update_helm_chart_repo
          log("Updating gitlab helm chart repo", :info)
          puts run_helm_cmd(%w[repo update gitlab])
        end

        # Create namespace
        #
        # @return [void]
        def create_namespace
          log("Creating namespace '#{namespace}'", :info)
          puts kubeclient.create_namespace
        rescue StandardError => e
          return log("namespace already exists, skipping", :warn) if e.message.include?("already exists")

          raise(e)
        end

        # Create gitlab license
        #
        # @return [void]
        def create_license
          log("Creating gitlab license secret", :info)
          return log("`QA_EE_LICENSE|EE_LICENSE` variable is not set, skipping", :warn) unless license

          secret = Kubectl::Resources::Secret.new(LICENSE_SECRET, "license", license)
          puts mask_secrets(kubeclient.create_resource(secret), [license, Base64.encode64(license)])
        end

        # Run helm command
        #
        # @param [Array] cmd
        # @return [String]
        def run_helm_cmd(cmd, stdin = nil)
          execute_shell(["helm", *cmd], stdin_data: stdin)
        end
      end
    end
  end
end
