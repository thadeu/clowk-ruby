# frozen_string_literal: true

require_relative 'lib/clowk/version'

Gem::Specification.new do |spec|
  spec.name = 'clowk'
  spec.version = Clowk::VERSION
  spec.authors = ['Clowk']
  spec.email = ['support@clowk.in']

  spec.summary = 'Rails SDK for Clowk authentication'
  spec.description = 'Clowk Authentication, JWT verification, and future API access'
  spec.homepage = 'https://clowk.in'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'
  spec.metadata = {
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir.chdir(__dir__) do
    Dir['README.md', 'clowk.gemspec', 'config/routes.rb', 'lib/**/*.rb']
  end

  spec.require_paths = ['lib']

  spec.add_dependency 'activesupport', '>= 7.0'
  spec.add_dependency 'jwt', '>= 2.7', '< 3.0'
  spec.add_dependency 'railties', '>= 7.0'

  spec.add_development_dependency 'rspec', '>= 3.13', '< 4.0'
end
