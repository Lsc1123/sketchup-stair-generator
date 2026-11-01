# frozen_string_literal: true
require 'rbconfig'
root=File.expand_path('..',__dir__)
files=Dir[File.join(root,'{src,tests,tools}/**/*.rb')]
exit(files.all? { |path| system(RbConfig.ruby,'-c',path) } ? 0 : 1)
