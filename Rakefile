require "bundler/gem_tasks"
require "rake/testtask"

namespace "test" do
  desc "Unit tests for Hastur"
  Rake::TestTask.new(:units) do |t|
    t.libs += ["test"]  # require from test subdir
    t.test_files = Dir["test/units/*_test.rb"]
    t.verbose = true
  end
end

# Put together a test target for Jenkins
task :test => ["test:units"]