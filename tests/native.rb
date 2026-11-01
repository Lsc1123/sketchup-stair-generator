# frozen_string_literal: true
# Run only in a separate SketchUp process with an explicitly named empty fixture.
require 'json'
require 'fileutils'
require 'digest'
module LSCStairsNativeTest
  extend self
  def assert(value,message)
    raise message unless value
  end
  def check(name)
    yield
    @results << {name:name,pass:true}
  rescue StandardError=>e
    @results << {name:name,pass:false,error:"#{e.class}: #{e.message}",trace:e.backtrace.first(4)}
  end
  def write(complete=false)
    File.write(File.join(@output,'native.json'),JSON.pretty_generate({complete:complete,
      pass:complete && @results.all? { |r| r[:pass] },pid:Process.pid,sketchup:Sketchup.version,ruby:RUBY_DESCRIPTION,
      packaged_runtime:true,results:@results})+"\n")
  end
  def run(fixture:,package:,output:)
    @output=output; FileUtils.mkdir_p(output); @results=[]
    @model=Sketchup.active_model
    assert(@model && @model.path==fixture && @model.entities.length.zero? && @model.active_path.nil?,'Not the dedicated empty fixture')
    $LOAD_PATH.unshift(package)
    require File.join(package,'lsc_stairs.rb')
    @plugin=LSC::Stairs
    assert(File.realpath(@plugin::Core.method(:solve).source_location.first)==File.realpath(File.join(package,'lsc_stairs/core.rb')),'Wrong runtime source')
    check('extension registration and coexistence') do
      assert(defined?(LSC::SpatialWorkbench),'Original workbench not loaded in this host; coexistence unverified')
      assert(LSC::Stairs::DICT!=LSC::SpatialWorkbench::DICT,'Metadata namespace conflict')
    end
    %w[straight I L U].each do |shape|
      check("#{shape}: closed step, platform and railing solids") do
        @model.entities.clear!
        plan=@plugin::Core.solve('shape'=>shape)
        instance=@plugin::Geometry.create(@model,plan)
        solids=instance.definition.entities.grep(Sketchup::Group).flat_map { |g| g.entities.grep(Sketchup::Group) }
        assert(solids.length==plan['boxes'].length+plan['rails'].length,'Wrong solid count')
        assert(solids.all?(&:manifold?),'Open solid')
        assert(instance.get_attribute(@plugin::DICT,'schema')==1,'Missing metadata')
      end
    end
    check('negative elevation endpoint placement') do
      @model.entities.clear!
      plan=@plugin::Core.solve('shape'=>'straight','mode'=>'endpoints','lower'=>{'point'=>[1000,2000,-3000]},'upper'=>{'point'=>[7900,2000,0]})
      instance=@plugin::Geometry.create(@model,plan)
      assert((instance.transformation.origin.z*25.4+3000).abs<0.01,'Wrong origin')
      assert((instance.bounds.max.z*25.4-900).abs<0.1,'Wrong upper elevation')
    end
    check('update preserves instance, transform, tag, material and copied sibling') do
      @model.entities.clear!
      @instance=@plugin::Geometry.create(@model,@plugin::Core.solve)
      @old_definition=@instance.definition
      @sibling=@model.entities.add_instance(@old_definition,Geom::Transformation.translation([300,0,0]))
      # add_instance does not copy per-instance attributes; mirror native copy
      # semantics explicitly so this fixture exercises a parametric sibling.
      @plugin::Geometry.stamp(@sibling,@plugin::Core.solve)
      @old_stats=@sibling.get_attribute(@plugin::DICT,'stats')
      @instance.transformation=Geom::Transformation.translation([15,24,30])*Geom::Transformation.rotation(ORIGIN,Z_AXIS,0.57)*Geom::Transformation.scaling(1.3,0.8,1.1)
      @transform=@instance.transformation.to_a
      @instance.name='我的测试楼梯'
      @layer=@model.layers.add('测试楼梯'); @instance.layer=@layer
      @material=@model.materials.add('测试材质'); @material.color='orange'; @instance.material=@material
      @instance_id=@instance.persistent_id
      @updated_plan=@plugin::Core.solve('shape'=>'L','rise'=>3300,'rails'=>'none')
      @plugin::Geometry.update(@model,@instance,@updated_plan)
      assert(@instance.persistent_id==@instance_id,'Instance replaced')
      assert(@instance.transformation.to_a==@transform,'Transform changed')
      assert(@instance.name=='我的测试楼梯' && @instance.layer==@layer && @instance.material==@material,'Presentation changed')
      assert(@instance.definition!=@sibling.definition && @sibling.definition==@old_definition,'Copied sibling changed')
      assert(@sibling.get_attribute(@plugin::DICT,'stats')==@old_stats,'Sibling metadata changed')
    end
    write
    Sketchup.undo
    UI.start_timer(0.25,false) { after_undo }
  rescue StandardError=>e
    @results ||= []
    @results << {name:'runner',pass:false,error:e.message,trace:e.backtrace.first(6)}
    write(true)
  end
  def after_undo
    check('undo restores shared definition and original parameters') do
      @instance=@model.find_entity_by_persistent_id(@instance_id)
      assert(@instance && @instance.definition==@sibling.definition,'Undo did not restore definition')
      assert(JSON.parse(@instance.get_attribute(@plugin::DICT,'params'))['shape']=='U','Undo did not restore parameters')
    end
    check('failed rebuild rolls back geometry and metadata') do
      before=@instance.definition
      params=@instance.get_attribute(@plugin::DICT,'params')
      bad=JSON.parse(JSON.generate(@updated_plan)); bad['boxes'][2]['corners']=[[0,0],[0,0],[0,0],[0,0]]
      begin
        @plugin::Geometry.update(@model,@instance,bad)
        raise 'Invalid rebuild was accepted'
      rescue StandardError=>e
        raise if e.message=='Invalid rebuild was accepted'
      end
      @rollback_definition=before; @rollback_params=params
    end
    UI.start_timer(0.25,false) { after_rollback }
  end
  def after_rollback
    check('aborted operation leaves original and sibling intact') do
      @instance=@model.find_entity_by_persistent_id(@instance_id)
      assert(@instance.definition==@rollback_definition,'Original geometry changed after abort')
      assert(@instance.get_attribute(@plugin::DICT,'params')==@rollback_params,'Original metadata changed after abort')
      assert(@sibling.valid?,'Sibling erased')
    end
    check('locked instance rejects update without mutation') do
      @instance.locked=true
      begin
        @plugin::Geometry.update(@model,@instance,@updated_plan)
        raise 'Locked update accepted'
      rescue StandardError=>e
        assert(e.message.include?('解锁'),'Unexpected locked update failure')
      ensure
        @instance.locked=false
      end
    end
    check('save keeps parametric metadata') do
      @roundtrip=File.join(@output,'roundtrip.skp')
      assert(@model.save(@roundtrip),'Save failed')
    end
    # Loading only our own just-saved fixture in this separate host is safe.
    Sketchup.open_file(@roundtrip)
    UI.start_timer(0.5,false) { after_reopen }
  end
  def after_reopen
    @model=Sketchup.active_model
    check('save/reopen keeps editable parameters') do
      assert(@model.path==@roundtrip,'Wrong reopened model')
      instances=@model.entities.grep(Sketchup::ComponentInstance).select { |i| @plugin::Geometry.owned?(i) }
      assert(instances.length==2,'Instances missing')
      assert(instances.all? { |i| JSON.parse(i.get_attribute(@plugin::DICT,'params'))['shape']=='U' },'Parameters lost')
    end
    # Keep one example for visual inspection, saved only under test-results.
    @model.entities.clear!
    @plugin::Geometry.create(@model,@plugin::Core.solve)
    @model.active_view.zoom_extents
    @model.save(File.join(@output,'example-U.skp'))
    write(true)
  end
end
