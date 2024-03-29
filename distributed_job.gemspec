# frozen_string_literal: true

require_relative 'lib/distributed_job/version'

Gem::Specification.new do |spec|
  spec.name          = 'distributed_job'
  spec.version       = DistributedJob::VERSION
  spec.authors       = ['Benjamin Vetter']
  spec.email         = ['benjamin.vetter@wlw.de']

  spec.summary       = 'Keep track of distributed jobs using redis'
  spec.description   = 'Keep track of distributed jobs spanning multiple workers using redis'
  spec.homepage      = 'https://github.com/mrkamel/distributed_job'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.5.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/mrkamel/distributed_job'
  spec.metadata['changelog_uri'] = 'https://github.com/mrkamel/distributed_job/blob/master/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'redis', '>= 4.1.0'
end
