# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "hastur-server/version"

Gem::Specification.new do |s|
  s.name        = "hastur-server"
  s.version     = Hastur::SERVER_VERSION
  s.authors     = ["Noah Gibbs"]
  s.email       = ["noah@ooyala.com"]
  s.homepage    = ""
  s.summary     = %q{A monitoring system to tame the eldritch horror of your network}
  s.description = <<EOS
Hastur is a monitoring network, so it's a bit like Nagios.  You run
clients on the monitored systems, routers to forward the information
and various back-end sinks to organize and store information about
your systems.  Hastur tracks registrations, statistics and metrics,
notifications and errors, log entries and plugins.
EOS

  s.platform = "java"

  s.rubyforge_project = "hastur-server"
  s.required_ruby_version = ">= 1.9.3"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").
                      delete_if { |f| f =~ /\.(ecology|init|pill)$/ }.map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "scope"
  s.add_development_dependency "mocha"
  s.add_development_dependency "erubis"
  s.add_development_dependency "rerun"
  s.add_development_dependency "nodule", ">=0.0.32"
  s.add_development_dependency "yard"
  s.add_development_dependency "redcarpet"
  s.add_development_dependency "simplecov"
  s.add_development_dependency "test-unit"
  s.add_development_dependency "rack-test"
  s.add_development_dependency "minitest"
  s.add_development_dependency "warbler"

  s.add_runtime_dependency "sinatra"
  s.add_runtime_dependency "httparty"
  s.add_runtime_dependency "multi_json"
  s.add_runtime_dependency "ffi-rzmq"
  s.add_runtime_dependency "trollop"
  s.add_runtime_dependency "uuid"
  s.add_runtime_dependency "termite"
  s.add_runtime_dependency "bluepill"
  s.add_runtime_dependency "rainbow"
  s.add_runtime_dependency "hastur"
  s.add_runtime_dependency "pony"
  s.add_runtime_dependency "pry"
  s.add_runtime_dependency "ohai"
  s.add_runtime_dependency "sys-uname"
  s.add_runtime_dependency "hastur-rack"
  s.add_runtime_dependency "jruby-msgpack"
end
