# frozen_string_literal: true
module LSC
  module Stairs
    class PreviewTool
      def initialize(plan,transform)
        @plan=plan; @transform=transform
      end
      def activate
        Sketchup.set_status_text('楼梯预览：在参数面板修改尺寸；Esc 关闭模型预览。')
        Sketchup.active_model.active_view.invalidate
      end
      def draw(view)
        view.drawing_color=Sketchup::Color.new(23,110,96,170)
        view.line_width=1
        @plan['boxes'].each do |box|
          rings=[box['bottom'],box['top']].map { |z| box['corners'].map { |p| Geometry.point([*p,z]).transform(@transform) } }
          rings.each { |ring| view.draw(GL_LINE_LOOP,ring) }
          view.draw(GL_LINES,rings[0].zip(rings[1]).flatten)
        end
        @plan.fetch('meshes',[]).each do |mesh|
          points=mesh['vertices'].map { |p| Geometry.point(p).transform(@transform) }
          mesh['faces'].each { |face| view.draw(GL_LINE_LOOP,face.map { |i| points[i] }) }
        end
        view.line_width=2
        view.draw(GL_LINES,@plan['rails'].flat_map { |r| [r['a'],r['b']].map { |p| Geometry.point(p).transform(@transform) } }) unless @plan['rails'].empty?
      end
      def getExtents
        bounds=Geom::BoundingBox.new
        @plan['boxes'].each do |box|
          [box['bottom'],box['top']].each { |z| box['corners'].each { |p| bounds.add(Geometry.point([*p,z]).transform(@transform)) } }
        end
        @plan['rails'].each { |r| [r['a'],r['b']].each { |p| bounds.add(Geometry.point(p).transform(@transform)) } }
        @plan.fetch('meshes',[]).each { |mesh| mesh['vertices'].each { |p| bounds.add(Geometry.point(p).transform(@transform)) } }
        bounds
      end
      def onCancel(_reason,view)
        Stairs.cancel_tool; view.invalidate
      end
      def deactivate(view)
        Stairs.tool_deactivated(self)
        view.invalidate
      end
    end

    class PlacementTool < PreviewTool
      def initialize(plan,model)
        @plan=plan; @model=model; @input=Sketchup::InputPoint.new
        @transform=Geom::Transformation.new
      end
      def activate
        Sketchup.set_status_text('点选楼梯下方接入边缘放置；Esc 取消。')
      end
      def onMouseMove(_flags,x,y,view)
        @input.pick(view,x,y); view.tooltip=@input.tooltip
        @transform=Geom::Transformation.translation(@input.position.to_a) if @input.valid?
        view.invalidate
      end
      def draw(view)
        @input.draw(view) if @input.valid?
        super(view)
      end
      def onLButtonDown(_flags,x,y,view)
        raise '当前模型已改变。' unless Sketchup.active_model==@model
        @input.pick(view,x,y)
        return unless @input.valid?
        @transform=Geom::Transformation.translation(@input.position.to_a)
        Geometry.create(@model,@plan,@transform)
        Stairs.finish_tool
        Stairs.send_ui('notice',{'text'=>'楼梯已生成。选中后可读取参数并原位更新。'})
      rescue StandardError=>e
        Stairs.send_ui('error',{'text'=>e.message})
      end
    end

    class EndpointTool
      def initialize(model)
        @model=model; @input=Sketchup::InputPoint.new; @points=[]
      end
      def activate
        Sketchup.set_status_text('点选下方落点；可在普通模型上捕捉。Esc 取消。')
      end
      def onMouseMove(_flags,x,y,view)
        @input.pick(view,x,y); view.tooltip=@input.tooltip; view.invalidate
      end
      def draw(view)
        @input.draw(view) if @input.valid?
        view.drawing_color='#176e60'
        view.draw_points(@points,10,2) unless @points.empty?
      end
      def onLButtonDown(_flags,x,y,view)
        raise '当前模型已改变。' unless Sketchup.active_model==@model
        @input.pick(view,x,y); return unless @input.valid?
        point=@input.position
        raise '上方落点必须高于下方至少 150mm。' if @points.length==1 && (point.z-@points.first.z)*25.4<150
        @points << point.clone
        if @points.length==1
          Sketchup.set_status_text('点选上方落点；使用实际捕捉标高。Esc 取消。')
        else
          Stairs.accept_endpoints(@points.map { |p| p.to_a.map { |v| v*25.4 } })
          Stairs.finish_tool
        end
      rescue StandardError=>e
        Stairs.send_ui('error',{'text'=>e.message})
      end
      def onCancel(_reason,view)
        Stairs.cancel_tool; view.invalidate
      end
      def deactivate(view)
        Stairs.tool_deactivated(self)
        view.invalidate
      end
    end
  end
end
