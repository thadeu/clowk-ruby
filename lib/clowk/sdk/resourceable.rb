# frozen_string_literal: true

module Clowk
  module Client
    class SDK
      module Resourceable
        def self.included(base)
          base.include UsersMethods
          base.include InstancesMethods
          base.include WebhooksMethods
          base.include SessionsMethods
        end

        module UsersMethods
          def users
            @users ||= UsersResource.new(self)
          end

          def user(id)
            users.find(id)
          end
        end

        module InstancesMethods
          def instances
            @instances ||= InstancesResource.new(self)
          end
        end

        module WebhooksMethods
          def webhooks
            @webhooks ||= WebhooksResource.new(self)
          end
        end

        module SessionsMethods
          def sessions
            @sessions ||= SessionsResource.new(self)
          end
        end

        class BaseResource
          def initialize(sdk)
            @sdk = sdk
          end

          private

          attr_reader :sdk
        end

        class UsersResource < BaseResource
          def find(id)
            sdk.get("users/#{id}")
          end
        end

        class InstancesResource < BaseResource
          def find_by_key(key: nil, path: nil)
            sdk.get(path || "i/#{key}")
          end
        end

        class WebhooksResource < BaseResource
        end

        class SessionsResource < BaseResource
        end
      end
    end
  end
end