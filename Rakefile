# frozen_string_literal: true

# Provides build / install / release. `rake release` tags the version, pushes
# the tag, and publishes to RubyGems — see "Publicar una versión" in the README.
# A published version number can never be reused, so it runs `check` first.
require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
  t.warning = false
end

RuboCop::RakeTask.new

desc "Ejecuta las pruebas y el linter"
task check: %i[test rubocop]

# A fiscal document library should not ship on a red build, so the release
# tasks bundler defines run the full check first.
task build: :check
task release: :check

task default: :check
