# frozen_string_literal: true

# Endpoint search ported from LSC Spatial Workbench core/independent-stairs.js
# (MIT, Copyright 2026 LSC). See docs/provenance.md for the pinned source.
module LSC
  module Stairs
    module Core
      extend self
      DEFAULTS = {
        'mode'=>'dimensions', 'shape'=>'U', 'rise'=>3000.0, 'width'=>1000.0,
        'landing'=>1200.0, 'riser'=>150.0, 'tread'=>300.0, 'gap'=>200.0,
        'heading'=>0.0, 'left'=>true, 'thickness'=>180.0, 'rails'=>'both',
        'rail_height'=>900.0, 'rail_radius'=>20.0, 'post_spacing'=>900.0,
        'style'=>'standard', 'beam_width'=>120.0, 'beam_depth'=>240.0
      }.freeze
      RANGES = {
        'rise'=>[150, 30000], 'width'=>[400, 5000], 'landing'=>[400, 10000],
        'riser'=>[100, 200], 'tread'=>[220, 450], 'gap'=>[0, 10000],
        'heading'=>[-36000, 36000], 'thickness'=>[30, 500],
        'rail_height'=>[600, 1500], 'rail_radius'=>[10, 60], 'post_spacing'=>[200, 1500],
        'beam_width'=>[50, 500], 'beam_depth'=>[80, 800]
      }.freeze
      LABELS = {'straight'=>'直跑', 'I'=>'双跑直梯', 'L'=>'L 型', 'U'=>'U 型'}.freeze
      STYLES = [
        {'id'=>'standard','name'=>'标准踏步','description'=>'连续台阶板，保留现有楼梯形态。','params'=>{'thickness'=>180.0}},
        {'id'=>'solid','name'=>'实心梯段','description'=>'踏步下方填实，底部保持水平。','params'=>{'thickness'=>180.0}},
        {'id'=>'waist','name'=>'斜板梯段','description'=>'锯齿踏步顶面与连续倾斜底板。','params'=>{'thickness'=>200.0}},
        {'id'=>'open','name'=>'开放踏步','description'=>'独立薄踏步，保留踏步之间的开口。','params'=>{'thickness'=>60.0}},
        {'id'=>'twin','name'=>'双侧梁踏步','description'=>'两根斜向侧梁与薄踏步、支座。','params'=>{'thickness'=>60.0,'beam_width'=>100.0,'beam_depth'=>240.0}},
        {'id'=>'spine','name'=>'中梁踏步','description'=>'单根中央斜梁与独立踏步、支座。','params'=>{'thickness'=>60.0,'beam_width'=>160.0,'beam_depth'=>280.0}}
      ].freeze

      def styles
        # Return independent data so clients cannot mutate the preset registry.
        STYLES.map { |s| s.merge('params'=>s['params'].dup) }
      end

      def normalize(input)
        raise ArgumentError, '楼梯参数应为对象。' unless input.is_a?(Hash)
        preset=STYLES.find { |s| s['id']==input.fetch('style',DEFAULTS['style']) }
        r = DEFAULTS.merge(preset ? preset['params'] : {}).merge(input.select { |k,_| DEFAULTS.key?(k) || %w[lower upper].include?(k) })
        raise ArgumentError, '未知梯型。' unless LABELS.key?(r['shape'])
        raise ArgumentError, '未知生成方式。' unless %w[dimensions endpoints].include?(r['mode'])
        raise ArgumentError, '未知扶手选项。' unless %w[none left right both].include?(r['rails'])
        raise ArgumentError, '未知楼梯样式。' unless STYLES.any? { |s| s['id']==r['style'] }
        raise ArgumentError, '转向参数无效。' unless [true, false].include?(r['left'])
        RANGES.each do |key, bounds|
          value = r[key]
          unless value.is_a?(Numeric) && value.finite? && value >= bounds[0] && value <= bounds[1]
            raise ArgumentError, "#{key} 应为 #{bounds[0]}～#{bounds[1]} 之间的数值（mm；方向为度）。"
          end
          r[key] = value.to_f
        end
        raise ArgumentError, '平台长度不能小于梯宽。' if r['shape']!='straight' && r['landing'] < r['width']
        if %w[twin spine].include?(r['style'])
          limit=r['style']=='twin' ? r['width']/2 : r['width']
          raise ArgumentError, '支撑梁过宽；双侧梁宽不能超过梯宽的一半。' if r['beam_width']>limit
        end
        if r['mode'] == 'endpoints'
          %w[lower upper].each do |end_name|
            p = r[end_name].is_a?(Hash) && r[end_name]['point']
            unless p.is_a?(Array) && p.length == 3 && p.all? { |v| v.is_a?(Numeric) && v.finite? && v.abs <= 1e8 }
              raise ArgumentError, '请点选或重新点选上下落点。'
            end
            r[end_name] = {'point'=>p.map(&:to_f)}
          end
          r['rise'] = r['upper']['point'][2] - r['lower']['point'][2]
          raise ArgumentError, '上下落点高差应在 150～30000mm 之间。' unless r['rise'].between?(150, 30000)
        else
          r.delete('lower'); r.delete('upper')
        end
        r
      end

      def solve(input = {})
        r = normalize(input)
        layout = r['mode'] == 'endpoints' ? endpoint_layout(r) : dimension_layout(r)
        # Keep every component in a stable local frame. Instance transformations
        # belong to SketchUp, and are never baked into parametric dimensions.
        a = layout[:origin]
        boxes = []; rails = []; meshes = []; flights = layout[:flights]
        add_box = lambda do |center, d, width, depth, z, detail|
          side = [-d[1], d[0]]
          corners = [[-1,-1],[1,-1],[1,1],[-1,1]].map do |u,v|
            [center[0]+side[0]*width*u/2+d[0]*depth*v/2-a[0],
             center[1]+side[1]*width*u/2+d[1]*depth*v/2-a[1]]
          end
          boxes << {'corners'=>corners, 'bottom'=>z-r['thickness']-a[2], 'top'=>z-a[2], 'detail'=>detail}
        end
        platforms = []
        add_platform = lambda do |center, d, width, depth, detail|
          add_box.call(center,d,width,depth,center[2],detail)
          platforms << {center:center, d:d, width:width, depth:depth, detail:detail}
        end
        first = flights.first; last = flights.last
        if flights.length > 1
          mid = first[:b]
          if r['shape'] == 'U'
            other = last[:a]
            center = mid.zip(other).map { |x,y| (x+y)/2 }
            add_platform.call(center,first[:d],r['width']+layout[:lateral],r['landing'],'转折平台')
          elsif r['shape'] == 'L'
            add_platform.call(mid,first[:d],r['landing'],r['landing'],'转折平台')
          else
            add_platform.call(mid,first[:d],r['width'],r['landing'],'中间平台')
          end
        end
        flights.each_with_index do |f,index|
          if %w[solid waist].include?(r['style']) && f[:n]>1
            profile=[[0,layout[:riser]]]
            (f[:n]-1).times do |j|
              profile << [(j+1)*f[:t],(j+1)*layout[:riser]]
              profile << [(j+1)*f[:t],(j+2)*layout[:riser]] if j<f[:n]-2
            end
            length=(f[:n]-1)*f[:t]
            bottom=r['style']=='solid' ? -r['thickness'] : (f[:n]-2)*layout[:riser]-r['thickness']
            profile += [[length,bottom],[0,-r['thickness']]]
            meshes << profile_mesh(f,f[:start_pad],profile,0,r['width'],a,"梯段 #{index+1}")
          end
          (f[:n]-1).times do |j|
            p = add(f[:a],f[:d],f[:start_pad]+(j+0.5)*f[:t])
            unless %w[solid waist].include?(r['style'])
              add_box.call(p,f[:d],r['width'],f[:t],f[:a][2]+(j+1)*layout[:riser],"梯段 #{index+1}")
            end
          end
          if %w[twin spine].include?(r['style']) && f[:n]>1
            offsets=r['style']=='spine' ? [0] : [-(r['width']-r['beam_width'])/2,(r['width']-r['beam_width'])/2]
            length=(f[:n]-1)*f[:t]; z_end=(f[:n]-2)*layout[:riser]-r['thickness']
            profile=[[0,-r['thickness']],[length,z_end],[length,z_end-r['beam_depth']],[0,-r['thickness']-r['beam_depth']]]
            offsets.each do |offset|
              meshes << profile_mesh(f,f[:start_pad],profile,offset,r['beam_width'],a,"梯段 #{index+1} 支撑梁")
              (f[:n]-1).times do |j|
                p=add(f[:a],f[:d],f[:start_pad]+(j+0.5)*f[:t])
                p=add(p,[-f[:d][1],f[:d][0]],offset)
                top=f[:a][2]+(j+1)*layout[:riser]-r['thickness']
                bottom=f[:a][2]+(j+0.5)*layout[:riser]-r['thickness']-40
                depth=[f[:t]/3,80].min
                side=[-f[:d][1],f[:d][0]]
                corners=[[-1,-1],[1,-1],[1,1],[-1,1]].map do |u,v|
                  [p[0]+side[0]*r['beam_width']*u/2+f[:d][0]*depth*v/2-a[0],
                   p[1]+side[1]*r['beam_width']*u/2+f[:d][1]*depth*v/2-a[1]]
                end
                boxes << {'corners'=>corners,'bottom'=>bottom-a[2],'top'=>top-a[2],'detail'=>"梯段 #{index+1} 踏步支座"}
              end
            end
          end
          %w[left right].each do |side_name|
            next unless [side_name,'both'].include?(r['rails'])
            sign = side_name == 'left' ? 1 : -1
            side = [-f[:d][1]*sign,f[:d][0]*sign]
            # Rails run from first tread nosing to the upper landing edge.
            start = add(f[:a],f[:d],f[:start_pad])
            start[2] = f[:a][2]+layout[:riser]
            finish = add(f[:b],f[:d],-f[:end_pad])
            finish[2] = f[:b][2]
            start = add(start,side,r['width']/2-r['rail_radius'])
            finish = add(finish,side,r['width']/2-r['rail_radius'])
            base = lambda { |fraction| f[:a][2]+[1+(fraction*(f[:n]-1)+1e-8).floor,f[:n]].min*layout[:riser] }
            rail_line(rails,start,finish,r,a,"梯段 #{index+1} 扶手",base)
          end
        end
        # Guard only the exposed perimeter of each platform. Flight openings
        # are subtracted geometrically so no railing blocks the walking route.
        unless r['rails'] == 'none'
          platforms.each { |p| platform_rails(rails,p,flights,r,a) }
        end
        count = flights.sum { |f| f[:n] }
        treads = flights.map { |f| f[:t] }
        comfort = treads.map { |t| 2*layout[:riser]+t }
        warnings = []
        warnings << '实际踏步偏离目标值超过 30mm，请检查落点与尺寸。' if treads.any? { |t| (t-r['tread']).abs>30 }
        warnings << '2h+b 超出 550～650mm 参考区间。' if comfort.any? { |x| !x.between?(550,650) }
        warnings << '踏步板厚小于踢面高度，梯段为开放踏步。' if r['thickness'] < layout[:riser]
        {'params'=>r, 'origin'=>a, 'boxes'=>boxes, 'rails'=>rails, 'meshes'=>meshes,
         'stats'=>{'count'=>count,'riser'=>layout[:riser],'treads'=>treads,
                   'rise'=>r['rise'],'flights'=>flights.map { |f| f[:n] },'comfort'=>comfort},
         'warnings'=>warnings, 'endpoint'=>last[:b].zip(a).map { |x,y| x-y }}
      end

      def add(p,d,n)
        [p[0]+d[0]*n,p[1]+d[1]*n,p[2]]
      end

      def profile_mesh(f,start,profile,offset,width,origin,detail)
        side=[-f[:d][1],f[:d][0]]
        vertices=[offset-width/2,offset+width/2].flat_map do |lateral|
          profile.map do |u,z|
            p=add(add(f[:a],f[:d],start+u),side,lateral)
            local([p[0],p[1],f[:a][2]+z],origin)
          end
        end
        n=profile.length
        faces=[(0...n).to_a.reverse,(n...2*n).to_a]
        n.times { |i| j=(i+1)%n; faces << [i,j,j+n,i+n] }
        {'vertices'=>vertices,'faces'=>faces,'detail'=>detail}
      end

      def directions(r)
        theta = r['heading']*Math::PI/180
        d = [Math.cos(theta),Math.sin(theta)]
        s = r['left'] ? [-d[1],d[0]] : [d[1],-d[0]]
        [d,s]
      end

      def dimension_layout(r)
        n = [(r['rise']/r['riser']).round,r['shape']=='straight' ? 2 : 4].max
        n += 1 while r['rise']/n > 200
        n -= 1 while n>1 && r['rise']/n < 100
        two = r['shape'] != 'straight'
        raise ArgumentError, '当前层高不足以生成至少两个踢面的楼梯。' if n<2
        raise ArgumentError, '双跑楼梯至少需要四个踢面；请增加层高。' if two && n<4
        d,s = directions(r); a=[0.0,0.0,0.0]
        ns = two ? [n/2,n-n/2] : [n]
        h = r['rise']/n; first_length = (two ? r['landing']/2 : 0)+(ns[0]-1)*r['tread']
        c=add(a,d,first_length); c[2]=ns[0]*h
        flights=[{a:a,b:c,d:d,n:ns[0],t:r['tread'],start_pad:0,end_pad:two ? r['landing']/2 : 0}]
        if two
          c2 = r['shape']=='U' ? add(c,s,r['width']+r['gap']) : c.dup
          direction = r['shape']=='L' ? s : r['shape']=='U' ? d.map { |v| -v } : d
          b=add(c2,direction,r['landing']/2+(ns[1]-1)*r['tread']); b[2]=r['rise']
          flights << {a:c2,b:b,d:direction,n:ns[1],t:r['tread'],start_pad:r['landing']/2,end_pad:0}
        end
        {origin:a,flights:flights,riser:h,lateral:r['width']+r['gap']}
      end

      def endpoint_layout(r)
        a=r['lower']['point']; b=r['upper']['point']; d,s=directions(r)
        delta=[b[0]-a[0],b[1]-a[1]]
        along=delta.zip(d).sum { |x,y| x*y }; lateral=delta.zip(s).sum { |x,y| x*y }
        candidates=[]; two=r['shape']!='straight'
        ((r['rise']/200).ceil..(r['rise']/100).floor).each do |n|
          next if two && n<4
          h=r['rise']/n
          unless two
            distance=Math.hypot(*delta)
            next if n<2 || distance<=0.1
            t=distance/(n-1)
            next unless t.between?(220-0.01,450+0.01)
            direction=delta.map { |v| v/distance }
            candidates << {origin:a,flights:[{a:a,b:b,d:direction,n:n,t:t,start_pad:0,end_pad:0}],riser:h}
            next
          end
          (2..n-2).each do |n1|
            n2=n-n1
            case r['shape']
            when 'L'
              t1=(along-r['landing']/2)/(n1-1); t2=(lateral-r['landing']/2)/(n2-1)
              c=add(a,d,along); c[2]=a[2]+n1*h; c2=c.dup; direction=s
            when 'U'
              next if lateral < r['width']+r['gap']-0.1
              turn=((n-2)*r['tread']+along)/2+r['landing']/2
              t1=(turn-r['landing']/2)/(n1-1); t2=(turn-along-r['landing']/2)/(n2-1)
              c=add(a,d,turn); c[2]=a[2]+n1*h; c2=add(c,s,lateral); direction=d.map { |v| -v }
            when 'I'
              next if lateral.abs > 0.1
              t1=t2=(along-r['landing'])/(n-2)
              c=add(a,d,r['landing']/2+(n1-1)*t1); c[2]=a[2]+n1*h; c2=c.dup; direction=d
            end
            next unless [t1,t2].all? { |t| t.between?(220-0.01,450+0.01) }
            candidates << {origin:a,flights:[{a:a,b:c,d:d,n:n1,t:t1,start_pad:0,end_pad:r['landing']/2},{a:c2,b:b,d:direction,n:n2,t:t2,start_pad:r['landing']/2,end_pad:0}],riser:h,lateral:lateral}
          end
        end
        chosen=candidates.min_by do |c|
          (c[:riser]-r['riser']).abs*10+c[:flights].sum { |f| (f[:t]-r['tread']).abs }+
            (c[:flights].length>1 ? (c[:flights][0][:n]-c[:flights][1][:n]).abs*0.01 : 0)
        end
        raise ArgumentError, '落点无法容纳此梯型。请调整方向、转向、平台或重选落点；U 型横向间距至少为梯宽加梯井。' unless chosen
        chosen
      end

      def local(p,a)
        p.zip(a).map { |x,y| x-y }
      end

      def rail_line(out,start,finish,r,origin,detail,post_base=nil)
        length=Math.hypot(finish[0]-start[0],finish[1]-start[1])
        return if length < 0.1
        out << {'a'=>local([start[0],start[1],start[2]+r['rail_height']],origin),
                'b'=>local([finish[0],finish[1],finish[2]+r['rail_height']],origin),
                'radius'=>r['rail_radius'],'detail'=>detail}
        divisions=[(length/r['post_spacing']).ceil,1].max
        (0..divisions).each do |i|
          p=start.zip(finish).map { |x,y| x+(y-x)*i/divisions }
          bottom=p.dup; bottom[2]=post_base.call(i.to_f/divisions) if post_base
          out << {'a'=>local(bottom,origin),'b'=>local([p[0],p[1],p[2]+r['rail_height']],origin),
                  'radius'=>r['rail_radius']*0.7,'detail'=>'立柱'}
        end
      end

      def platform_rails(out,p,flights,r,origin)
        d=p[:d]; s=[-d[1],d[0]]; c=p[:center]
        xy=lambda { |x,y| add(add(c,s,x),d,y) }
        w=p[:width]/2; depth=p[:depth]/2
        edges=[[xy.call(-w,-depth),xy.call(w,-depth)], [xy.call(w,-depth),xy.call(w,depth)],
               [xy.call(w,depth),xy.call(-w,depth)], [xy.call(-w,depth),xy.call(-w,-depth)]]
        edges.each_with_index do |(e1,e2),index|
          if p[:detail]=='中间平台'
            next if r['rails']=='left' && index==3
            next if r['rails']=='right' && index==1
          end
          len=Math.hypot(e2[0]-e1[0],e2[1]-e1[1]); dir=[(e2[0]-e1[0])/len,(e2[1]-e1[1])/len]
          intervals=[[0.0,len]]
          flights.each do |f|
            [[:a,1],[:b,-1]].each do |end_key,sign|
              q=f[end_key]; next unless (q[2]-c[2]).abs<0.1
              pad=end_key==:a ? f[:start_pad] : f[:end_pad]
              opening=add(q,f[:d],sign*pad)
              distance=((opening[0]-e1[0])*dir[1]-(opening[1]-e1[1])*dir[0]).abs
              next if distance>0.1
              projection=(opening[0]-e1[0])*dir[0]+(opening[1]-e1[1])*dir[1]
              lo=projection-r['width']/2; hi=projection+r['width']/2
              intervals=intervals.flat_map { |a,b| hi<=a || lo>=b ? [[a,b]] : [[a,[lo,b].min],[[hi,a].max,b]].select { |x,y| y-x>1 } }
            end
          end
          intervals.each do |lo,hi|
            a=add(e1,dir,lo+r['rail_radius']); b=add(e1,dir,hi-r['rail_radius'])
            rail_line(out,a,b,r,origin,'平台扶手') if hi-lo>2*r['rail_radius']
          end
        end
      end
    end
  end
end
