/* All geometry is computed by Ruby Core. JavaScript only presents it. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const form = $('form');
  const state = {connected:false, params:{}, styles:[], target:null, revision:0, plan:null, busy:false, view:'iso', yaw:-.65, pitch:.48, timer:null};
  const names = {straight:'直跑楼梯', I:'双跑直梯', L:'L 型楼梯', U:'U 型楼梯'};
  const fmt = n => Number.isFinite(n) ? String(Math.round(n * 10) / 10) : '—';
  function call(action, payload) {
    if (state.connected) {
      if (payload===undefined) window.sketchup[action]();
      else window.sketchup[action](payload);
    }
  }
  function message(text, error=false) {
    $('notice').textContent=text;
    $('notice').classList.toggle('error', error);
    $('notice').hidden=!text;
  }
  function setParams(params) {
    state.params=structuredCloneSafe(params);
    for (const field of form.elements) {
      if (field.name && params[field.name] !== undefined) field.value=String(params[field.name]);
    }
    syncControls();
  }
  function structuredCloneSafe(value) { return JSON.parse(JSON.stringify(value)); }
  const diagrams = {
    standard:'M5 29h8v-6h8v-6h8v-6h8 M5 33h12v-6h8v-6h8v-6h4',
    solid:'M5 29h8v-6h8v-6h8v-6h8v24H5Z',
    waist:'M5 29h8v-6h8v-6h8v-6h8v6L5 35Z',
    open:'M5 29h10v3H5Zm8-7h10v3H13Zm8-7h10v3H21Zm8-7h10v3H29Z',
    twin:'M5 29h10m-2-7h10m-2-7h10m-2-7h10 M5 35l31-23m-27 25 31-23',
    spine:'M5 29h10m-2-7h10m-2-7h10m-2-7h10 M9 34l26-19 3 4-26 19Z'
  };
  function renderStyles(styles) {
    state.styles=styles;
    $('style-picker').replaceChildren();
    for (const style of styles) {
      const button=document.createElement('button');
      button.type='button'; button.dataset.style=style.id; button.title=style.description;
      button.innerHTML=`<svg viewBox="0 0 44 42" aria-hidden="true"><path d="${diagrams[style.id] || diagrams.standard}"/></svg>`;
      const label=document.createElement('span'); label.textContent=style.name; button.append(label);
      button.addEventListener('click',() => {
        if (!state.connected) {
          const example=window.LSC_STAIRS_DEMO?.style_examples?.[style.id];
          if (example) {setParams(example.params);showPlan(example);}
          return;
        }
        try { state.params=readForm(); } catch (_) {}
        setParams({...state.params,...style.params,style:style.id}); invalidate();
      });
      $('style-picker').append(button);
    }
  }
  function syncControls() {
    document.querySelectorAll('[data-shape]').forEach(b => b.setAttribute('aria-pressed',String(b.dataset.shape===state.params.shape)));
    document.querySelectorAll('[data-mode]').forEach(b => b.setAttribute('aria-pressed',String(b.dataset.mode===state.params.mode)));
    $('gap-row').hidden=state.params.shape!=='U';
    $('landing-row').hidden=state.params.shape==='straight';
    $('turn-row').hidden=!['L','U'].includes(state.params.shape);
    $('rail-fields').hidden=state.params.rails==='none';
    $('beam-fields').hidden=!['twin','spine'].includes(state.params.style);
    document.querySelectorAll('[data-style]').forEach(b => b.setAttribute('aria-pressed',String(b.dataset.style===state.params.style)));
    const preset=state.styles.find(s=>s.id===state.params.style);
    if (preset) {
      const modified=Object.entries(preset.params).some(([key,value])=>state.params[key]!==value);
      $('style-description').textContent=preset.description+(modified ? ' 已自定义尺寸。' : '');
    }
    $('endpoint-controls').hidden=state.params.mode!=='endpoints';
    form.elements.rise.disabled=!state.connected || state.params.mode==='endpoints';
    $('update-note').hidden=!state.target;
    $('target').hidden=!state.target;
    $('target').textContent=state.target ? `正在编辑 · ${state.target}` : '';
    $('apply').textContent=state.target ? '更新所选楼梯' : state.params.mode==='endpoints' ? '生成楼梯' : '放置楼梯';
    $('apply').disabled=!state.connected || !state.plan || state.busy;
    $('pick').disabled=!state.connected || !!state.target;
    if (state.params.lower && state.params.upper) {
      $('endpoint-info').textContent=`下方 ${fmt(state.params.lower.point[2])} → 上方 ${fmt(state.params.upper.point[2])} mm`;
    } else $('endpoint-info').textContent='依次捕捉两个落点，使用实际标高。';
  }
  function readForm() {
    const params={...state.params};
    let valid=true;
    for (const field of form.elements) {
      if (!field.name) continue;
      if (field.type==='number') {
        const bad=!field.disabled && !field.checkValidity();
        field.setAttribute('aria-invalid',String(bad));
        if (bad) valid=false;
        params[field.name]=Number(field.value);
      } else params[field.name]=field.name==='left' ? field.value==='true' : field.value;
    }
    if (!valid) throw new Error('请检查标红的参数，填写有效尺寸。');
    return params;
  }
  function invalidate() {
    state.plan=null; state.revision++;
    $('apply').disabled=true;
    $('preview-status').textContent='重新计算…';
    clearTimeout(state.timer);
    if (!state.connected) return;
    call('stop_preview');
    state.timer=setTimeout(() => {
      try {
        state.params=readForm(); syncControls();
        call('preview',{params:state.params,revision:state.revision,model_preview:$('model-preview').checked});
      } catch (error) {
        message(error.message,true); $('preview-status').textContent='参数需要调整';
        $('scene').replaceChildren();
      }
    },140);
  }
  function showPlan(plan) {
    state.plan=plan;
    $('stat-count').textContent=plan.stats.count;
    for (const [id,text] of [['stat-riser',fmt(plan.stats.riser)],['stat-tread',plan.stats.treads.map(fmt).join(' / ')]]) {
      $(id).textContent=text;
      const unit=document.createElement('small'); unit.textContent='mm'; $(id).append(unit);
    }
    $('flight-stats').textContent=`${plan.stats.flights.length} 个梯段 · ${plan.stats.flights.join(' + ')} 个踢面`;
    $('comfort').textContent=`2h + b = ${plan.stats.comfort.map(fmt).join(' / ')} mm`;
    const style=state.styles.find(s=>s.id===plan.params.style);
    $('shape-label').textContent=names[plan.params.shape]+(style ? ` · ${style.name}` : '');
    $('warnings').replaceChildren();
    plan.warnings.forEach(text => { const p=document.createElement('p'); p.textContent=text; $('warnings').append(p); });
    $('warnings').hidden=!plan.warnings.length;
    $('preview-status').textContent=state.connected ? '已按当前参数更新' : '示例预览 · 在 SketchUp 内启用编辑';
    $('apply').disabled=!state.connected || state.busy;
    draw();
  }
  window.LSCStairs = {receive(event,data) {
    if (event==='ready') {
      state.connected=true; $('version').textContent=data.version; renderStyles(data.styles || []); setParams(data.params); invalidate();
    } else if (event==='plan') {
      if (data.revision!==state.revision) return;
      message(''); showPlan(data);
    } else if (event==='loaded') {
      state.target=data.name || '楼梯'; setParams(data.params); message('已读取参数。修改后点击“更新所选楼梯”。'); invalidate();
    } else if (event==='target') {
      state.target=data.name; syncControls();
    } else if (event==='endpoints') {
      state.params={...state.params,...data,mode:'endpoints',rise:data.upper.point[2]-data.lower.point[2]};
      setParams(state.params); invalidate();
    } else if (event==='reset') {
      state.target=null; state.busy=false; setParams(data.params); message(data.text); invalidate();
    } else if (event==='error') {
      if (data.revision != null && data.revision!==state.revision) return;
      state.busy=false; state.plan=null; $('scene').replaceChildren();
      message(data.text,true); $('preview-status').textContent='请调整参数后重试'; syncControls();
    } else if (event==='notice') message(data.text);
    else if (event==='applied') { state.busy=false; syncControls(); }
  }};
  form.addEventListener('submit',e => e.preventDefault());
  form.addEventListener('input',() => { try { state.params=readForm(); syncControls(); } catch (_) {} invalidate(); });
  document.querySelectorAll('[data-shape],[data-mode]').forEach(button => button.addEventListener('click',() => {
    if (!state.connected) return;
    if (button.dataset.shape) state.params.shape=button.dataset.shape;
    if (button.dataset.mode) state.params.mode=button.dataset.mode;
    syncControls(); invalidate();
  }));
  $('read').addEventListener('click',() => { clearTimeout(state.timer); state.revision++; call('read'); });
  $('reset').addEventListener('click',() => { clearTimeout(state.timer); state.revision++; call('cancel'); });
  $('pick').addEventListener('click',() => {
    clearTimeout(state.timer); state.revision++; state.plan=null;
    delete state.params.lower; delete state.params.upper;
    syncControls(); call('pick');
  });
  $('model-preview').addEventListener('change',invalidate);
  $('apply').addEventListener('click',() => {
    try {
      const params=readForm(); state.busy=true; syncControls();
      call('apply',{params,update:!!state.target,revision:state.revision});
    } catch(error) { state.busy=false; message(error.message,true); syncControls(); }
  });
  document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click',() => {
    state.view=button.dataset.view;
    document.querySelectorAll('[data-view]').forEach(b => b.setAttribute('aria-pressed',String(b===button)));
    $('drag-hint').textContent=state.view==='iso' ? '拖动旋转' : '正投影视图'; draw();
  }));
  let drag=null;
  $('preview').addEventListener('pointerdown',e => {
    if (state.view!=='iso') return;
    drag={x:e.clientX,y:e.clientY,yaw:state.yaw,pitch:state.pitch}; $('preview').setPointerCapture(e.pointerId);
  });
  $('preview').addEventListener('pointermove',e => {
    if (!drag) return;
    state.yaw=drag.yaw+(e.clientX-drag.x)/180;
    state.pitch=Math.max(.12,Math.min(1.3,drag.pitch+(e.clientY-drag.y)/250)); draw();
  });
  $('preview').addEventListener('pointerup',() => {drag=null;});
  $('preview').addEventListener('pointercancel',() => {drag=null;});

  function draw() {
    const plan=state.plan; if (!plan) return;
    const yaw=state.view==='iso' ? state.yaw : 0;
    const pitch=state.view==='plan' ? Math.PI/2 : state.view==='side' ? 0 : state.pitch;
    const c=Math.cos(yaw),s=Math.sin(yaw),sp=Math.sin(pitch),cp=Math.cos(pitch);
    const project=p => { const y=p[0]*s+p[1]*c; return [p[0]*c-p[1]*s,y*sp-p[2]*cp,y*cp+p[2]*sp]; };
    const raw=[],faces=[];
    for (const box of plan.boxes) {
      const vertices=[box.bottom,box.top].flatMap(z => box.corners.map(p => project([...p,z])));
      raw.push(...vertices);
      const indices=[[0,1,2,3],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7]];
      indices.forEach((ii,i) => {
        const points=ii.map(k=>vertices[k]);
        faces.push({points,depth:points.reduce((n,p)=>n+p[2],0)/4,fill:['#d5d9df','#e1e5eb','#cbd1d9','#d3d9e1','#e8ecf1','#ffffff'][i]});
      });
    }
    for (const mesh of plan.meshes || []) {
      const vertices=mesh.vertices.map(project); raw.push(...vertices);
      mesh.faces.forEach((indices,i) => {
        const points=indices.map(k=>vertices[k]);
        faces.push({points,depth:points.reduce((n,p)=>n+p[2],0)/points.length,fill:i<2 ? '#e1e5eb' : '#f8fafc'});
      });
    }
    const rails=plan.rails.map(r => { const points=[project(r.a),project(r.b)]; raw.push(...points); return {points,depth:(points[0][2]+points[1][2])/2,rail:true}; });
    const xs=raw.map(p=>p[0]),ys=raw.map(p=>p[1]);
    if (!raw.length) return;
    const minX=Math.min(...xs),maxX=Math.max(...xs),minY=Math.min(...ys),maxY=Math.max(...ys);
    const scale=Math.min(540/Math.max(maxX-minX,1),350/Math.max(maxY-minY,1));
    const at=p => [320+(p[0]-(minX+maxX)/2)*scale,220+(p[1]-(minY+maxY)/2)*scale];
    const groundZ=-plan.params.thickness;
    const centerX=(minX+maxX)/2, span=Math.max(maxX-minX,maxY-minY,3000);
    let markup='';
    // A sparse dimensional ground grid uses the same projection as the model.
    for (let i=-4;i<=4;i++) {
      const y=i*span/6;
      for (const pair of [[[centerX-span,y,groundZ],[centerX+span,y,groundZ]],[[centerX+y,-span,groundZ],[centerX+y,span,groundZ]]]) {
        const [a,b]=pair.map(p=>at(project(p)));
        markup+=`<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" stroke="#e5e7ec" stroke-width=".65"/>`;
      }
    }
    [...faces,...rails].sort((a,b)=>a.depth-b.depth).forEach(face => {
      const points=face.points.map(at);
      if (face.rail) markup+=`<line x1="${points[0][0]}" y1="${points[0][1]}" x2="${points[1][0]}" y2="${points[1][1]}" stroke="#4d7db5" stroke-width="1.8" stroke-linecap="round"/>`;
      else markup+=`<polygon points="${points.map(p=>p.join(',')).join(' ')}" fill="${face.fill}" stroke="#9ca8b7" stroke-width=".6" stroke-linejoin="round"/>`;
    });
    $('scene').innerHTML=markup;
  }
  if (window.sketchup && typeof window.sketchup.ready==='function') {
    state.connected=true; call('ready');
  } else {
    document.body.classList.add('demo');
    const demo=window.LSC_STAIRS_DEMO;
    if (demo) {renderStyles(demo.styles || []);setParams(demo.params);showPlan(demo);}
    [...form.querySelectorAll('input,select,button'),$('read'),$('pick'),$('reset'),$('model-preview')].forEach(el => {if (!el.dataset.style) el.disabled=true;});
  }
})();
