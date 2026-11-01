# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require_relative 'version'
require_relative 'core'
require_relative 'geometry'
require_relative 'tools'

module LSC
  module Stairs
    class << self
      def show(read_selection=false)
        if @dialog
          @dialog.bring_to_front
          handle('read',nil) if read_selection
          return
        end
        @read_on_ready=read_selection
        @bound_model=Sketchup.active_model; @target=nil; @endpoints=nil
        @dialog=UI::HtmlDialog.new(dialog_title:'LSC 楼梯生成器',preferences_key:'LSC_Stairs_Panel_v1',
          scrollable:true,resizable:true,width:1020,height:820,min_width:580,min_height:600,
          style:UI::HtmlDialog::STYLE_DIALOG)
        @dialog.set_file(File.join(__dir__,'ui','index.html'))
        %w[ready preview apply pick read cancel stop_preview].each do |action|
          @dialog.add_action_callback(action) do |_context,payload|
            begin
              handle(action,payload)
            rescue StandardError=>e
              cancel_tool
              send_ui('error',{'text'=>e.message,'revision'=>payload.is_a?(Hash) ? payload['revision'] : nil})
            end
          end
        end
        @dialog.set_on_closed { cancel_tool; @dialog=nil; @target=nil; @endpoints=nil }
        @dialog.show
      end

      def send_ui(event,data)
        @dialog&.execute_script("window.LSCStairs.receive(#{JSON.generate(event)},#{JSON.generate(data)})")
      end

      def ensure_context!
        current=Sketchup.active_model
        if current!=@bound_model
          cancel_tool
          @bound_model=current; @target=nil; @endpoints=nil
          send_ui('reset',{'params'=>Core::DEFAULTS,'text'=>'已切换模型，参数和选中目标已重置。'})
          raise '模型已切换，请检查参数后重试。'
        end
        raise '请先退出群组或组件编辑。' if current.active_path
        current
      end

      def request_params(payload)
        params=payload.fetch('params').dup
        if params['mode']=='endpoints'
          if @target
            saved=JSON.parse(@target.get_attribute(DICT,'params'))
            %w[lower upper].each { |key| params[key]=saved[key] }
          else
            raise '请先点选当前模型中的上下落点。' unless @endpoints
            params['lower']={'point'=>@endpoints[0]}; params['upper']={'point'=>@endpoints[1]}
          end
        end
        params
      end

      def handle(action,payload)
        if action=='ready'
          send_ui('ready',{'version'=>VERSION,'params'=>Core::DEFAULTS,'styles'=>Core.styles})
          if @read_on_ready
            @read_on_ready=false
            handle('read',nil)
          end
          return
        end
        model=ensure_context!
        case action
        when 'preview'
          cancel_tool
          plan=Core.solve(request_params(payload))
          send_ui('plan',plan.merge('revision'=>payload['revision']))
          if payload['model_preview']
            transform=@target ? @target.transformation : Geom::Transformation.translation(Geometry.point(plan['origin']).to_a)
            select_tool(PreviewTool.new(plan,transform))
          end
        when 'apply'
          cancel_tool
          plan=Core.solve(request_params(payload))
          if payload['update']
            raise '先选中楼梯并读取参数。' unless @target
            Geometry.update(model,@target,plan)
            send_ui('notice',{'text'=>'楼梯已原位更新。可通过 SketchUp 撤销恢复。'})
          elsif plan['params']['mode']=='endpoints'
            Geometry.create(model,plan)
            send_ui('notice',{'text'=>'已在点选落点生成楼梯。'})
          else
            send_ui('notice',{'text'=>'回到模型，点击下方接入边缘放置楼梯；Esc 取消。'})
            select_tool(PlacementTool.new(plan,model))
          end
          send_ui('applied',{'revision'=>payload['revision']})
        when 'pick'
          @target=nil; @endpoints=nil
          send_ui('target',{'name'=>nil})
          select_tool(EndpointTool.new(model))
          send_ui('notice',{'text'=>'回到模型，依次点选下、上两个落点；Esc 取消。'})
        when 'read'
          cancel_tool
          raise '请选择一个由本插件生成的顶层楼梯组件。' unless model.selection.length==1
          target=model.selection.first
          raise '请选择一个由本插件生成的顶层楼梯组件。' unless Geometry.owned?(target) && model.entities.include?(target)
          raise '请先解锁此楼梯。' if target.locked?
          params=Core.normalize(JSON.parse(target.get_attribute(DICT,'params')))
          @target=target; @endpoints=nil
          send_ui('loaded',{'params'=>params,'name'=>target.name})
        when 'cancel'
          cancel_tool; @target=nil; @endpoints=nil
          send_ui('reset',{'params'=>Core::DEFAULTS,'text'=>'已返回新建楼梯。'})
        when 'stop_preview'
          cancel_tool
        end
      end

      def select_tool(tool)
        cancel_tool
        model=Sketchup.active_model
        model.select_tool(tool)
        @tool=tool; @tool_model=model
      end

      def tool_deactivated(tool)
        return unless @tool.equal?(tool)
        @tool=nil; @tool_model=nil
      end

      def cancel_tool
        model=@tool_model; tool=@tool
        @tool=nil; @tool_model=nil
        model.select_tool(nil) if tool && model==Sketchup.active_model
      end

      def finish_tool
        cancel_tool
      end

      def accept_endpoints(points)
        @endpoints=points; @target=nil
        send_ui('endpoints',{'lower'=>{'point'=>points[0]},'upper'=>{'point'=>points[1]}})
      end
    end

    unless file_loaded?(__FILE__)
      command=UI::Command.new('LSC 楼梯生成器') { show }
      command.tooltip='LSC 楼梯生成器'
      command.status_bar_text='四种梯型、六种几何样式，平台与扶手。'
      command.small_icon=File.join(__dir__,'icons','stairs.png')
      command.large_icon=command.small_icon
      UI.menu('Extensions').add_item(command)
      toolbar=UI::Toolbar.new('LSC 楼梯生成器'); toolbar.add_item(command); toolbar.restore
      @toolbar=toolbar
      UI.add_context_menu_handler do |menu|
        selection=Sketchup.active_model.selection
        if selection.length==1 && Geometry.owned?(selection.first)
          menu.add_item('编辑楼梯参数…') do
            begin
              show(true)
            rescue StandardError=>e
              send_ui('error',{'text'=>e.message})
            end
          end
        end
      end
      file_loaded(__FILE__)
    end
  end
end
