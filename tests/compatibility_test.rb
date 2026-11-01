# frozen_string_literal: true
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'json'

class StairCompatibilityTest < Minitest::Test
  def test_legacy_array_sum_does_not_change_counts_or_endpoint_solutions
    # Run the hostile extension in a separate Ruby process. Do not patch the
    # test framework or the actual SketchUp host's globally shared Array class.
    script=<<~'RUBY'
      require 'json'
      class Array
        def sum(_initial=0)
          values=select { |value| value.is_a?(Numeric) }
          values.empty? ? nil : values.inject(0) { |total,value| total+value }
        end
      end
      require File.join(ARGV.fetch(0),'src/lsc_stairs/core')
      core=LSC::Stairs::Core
      results=[]
      core.styles.product(%w[straight I L U],[true,false],[0,37,-90]).each do |style,shape,left,heading|
        plan=core.solve('style'=>style['id'],'shape'=>shape,'left'=>left,'heading'=>heading,'rise'=>3150)
        origin=[-2500.0,5000.0,-3000.0]
        upper=plan['endpoint'].zip(origin).map { |x,y| x+y }
        fitted=core.solve(plan['params'].merge('mode'=>'endpoints','lower'=>{'point'=>origin},'upper'=>{'point'=>upper}))
        raise 'Wrong dimension count' unless plan['stats']['count']==21
        raise 'Wrong endpoint count' unless fitted['stats']['count']==21
        raise 'Endpoint changed' unless plan['endpoint'].zip(fitted['endpoint']).all? { |x,y| (x-y).abs<0.01 }
        raise 'Tread changed' unless fitted['stats']['treads'].all? { |t| (t-300).abs<0.01 }
        results << [style['id'],shape,left,heading]
      end
      puts JSON.generate('cases'=>results.length,'hostile_sum_still_active'=>[1,2].sum { |x| x*10 }==3)
    RUBY
    output,error,status=Open3.capture3(RbConfig.ruby,'-e',script,File.expand_path('..',__dir__))
    assert status.success?,"Legacy Array#sum regression:\n#{output}\n#{error}"
    report=JSON.parse(output)
    assert_equal 144,report['cases']
    assert report['hostile_sum_still_active']
  end
end
