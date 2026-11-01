# frozen_string_literal: true
# Protocol tests with a tiny UI seam, not an emulator of SketchUp geometry.
require 'minitest/autorun'
require 'json'
$LOADED_FEATURES << 'sketchup.rb'
def file_loaded?(_path); true; end
module Sketchup
  class << self
    attr_accessor :active_model
  end
end
module UI
  class HtmlDialog
    STYLE_DIALOG=0
    attr_reader :callbacks,:scripts
    def initialize(**_options); @callbacks={}; @scripts=[]; end
    def set_file(_path); end
    def add_action_callback(name,&block); @callbacks[name]=block; end
    def set_on_closed(&block); @close=block; end
    def show; end
    def bring_to_front; end
    def execute_script(code); @scripts << code; end
    def close; @close.call; end
  end
end
require_relative '../src/lsc_stairs/main'
class StairControllerTest < Minitest::Test
  Plugin=LSC::Stairs
  Model=Struct.new(:active_path,:selection,:entities,:selected_tools) do
    def ==(other); equal?(other); end
    def select_tool(tool); selected_tools << tool; end
  end
  def setup
    Plugin.instance_variables.each { |key| Plugin.remove_instance_variable(key) }
    @model=Model.new(nil,[],[],[]); Sketchup.active_model=@model
    Plugin.show; @dialog=Plugin.instance_variable_get(:@dialog)
  end
  def payload(extra={})
    {'params'=>LSC::Stairs::Core::DEFAULTS,'revision'=>4,'model_preview'=>false}.merge(extra)
  end
  def test_preview_computes_geometry_but_never_creates_entities
    Plugin.handle('preview',payload)
    assert @dialog.scripts.last.include?('"count":20')
    assert @dialog.scripts.last.include?('"revision":4')
    assert_empty @model.entities
  end
  def test_switching_models_clears_target_and_blocks_the_current_action
    Plugin.instance_variable_set(:@target,Object.new)
    Sketchup.active_model=Model.new(nil,[],[],[])
    assert_raises(RuntimeError) { Plugin.handle('apply',payload) }
    assert_nil Plugin.instance_variable_get(:@target)
    assert @dialog.scripts.last.include?('"reset"')
    assert_empty Sketchup.active_model.entities
  end
  def test_active_edit_context_blocks_generation
    @model.active_path=[:editing]
    error=assert_raises(RuntimeError) { Plugin.handle('apply',payload) }
    assert_includes error.message,'退出'
  end
  def test_invalid_preview_returns_error_and_clears_our_owned_tool
    tool=Object.new; Plugin.instance_variable_set(:@tool,tool); Plugin.instance_variable_set(:@tool_model,@model)
    @dialog.callbacks.fetch('preview').call(nil,payload('params'=>{'width'=>0}))
    assert_equal [nil],@model.selected_tools
    assert_nil Plugin.instance_variable_get(:@tool)
    assert @dialog.scripts.last.include?('"error"')
  end
  def test_stop_preview_never_cancels_a_native_tool_we_do_not_own
    Plugin.handle('stop_preview',nil)
    assert_empty @model.selected_tools
  end
  def test_missing_endpoints_cannot_generate
    error=assert_raises(RuntimeError) { Plugin.handle('apply',payload('params'=>{'mode'=>'endpoints'})) }
    assert_includes error.message,'点选'
    assert_empty @model.entities
  end
  def test_closing_and_reopening_registers_fresh_callbacks
    @dialog.close
    assert_nil Plugin.instance_variable_get(:@dialog)
    Plugin.show
    reopened=Plugin.instance_variable_get(:@dialog)
    refute_same @dialog,reopened
    assert_equal %w[apply cancel pick preview read ready stop_preview],reopened.callbacks.keys.sort
    reopened.callbacks.fetch('ready').call(nil,nil)
    assert reopened.scripts.last.include?('"ready"')
  end
  def test_failed_read_keeps_no_new_target
    @dialog.callbacks.fetch('read').call(nil,nil)
    assert_nil Plugin.instance_variable_get(:@target)
    assert @dialog.scripts.last.include?('"error"')
  end
end
