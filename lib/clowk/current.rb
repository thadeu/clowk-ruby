# frozen_string_literal: true

module Clowk
  class Current
    attr_reader :attributes

    def initialize(attributes = {})
      @attributes = attributes.to_h.deep_symbolize_keys
    end

    def id
      attributes[:sub] || attributes[:id]
    end

    def email
      attributes[:email]
    end

    def name
      attributes[:name]
    end

    def avatar_url
      attributes[:avatar_url]
    end

    def provider
      attributes[:provider]
    end

    def instance_id
      attributes[:instance_id]
    end

    def app_id
      attributes[:app_id]
    end

    def [](key)
      attributes[key.to_sym]
    end

    def to_h
      attributes.merge(id: id)
    end
  end
end