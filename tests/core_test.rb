# frozen_string_literal: true
require 'minitest/autorun'
require 'json'
require_relative '../src/lsc_stairs/core'
class StairCoreTest < Minitest::Test
  C=LSC::Stairs::Core
  def test_all_shapes_and_turns_close_exactly_without_mutating_input
    %w[straight I L U].product([true,false],[0,37,-90,180],[2100,3000,3150,4200]).each do |shape,left,heading,rise|
      input={'shape'=>shape,'left'=>left,'heading'=>heading,'rise'=>rise}
      before=JSON.generate(input); p=C.solve(input)
      assert_equal before,JSON.generate(input)
      assert_in_delta rise,p['stats']['count']*p['stats']['riser'],1e-7
      assert_in_delta rise,p['endpoint'][2],1e-7
      assert p['stats']['riser'].between?(100,200)
      assert p['boxes'].all? { |b| b['corners'].flatten.all?(&:finite?) && b['top']>b['bottom'] }
      assert p['rails'].all? { |r| r['a'].zip(r['b']).any? { |a,b| a!=b } }
    end
  end
  def test_endpoint_layout_round_trips_dimension_layout
    %w[straight I L U].product([true,false],[0,73,-90]).each do |shape,left,heading|
      a=[-2500.0,5000.0,-3000.0]
      p=C.solve('shape'=>shape,'left'=>left,'heading'=>heading,'rise'=>3150)
      b=p['endpoint'].zip(a).map { |x,y| x+y }
      q=C.solve(p['params'].merge('mode'=>'endpoints','lower'=>{'point'=>a},'upper'=>{'point'=>b}))
      assert_in_delta 3150,q['stats']['rise'],1e-7
      p['endpoint'].zip(q['endpoint']).each { |x,y| assert_in_delta x,y,0.01 }
      assert_equal p['stats']['count'],q['stats']['count']
      assert q['stats']['treads'].all? { |v| (v-300).abs<0.01 }
    end
  end
  def test_standard_riser_and_tread_convention
    p=C.solve('shape'=>'straight','rails'=>'none')
    steps=p['boxes'].select { |b| b['detail']=='梯段 1' }
    assert_equal 20,p['stats']['count']
    assert_equal 19,steps.length
    assert_equal 19,p['boxes'].length
    assert_in_delta 5700,p['endpoint'][0],1e-7
    assert_equal (1..19).map { |n| n*150.0 },steps.map { |s| s['top'] }
    assert_empty p['rails']
  end
  def test_boxes_do_not_overlap_in_volume
    %w[straight I L U].each do |shape|
      p=C.solve('shape'=>shape,'landing'=>1500)
      p['boxes'].combination(2) do |a,b|
        z=[a['top'],b['top']].min-[a['bottom'],b['bottom']].max
        next unless z>0.01
        widths=[0,1].map do |axis|
          ar=a['corners'].map { |v| v[axis] }.minmax; br=b['corners'].map { |v| v[axis] }.minmax
          [ar[1],br[1]].min-[ar[0],br[0]].max
        end
        assert widths.any? { |w| w<0.01 },"#{shape}: overlapping #{a['detail']} and #{b['detail']}"
      end
    end
  end
  def test_endpoints_reject_unusable_layouts
    base={'mode'=>'endpoints','lower'=>{'point'=>[0,0,0]},'upper'=>{'point'=>[0,100,3000]}}
    assert_raises(ArgumentError) { C.solve(base) }
    assert_raises(ArgumentError) { C.solve(base.merge('upper'=>{'point'=>[0,0,-100]})) }
    assert_raises(ArgumentError) { C.solve(base.merge('lower'=>nil)) }
    assert_raises(ArgumentError) { C.solve(base.merge('upper'=>{'point'=>[Float::INFINITY,0,3000]})) }
  end
  def test_boundary_inputs_and_resource_limits
    [{'width'=>399},{'landing'=>999},{'rise'=>30001},{'rise'=>Float::NAN},{'left'=>'true'},
     {'heading'=>'0'},{'shape'=>'spiral'},{'rails'=>'invalid'},{'thickness'=>0},{'post_spacing'=>1}].each do |input|
      assert_raises(ArgumentError,input.inspect) { C.solve(input) }
    end
    assert_raises(ArgumentError) { C.solve(nil) }
    assert_raises(ArgumentError) { C.solve('rise'=>150,'shape'=>'L') }
    p=C.solve('rise'=>30000,'riser'=>100,'post_spacing'=>200)
    assert_equal 300,p['stats']['count']
    assert p['rails'].length<2500
    assert_raises(ArgumentError) { C.solve('shape'=>'straight','rise'=>150) }
    assert_equal 1,C.solve('shape'=>'straight','rise'=>200)['boxes'].length
  end
  def test_flight_posts_land_on_actual_steps
    p=C.solve('shape'=>'straight','rise'=>3150,'post_spacing'=>700)
    posts=p['rails'].select { |r| r['detail']=='立柱' }
    assert posts.length>4
    posts.each do |post|
      z=post['a'][2]
      assert_in_delta (z/p['stats']['riser']).round,z/p['stats']['riser'],1e-7
      assert post['b'][2]-z>=900-1e-7
    end
  end
  def test_landing_railings_leave_u_flight_openings_clear
    p=C.solve
    # Both flights open onto the near side of the middle platform at x=2700.
    on_edge=p['rails'].select { |r| r['detail']=='平台扶手' && (r['a'][0]-2700).abs<0.01 && (r['b'][0]-2700).abs<0.01 }
    refute_empty on_edge
    on_edge.each do |r|
      lo,hi=[r['a'][1],r['b'][1]].minmax
      assert hi<=-500+0.01 || lo>=1700-0.01 || (lo>=500-0.01 && hi<=700+0.01)
    end
  end
  def test_rails_select_correct_flight_side
    {'left'=>480,'right'=>-480}.each do |side,y|
      p=C.solve('shape'=>'straight','rails'=>side)
      rails=p['rails'].select { |r| r['detail']=='梯段 1 扶手' }
      assert_equal 1,rails.length
      assert_in_delta y,rails[0]['a'][1],1e-7
    end
  end
  def test_solutions_are_json_round_trippable_and_unknown_keys_ignored
    p=C.solve('untrusted_key'=>'anything')
    assert_equal p,JSON.parse(JSON.generate(p))
    refute p['params'].key?('untrusted_key')
  end
end
