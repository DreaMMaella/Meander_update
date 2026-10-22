// JS-рендеринг UI, markdown, drawer, bootstrap.

const String questHtmlJsUi = r'''
// ===== Markdown =====
function escapeHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
function substituteVars(text) {
  return String(text).replace(/\{([^{}]+)\}/g, function(_, t) {
    var v = resolveInlineToken(t.trim());
    if (v == null) return '';
    if (typeof v === 'object') return JSON.stringify(v);
    return String(v);
  });
}
function renderInline(s) {
  if (!s) return '';
  s = escapeHtml(s);
  s = s.replace(/\[color=#([0-9a-fA-F]{6})\]([\s\S]*?)\[\/color\]/g,
    function(_, h, t){ return '<span style="color:#' + h + '">' + t + '</span>'; });
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, t, u){
    if (u.indexOf('node://') === 0)
      return '<a href="#" data-node="' + encodeURIComponent(u.substring(7)) + '">' + t + '</a>';
    return '<a href="' + u + '" target="_blank" rel="noopener">' + t + '</a>';
  });
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>');
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  return s;
}
function renderMarkdown(text) {
  if (!text) return '';
  text = substituteVars(text);
  var lines = String(text).split('\n');
  var out = [];
  var i = 0;
  while (i < lines.length) {
    var line = lines[i];
    var tr = line.replace(/^\s+/, '');
    if (tr.indexOf('```') === 0) {
      var buf = []; i++;
      while (i < lines.length && lines[i].replace(/^\s+/, '').indexOf('```') !== 0) {
        buf.push(lines[i]); i++;
      }
      i++;
      out.push('<pre>' + escapeHtml(buf.join('\n')) + '</pre>');
      continue;
    }
    if (/^###\s/.test(tr)) out.push('<h3>' + renderInline(tr.replace(/^###\s+/, '')) + '</h3>');
    else if (/^##\s/.test(tr)) out.push('<h2>' + renderInline(tr.replace(/^##\s+/, '')) + '</h2>');
    else if (/^#\s/.test(tr)) out.push('<h1>' + renderInline(tr.replace(/^#\s+/, '')) + '</h1>');
    else if (/^>\s/.test(tr)) {
      var q = [];
      while (i < lines.length && /^>\s?/.test(lines[i].replace(/^\s+/, ''))) {
        q.push(lines[i].replace(/^\s+/, '').replace(/^>\s?/, '')); i++;
      }
      out.push('<blockquote>' + renderInline(q.join('<br>')) + '</blockquote>');
      continue;
    }
    else if (/^(-|\*)\s/.test(tr)) {
      var it = [];
      while (i < lines.length && /^(-|\*)\s/.test(lines[i].replace(/^\s+/, ''))) {
        it.push('<li>' + renderInline(lines[i].replace(/^\s+/, '').replace(/^(-|\*)\s+/, '')) + '</li>');
        i++;
      }
      out.push('<ul>' + it.join('') + '</ul>');
      continue;
    }
    else if (/^\d+\.\s/.test(tr)) {
      var oi = [];
      while (i < lines.length && /^\d+\.\s/.test(lines[i].replace(/^\s+/, ''))) {
        oi.push('<li>' + renderInline(lines[i].replace(/^\s+/, '').replace(/^\d+\.\s+/, '')) + '</li>');
        i++;
      }
      out.push('<ol>' + oi.join('') + '</ol>');
      continue;
    }
    else if (tr === '') out.push('');
    else out.push('<p>' + renderInline(line) + '</p>');
    i++;
  }
  return out.join('\n');
}

// ===== UI =====
var headerTitle = document.getElementById('header-title');
var backBtn = document.getElementById('back-btn');
var menuBtn = document.getElementById('menu-btn');
var drawer = document.getElementById('drawer');
var drawerBackdrop = document.getElementById('drawer-backdrop');
var drawerClose = document.getElementById('drawer-close');
var drawerList = document.getElementById('drawer-list');
var nodeContent = document.getElementById('node-content');
var bgLayer = document.getElementById('bg-layer');

var historyStack = [];
var currentNodeId = null;

function openDrawer(){ drawer.classList.add('open'); drawerBackdrop.classList.add('visible'); }
function closeDrawer(){ drawer.classList.remove('open'); drawerBackdrop.classList.remove('visible'); }
menuBtn.addEventListener('click', openDrawer);
drawerClose.addEventListener('click', closeDrawer);
drawerBackdrop.addEventListener('click', closeDrawer);

backBtn.addEventListener('click', function(){
  if (historyStack.length <= 1) return;
  historyStack.pop();
  var prev = historyStack[historyStack.length - 1];
  showNode(prev, false);
});

function setBackground(resId) {
  if (resId) {
    var url = getResUrl(resId);
    if (url) {
      bgLayer.style.backgroundImage = 'url(' + url + ')';
      return;
    }
  }
  bgLayer.style.backgroundImage = '';
}

function buildDrawer() {
  var html = '';
  (quest.chapters || []).forEach(function(ch){
    html += '<div class="drawer-chapter">' + escapeHtml(ch.name) + '</div>';
    (ch.nodeIds || []).forEach(function(nid){
      var node = NODES[nid];
      if (!node) return;
      var t = node.title || '(без названия)';
      html += '<button class="drawer-node" data-node="' + encodeURIComponent(nid) + '">' + escapeHtml(t) + '</button>';
    });
  });
  drawerList.innerHTML = html;
  drawerList.addEventListener('click', function(ev){
    var btn = ev.target.closest('button[data-node]');
    if (!btn) return;
    var target = decodeURIComponent(btn.getAttribute('data-node'));
    if (NODES[target]) showNode(target, true);
  });
}

function renderItem(it) {
  var triggers = it.scriptTriggers || {};
  var type = it.type;
  if (type === 'text') {
    // Обводку считает Dart (тот же расчёт, что у превью в редакторе). Здесь
    // значение ложится на div.style напрямую, а не в текст атрибута: строка не
    // попадает в HTML-парсер, поэтому ей не нужна экранировка и нечего терять
    // на кавычках. text-shadow наследуется, поэтому одного слоя на контейнере
    // хватает, чтобы контур получили и абзацы, и заголовки, и ссылки markdown.
    var div = document.createElement('div');
    div.className = 'player-text';
    if (it.textShadow) div.style.textShadow = it.textShadow;
    div.setAttribute('data-itemid', it.id || '');
    div.innerHTML = renderMarkdown(it.text || '');
    return div.outerHTML;
  }
  if (type === 'image') {
    var url = it.resId ? getResUrl(it.resId) : null;
    if (url) return '<div class="player-img-wrap"><img loading="lazy" decoding="async" src="' + url + '" alt=""></div>';
    return '';
  }
  if (type === 'audio') {
    var aurl = it.resId ? getResUrl(it.resId) : null;
    if (aurl) return '<div class="player-audio"><audio controls preload="none" src="' + aurl + '"></audio></div>';
    return '';
  }
  if (type === 'button') {
    if (!it.targetNodeId) return '';
    var hasOnPress = triggers.onPress ? ' data-onpress="' + escapeHtml(triggers.onPress) + '"' : '';
    return '<button class="player-btn" data-itemid="' + escapeHtml(it.id || '') + '" data-node="' + encodeURIComponent(it.targetNodeId) + '"' + hasOnPress + '>' + renderInline(substituteVars(it.text || '')) + '</button>';
  }
  if (type === 'input') {
    return '<div class="input-block">' +
      (it.text ? '<div class="player-text">' + renderInline(substituteVars(it.text)) + '</div>' : '') +
      '<input type="text" placeholder="' + escapeHtml(it.placeholderText || '') + '" data-varname="' + escapeHtml(it.variableName || '') + '">' +
      '<button class="input-submit">' + escapeHtml(it.buttonText || 'Готово') + '</button></div>';
  }
  if (type === 'chat') {
    var cls = it.isIncoming ? 'in' : 'out';
    var sender = it.senderName ? '<div class="sender">' + escapeHtml(it.senderName) + '</div>' : '';
    return '<div class="chat ' + cls + '"><div class="bubble">' + sender +
      '<div>' + renderInline(substituteVars(it.text || '')) + '</div></div></div>';
  }
  if (type === 'script') {
    return ''; // невидимая
  }
  if (type === 'row' || type === 'column') {
    var ch = (it.children || []).map(renderItem).join('');
    if (type === 'row') return '<div style="display:flex;gap:10px;flex-wrap:wrap;align-items:flex-start">' + ch + '</div>';
    return ch;
  }
  return '';
}

async function showNode(nodeId, pushHistory) {
  var node = NODES[nodeId];
  if (!node) return;
  currentNodeId = nodeId;
  if (pushHistory) historyStack.push(nodeId);
  else if (historyStack[historyStack.length - 1] !== nodeId) historyStack.push(nodeId);

  closeDrawer();
  backBtn.disabled = historyStack.length <= 1;
  headerTitle.textContent = node.title || (quest.title || '');

  // active in drawer
  Array.prototype.forEach.call(document.querySelectorAll('#drawer-list .drawer-node'), function(b){
    b.classList.toggle('active', decodeURIComponent(b.getAttribute('data-node')) === nodeId);
  });

  // Background priority: node > chapter > quest
  var bgResId = node.backgroundResId;
  if (!bgResId) {
    var ch = (quest.chapters || []).find(function(c){ return c.id === node.chapterId; });
    if (ch && ch.backgroundResId) bgResId = ch.backgroundResId;
  }
  if (!bgResId) bgResId = quest.backgroundResId;
  setBackground(bgResId);

  // Build content
  var items = node.items || [];
  var hasButtons = false;
  var html = '<div class="node-card">';
  if (node.title) html += '<div class="node-title">' + escapeHtml(node.title) + '</div>';

  // Сначала вычисляем видимость каждого item через onAppear-скрипты.
  // Если onAppear возвращает go_to_node — делаем переход сразу.
  for (var i = 0; i < items.length; i++) {
    var it = items[i];
    if (it && it.scriptTriggers && it.scriptTriggers.onAppear) {
      var sid = it.scriptTriggers.onAppear;
      var script = SCRIPTS[sid];
      if (script) {
        // Проверка видимости через первый condition в onAppear-блоке
        var visible = await checkItemVisibility(script, it.id);
        if (!visible) { it._hidden = true; continue; }
        // Выполняем побочные эффекты (assign, table, etc) + возможный go_to
        var transit = await runScript(script, 'onContentAppear', { contentItemId: it.id });
        if (transit) { showNode(transit, true); return; }
      }
    }
  }

  for (var j = 0; j < items.length; j++) {
    var item = items[j];
    if (!item || item._hidden) continue;
    if (item.type === 'button') hasButtons = true;
    html += renderItem(item);
  }

  if (!hasButtons) {
    html += '<div class="ending-banner"><div class="name">' + escapeHtml(node.title || 'Концовка') + '</div></div>';
    if (quest.startNodeId && quest.startNodeId !== nodeId) {
      html += '<div class="player-buttons"><button class="player-btn restart" data-node="' +
        encodeURIComponent(quest.startNodeId) + '">Начать сначала</button></div>';
    }
  }
  html += '</div>';
  nodeContent.innerHTML = html;

  // Bind buttons / inputs / links
  Array.prototype.forEach.call(nodeContent.querySelectorAll('button[data-node], a[data-node]'), function(el){
    el.addEventListener('click', async function(ev){
      ev.preventDefault();
      var onPressScript = el.getAttribute('data-onpress');
      var target = decodeURIComponent(el.getAttribute('data-node'));
      if (onPressScript) {
        var script = SCRIPTS[onPressScript];
        if (script) {
          var r = await runScript(script, 'onPress', { contentItemId: el.getAttribute('data-itemid') });
          if (r) target = r;
        }
      }
      if (NODES[target]) showNode(target, true);
    });
  });
  Array.prototype.forEach.call(nodeContent.querySelectorAll('.input-block'), function(box){
    var input = box.querySelector('input');
    var btn = box.querySelector('button.input-submit');
    if (!input || !btn) return;
    btn.addEventListener('click', function(){
      var name = input.getAttribute('data-varname');
      if (name) setVariable(name, input.value);
    });
  });

  // Прокрутка вверх
  window.scrollTo({ top: 0, behavior: 'instant' });

  // Node-level onNodeEnter из scriptAssetId (если есть)
  if (node.scriptAssetId) {
    var scr = SCRIPTS[node.scriptAssetId];
    if (scr) {
      var transitN = await runScript(scr, 'onNodeEnter');
      if (transitN) { showNode(transitN, true); return; }
    }
  }
}

/** Возвращает true, если первый condition в onAppear возвращает истину
 *  (или conditions нет). */
async function checkItemVisibility(script, contentItemId) {
  var blocks = resolveBlocksToRun(script.blocks || [], 'onContentAppear', { contentItemId: contentItemId });
  if (!blocks.length) {
    // Если нет фильтра по contentItem, но скрипт привязан к onAppear триггеру
    // — пробуем без фильтра.
    blocks = resolveBlocksToRun(script.blocks || [], 'onContentAppear', {});
  }
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    if (b && (b.type === 'condition' || b.type === 'условие')) {
      return evalCondition(b);
    }
  }
  return true;
}

// ===== Bootstrap =====
buildDrawer();
(async function boot() {
  // Скрипты запуска квеста: движок сам находит их в scripts/ по объявленному
  // событию «При запуске квеста», реестра в конфиге больше нет. Один раз, до
  // первой ноды; переход последнего важнее startNodeId — как в движке.
  var startTarget = null;
  var bootScripts = quest.startScripts || [];
  for (var i = 0; i < bootScripts.length; i++) {
    var scr = SCRIPTS[normalizeScriptId(bootScripts[i])];
    if (!scr) continue;
    var t = await runScript(scr, 'onQuestStart');
    var tid = t != null ? String(t).trim() : '';
    if (tid && NODES[tid]) startTarget = tid;
  }

  var startId = startTarget || (quest.startNodeId && NODES[quest.startNodeId] ? quest.startNodeId : null);
  if (!startId) {
    // если стартовая не определена — первую ноду первой главы
    var firstCh = (quest.chapters || [])[0];
    if (firstCh && firstCh.nodeIds && firstCh.nodeIds[0]) startId = firstCh.nodeIds[0];
  }
  if (startId) {
    showNode(startId, true);
  } else {
    nodeContent.innerHTML = '<div class="node-card"><div class="player-text">Квест не содержит нод.</div></div>';
  }
})();
''';
