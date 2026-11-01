# frozen_string_literal: true
require 'minitest/autorun'
require 'json'
require_relative '../src/lsc_stairs/core'
class StairStylesTest < Minitest::Test
  C=LSC::Stairs::Core
  def signed_volume(mesh)
    vertices=mesh['vertices']
    mesh['faces'].sum do |face|
      a=vertices[face[0]]
      (1...face.length-1).sum do |i|
        b=vertices[face[i]]; c=vertices[face[i+1]]
        (a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6.0
      end
    end
  end
  def test_all_six_presets_are_geometry_only_and_keep_primary_dimensions
    styles=C.styles
    assert_equal %w[standard solid waist open twin spine],styles.map { |s| s['id'] }
    styles.each do |s|
      assert (s['params'].keys-%w[thickness beam_width beam_depth]).empty?
      p=C.solve('style'=>s['id'],'rise'=>3150,'width'=>1200,'tread'=>280,'landing'=>1400,'rails'=>'left')
      assert_equal 3150,p['params']['rise']
      assert_equal 1200,p['params']['width']
      assert_equal 280,p['params']['tread']
      assert_equal 'left',p['params']['rails']
      s['params'].each { |key,value| assert_equal value,p['params'][key] }
    end
  end
  def test_every_style_mesh_is_closed_oriented_and_positive_in_all_shapes
    C.styles.product(%w[straight I L U],[true,false],[0,37,-90]).each do |style,shape,left,heading|
      p=C.solve('style'=>style['id'],'shape'=>shape,'left'=>left,'heading'=>heading,'rise'=>3150)
      assert_in_delta 3150,p['endpoint'][2],0.001
      p['meshes'].each do |mesh|
        assert mesh['vertices'].flatten.all?(&:finite?)
        edges=Hash.new { |h,k| h[k]=[] }
        mesh['faces'].each do |face|
          assert face.all? { |i| i.between?(0,mesh['vertices'].length-1) }
          face.each_with_index do |a,i|
            b=face[(i+1)%face.length]; refute_equal a,b
            edges[[a,b].sort] << [a,b]
          end
        end
        edges.each_value { |pair| assert_equal 2,pair.length; assert_equal pair[0],pair[1].reverse }
        assert signed_volume(mesh)>0.01,"Negative or zero volume: #{style['id']} / #{shape}"
      end
    end
  end
  def test_solid_and_waist_are_distinct_closed_profiles
    solid=C.solve('style'=>'solid','shape'=>'straight')
    waist=C.solve('style'=>'waist','shape'=>'straight')
    assert_equal 1,solid['meshes'].length
    assert_equal 1,waist['meshes'].length
    assert_empty solid['boxes']
    assert_empty waist['boxes']
    assert signed_volume(solid['meshes'][0])>signed_volume(waist['meshes'][0])*2
    assert_equal '梯段 1',waist['meshes'][0]['detail']
  end
  def test_open_steps_use_thin_independent_plates
    p=C.solve('style'=>'open','shape'=>'straight')
    assert_empty p['meshes']
    steps=p['boxes'].select { |b| b['detail']=='梯段 1' }
    assert_equal 19,steps.length
    steps.each { |step| assert_in_delta 60,step['top']-step['bottom'],1e-7 }
    assert p['warnings'].any? { |w| w.include?('开放踏步') }
  end
  def test_twin_and_spine_have_actual_beams_and_seats
    {'twin'=>4,'spine'=>2}.each do |style,beams|
      p=C.solve('style'=>style)
      assert_equal beams,p['meshes'].length
      assert p['meshes'].all? { |m| m['detail'].include?('支撑梁') }
      seats=p['boxes'].select { |b| b['detail'].include?('踏步支座') }
      assert_equal beams*9,seats.length
      assert seats.all? { |b| b['top']>b['bottom'] }
    end
  end
  def test_explicit_custom_dimensions_survive_round_trip
    p=C.solve('style'=>'spine','thickness'=>80,'beam_width'=>180,'beam_depth'=>320)
    q=C.solve(JSON.parse(JSON.generate(p['params'])))
    assert_equal p,q
    assert_equal 80,q['params']['thickness']
    assert_equal 180,q['params']['beam_width']
    assert_equal 320,q['params']['beam_depth']
  end
  def test_old_component_parameters_default_to_standard_style
    old=C::DEFAULTS.reject { |key,_| %w[style beam_width beam_depth].include?(key) }
    p=C.solve(old)
    assert_equal 'standard',p['params']['style']
    assert_empty p['meshes']
    assert_equal C.solve['boxes'],p['boxes']
  end
  def test_style_limits_and_registry_isolation
    assert_raises(ArgumentError) { C.solve('style'=>'unknown') }
    assert_raises(ArgumentError) { C.solve('style'=>'twin','width'=>400,'beam_width'=>250) }
    assert_raises(ArgumentError) { C.solve('style'=>'spine','beam_depth'=>0) }
    data=C.styles; data[0]['params']['thickness']=123
    assert_equal 180,C.styles[0]['params']['thickness']
  end
  def test_all_styles_omit_terminal_floor_plates_and_keep_only_the_middle_landing
    C.styles.product(%w[straight I L U]).each do |style,shape|
      p=C.solve('style'=>style['id'],'shape'=>shape)
      assert p['boxes'].none? { |b| %w[下平台 上平台].include?(b['detail']) }
      platforms=p['boxes'].select { |b| b['detail'].include?('平台') }
      assert_equal(shape=='straight' ? 0 : 1,platforms.length)
      if shape=='straight'
        assert p['rails'].none? { |rail| rail['detail']=='平台扶手' }
        points=p['boxes'].flat_map { |b| b['corners'] }+p['meshes'].flat_map { |m| m['vertices'] }
        assert_in_delta 0,points.map { |v| v[0] }.min,0.01
        assert_in_delta p['endpoint'][0],points.map { |v| v[0] }.max,0.01
      end
    end
  end
end
