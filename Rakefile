#!/usr/bin/env rake
require "bundler/gem_tasks"

require 'rake/testtask'
require 'rake/clean'

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  t.fail_on_error = false
end

task :default => [:spec, :build]
