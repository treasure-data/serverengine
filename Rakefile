#!/usr/bin/env rake
require "bundler/gem_tasks"

require 'rake/testtask'
require 'rake/clean'

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)
task :default => [:spec, :build]
