# frozen_string_literal: true
module LSC
  module Stairs
    DICT = 'LSC_Stairs'
    module Geometry
      extend self
      def point(p)
        Geom::Point3d.new(p.map { |v| v/25.4 })
      end

      def polygon_normal(ring)
        # Newell's method uses the complete boundary. The first three vertices
        # of a concave stair profile can turn opposite to the polygon winding.
        normal=[0.0,0.0,0.0]
        ring.each_with_index do |a,i|
          b=ring[(i+1)%ring.length]
          normal[0]+=(a.y-b.y)*(a.z+b.z)
          normal[1]+=(a.z-b.z)*(a.x+b.x)
          normal[2]+=(a.x-b.x)*(a.y+b.y)
        end
        Geom::Vector3d.new(normal)
      end

      def fill(entities,plan)
        buckets={}
        plan['boxes'].each do |box|
          bucket=buckets[box['detail']] ||= entities.add_group.tap { |g| g.name=box['detail'] }
          solid=bucket.entities.add_group; solid.name='踏步／平台'
          face=solid.entities.add_face(box['corners'].map { |p| point([*p,box['bottom']]) })
          raise '踏步面生成失败。' unless face
          face.reverse! if face.normal.z < 0
          face.pushpull((box['top']-box['bottom'])/25.4)
          raise '踏步实体未闭合。' unless solid.manifold?
        end
        plan.fetch('meshes',[]).each do |mesh|
          bucket=buckets[mesh['detail']] ||= entities.add_group.tap { |g| g.name=mesh['detail'] }
          solid=bucket.entities.add_group; solid.name=mesh['detail']
          points=mesh['vertices'].map { |p| point(p) }
          oriented_faces=mesh['faces'].map do |indices|
            ring=indices.map { |i| points.fetch(i) }
            face=solid.entities.add_face(ring)
            raise '楼梯样式构件生成失败。' unless face
            [face,polygon_normal(ring)]
          end
          # Orient after all faces exist so add_face's adjacency inference
          # cannot change a face that we already checked.
          oriented_faces.each { |face,normal| face.reverse! if face.normal.dot(normal)<0 }
          raise '楼梯样式构件未闭合。' unless solid.manifold?
        end
        plan['rails'].each do |rail|
          bucket=buckets['扶手与立柱'] ||= entities.add_group.tap { |g| g.name='扶手与立柱' }
          solid=bucket.entities.add_group; solid.name=rail['detail']
          a=point(rail['a']); b=point(rail['b']); axis=b-a
          next if axis.length < 0.001
          edges=solid.entities.add_circle(a,axis,rail['radius']/25.4,12)
          face=solid.entities.add_face(edges)
          raise '扶手截面生成失败。' unless face
          face.reverse! if face.normal.dot(axis) < 0
          face.pushpull(axis.length)
          raise '扶手实体未闭合。' unless solid.manifold?
          solid.entities.grep(Sketchup::Edge).each do |edge|
            next unless edge.faces.length==2 && edge.faces[0].normal.dot(edge.faces[1].normal)>0.5
            edge.soft=true; edge.smooth=true
          end
        end
        buckets
      end

      def create(model,plan,transformation=nil)
        raise '请先退出群组或组件编辑。' if model.active_path
        model.start_operation('生成参数楼梯',true)
        begin
          wrapper=model.entities.add_group
          fill(wrapper.entities,plan)
          instance=wrapper.to_component
          instance.name="#{Core::LABELS.fetch(plan['params']['shape'])}楼梯"
          instance.definition.name="LSC #{instance.name}"
          instance.transformation=transformation || Geom::Transformation.translation(point(plan['origin']).to_a)
          stamp(instance,plan)
          model.selection.clear; model.selection.add(instance)
          model.commit_operation
          instance
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def update(model,instance,plan)
        raise '请先退出群组或组件编辑。' if model.active_path
        raise '目标楼梯已删除或不在当前模型顶层。' unless instance&.valid? && instance.model==model && model.entities.include?(instance)
        raise '请先解锁此楼梯。' if instance.locked?
        raise '所选组件不是此插件生成的楼梯。' unless owned?(instance)
        model.start_operation('更新参数楼梯',true)
        begin
          instance.make_unique
          instance.definition.entities.clear!
          fill(instance.definition.entities,plan)
          stamp(instance,plan)
          model.commit_operation
          instance
        rescue StandardError
          model.abort_operation
          raise
        end
      end

      def stamp(instance,plan)
        instance.set_attribute(DICT,'schema',1)
        instance.set_attribute(DICT,'version',VERSION)
        instance.set_attribute(DICT,'params',JSON.generate(plan['params']))
        instance.set_attribute(DICT,'stats',JSON.generate(plan['stats']))
      end

      def owned?(entity)
        entity.is_a?(Sketchup::ComponentInstance) && entity.get_attribute(DICT,'schema')==1
      end
    end
  end
end
