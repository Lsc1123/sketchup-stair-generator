# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'
require_relative 'lsc_stairs/version'

module LSC
  module Stairs
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('LSC 楼梯生成器', File.join(__dir__,'lsc_stairs','main'))
      extension.description = '独立参数楼梯：四种梯型、六种几何样式、平台扶手、实时预览和参数更新。'
      extension.version = VERSION
      extension.creator = 'LSC'
      extension.copyright = 'Copyright 2026 LSC · MIT'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
