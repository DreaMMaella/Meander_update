// JS-движок скриптов: state, expressions, утилиты.

const String questHtmlJsEngine = r'''
// ===== State =====
var quest = null;
try { quest = JSON.parse(document.getElementById('quest-data').textContent); }
catch (e) {
  document.body.innerHTML =
    '<div style="padding:24px;color:#ff6b6b">Не удалось загрузить квест: ' + e + '</div>';
  throw e;
}
var SCRIPTS = quest.scripts || {};
var NODES = quest.nodes || {};

var resCache = {};
function getResUrl(resId) {
  if (!resId) return null;
  if (resCache[resId]) return resCache[resId];
  var el = document.getElementById(resId);
  if (!el) return null;
  var b64 = el.textContent.trim();
  var mime = el.getAttribute('data-mime') || 'application/octet-stream';
  try {
    var bin = atob(b64), len = bin.length, bytes = new Uint8Array(len);
    for (var i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
    var url = URL.createObjectURL(new Blob([bytes], { type: mime }));
    resCache[resId] = url;
    return url;
  } catch (e) { return null; }
}

var state = {
  variables: Object.assign({}, quest.variables || {}),
  tables: {}
};
function getVariable(n) {
  return Object.prototype.hasOwnProperty.call(state.variables, n) ? state.variables[n] : null;
}
function setVariable(n, v) { state.variables[n] = v; }
function getTable(n) { return state.tables[n] || null; }
function setTable(n, t) { state.tables[n] = t; }

// ===== Helpers =====
function toBool(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  if (v == null) return false;
  var s = String(v).trim().toLowerCase();
  if (!s || s === 'null' || s === 'false') return false;
  return true;
}
function toNum(v) {
  if (typeof v === 'number') return v;
  if (typeof v === 'boolean') return v ? 1 : 0;
  if (v == null) return null;
  var n = Number(v); return isNaN(n) ? null : n;
}
function valuesEqual(a, b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) {
    var nn = a == null ? b : a;
    if (typeof nn === 'string') {
      var t = nn.trim().toLowerCase();
      if (!t || ['ничего','nothing','none','null','пусто','нет'].indexOf(t) >= 0) return true;
    }
    return false;
  }
  var an = toNum(a), bn = toNum(b);
  if (an !== null && bn !== null) return an === bn;
  return String(a).trim() === String(b).trim();
}
function stripParens(expr) {
  var e = expr.trim();
  while (e.length > 1 && e.charAt(0) === '(' && e.charAt(e.length - 1) === ')') {
    var depth = 0, wraps = true, inQ = false, qc = '';
    for (var i = 0; i < e.length; i++) {
      var c = e.charAt(i);
      if (inQ) { if (c === qc && e.charAt(i - 1) !== '\\') inQ = false; continue; }
      if (c === "'" || c === '"') { inQ = true; qc = c; continue; }
      if (c === '(') depth++;
      if (c === ')') depth--;
      if (depth === 0 && i < e.length - 1) { wraps = false; break; }
    }
    if (!wraps) break;
    e = e.substring(1, e.length - 1).trim();
  }
  return e;
}
function findTopOp(expr, op) {
  var inQ = false, qc = '', bd = 0, pd = 0;
  for (var i = 0; i <= expr.length - op.length; i++) {
    var c = expr.charAt(i);
    if (inQ) { if (c === qc && expr.charAt(i - 1) !== '\\') inQ = false; continue; }
    if (c === "'" || c === '"') { inQ = true; qc = c; continue; }
    if (c === '[') { bd++; continue; }
    if (c === ']') { bd = Math.max(0, bd - 1); continue; }
    if (c === '(') { pd++; continue; }
    if (c === ')') { pd = Math.max(0, pd - 1); continue; }
    if (bd === 0 && pd === 0 && expr.substr(i, op.length) === op) return i;
  }
  return -1;
}
function compareValues(l, r, op) {
  if (op === '==') return valuesEqual(l, r);
  if (op === '!=') return !valuesEqual(l, r);
  var ln = toNum(l), rn = toNum(r);
  if (ln !== null && rn !== null) {
    if (op === '>') return ln > rn;
    if (op === '<') return ln < rn;
    if (op === '>=') return ln >= rn;
    if (op === '<=') return ln <= rn;
  }
  var ls = String(l == null ? '' : l), rs = String(r == null ? '' : r);
  var cmp = ls.localeCompare(rs);
  if (op === '>') return cmp > 0;
  if (op === '<') return cmp < 0;
  if (op === '>=') return cmp >= 0;
  if (op === '<=') return cmp <= 0;
  return false;
}
function manualDeepLookup(expr) {
  if (!expr) return null;
  var i = 0;
  while (i < expr.length) {
    var c = expr.charAt(i);
    if (c === '[' || c === '.') break;
    i++;
  }
  var baseName = expr.substring(0, i).trim();
  if (!baseName) return null;
  var cur, tbl = getTable(baseName);
  if (tbl) cur = tbl.data;
  else cur = getVariable(baseName);
  if (cur == null) return null;
  while (i < expr.length) {
    var c2 = expr.charAt(i);
    if (c2 === '.') {
      i++;
      var s = i;
      while (i < expr.length && expr.charAt(i) !== '[' && expr.charAt(i) !== '.') i++;
      var key = expr.substring(s, i).trim();
      if (!key) return null;
      if (cur && typeof cur === 'object' && !Array.isArray(cur)) cur = cur[key];
      else return null;
    } else if (c2 === '[') {
      i++;
      var start = i, endIdx = -1, inQ = false, qc = '';
      while (i < expr.length) {
        var cc = expr.charAt(i);
        if (inQ) { if (cc === qc && expr.charAt(i - 1) !== '\\') inQ = false; }
        else {
          if (cc === '"' || cc === "'") { inQ = true; qc = cc; }
          else if (cc === ']') { endIdx = i; break; }
        }
        i++;
      }
      if (endIdx < 0) return null;
      var content = expr.substring(start, endIdx).trim();
      i = endIdx + 1;
      if ((content.charAt(0) === '"' && content.charAt(content.length - 1) === '"') ||
          (content.charAt(0) === "'" && content.charAt(content.length - 1) === "'")) {
        var key2 = content.substring(1, content.length - 1);
        if (cur && typeof cur === 'object' && !Array.isArray(cur)) cur = cur[key2];
        else return null;
      } else {
        var idx = parseInt(content, 10);
        if (!isNaN(idx)) {
          if (Array.isArray(cur) && idx >= 0 && idx < cur.length) cur = cur[idx];
          else return null;
        } else {
          var kv = evalExpr(content);
          if (Array.isArray(cur)) {
            var ii = typeof kv === 'number' ? kv : parseInt(String(kv), 10);
            if (isNaN(ii) || ii < 0 || ii >= cur.length) return null;
            cur = cur[ii];
          } else if (cur && typeof cur === 'object') {
            cur = cur[kv] != null ? cur[kv] : cur[String(kv)];
          } else return null;
        }
      }
    } else {
      if (c2.trim() === '') { i++; continue; }
      return null;
    }
    if (cur == null) return null;
  }
  return cur;
}
function resolveInlineToken(token) {
  if (Object.prototype.hasOwnProperty.call(state.variables, token)) return state.variables[token];
  var t = getTable(token);
  if (t) return t.data;
  return manualDeepLookup(token);
}
function toExprLiteral(v) {
  if (v == null) return 'null';
  if (typeof v === 'number' || typeof v === 'boolean') return String(v);
  return "'" + String(v).replace(/'/g, "\\'") + "'";
}
function resolveInlinePlaceholders(expr) {
  return expr.replace(/\{([^{}]+)\}/g, function(_, token) {
    var t = token.trim();
    if (!t) return 'null';
    var v = resolveInlineToken(t);
    return toExprLiteral(v);
  });
}
function evalArith(expr) {
  try {
    var f = new Function('"use strict"; return (' + expr + ');');
    return f();
  } catch (e) { return null; }
}
// Схлопывание лишних фигурных скобок: {{X}} → {X}, X}} {Y} → X} {Y}.
function normalizeBraces(text) {
  var s = String(text);
  if (s.indexOf('{{') === -1 && s.indexOf('}}') === -1) return s;
  var pos;
  while ((pos = s.indexOf('{{')) !== -1) {
    if (pos + 2 < s.length && s.charAt(pos + 2) === '}') break; // маркер {}
    s = s.substring(0, pos) + s.substring(pos + 1);
  }
  var out = '';
  var i = 0;
  while (i < s.length) {
    if (s.charAt(i) === '}' && s.charAt(i + 1) === '}') {
      var next = s.charAt(i + 2);
      if (i + 2 >= s.length || next === '{' || next === ' ' || next === '\n' || next === '\t') {
        out += '}';
        i += 2;
        continue;
      }
    }
    out += s.charAt(i);
    i++;
  }
  return out;
}
function evalExpr(input) {
  if (input == null) return null;
  var expr = normalizeBraces(input).trim();
  if (!expr) return null;
  var low = expr.toLowerCase();
  if (low === 'null') return null;
  if (low === 'true') return true;
  if (low === 'false') return false;
  expr = stripParens(expr);
  var exact = expr.match(/^\{([^{}]+)\}$/);
  if (exact) {
    var t = exact[1].trim();
    if (t) {
      var r = resolveInlineToken(t);
      if (r != null) return r;
    }
  }
  if (expr.charAt(0) === '!' && expr.substr(0, 2) !== '!=') {
    return !toBool(evalExpr(expr.substring(1)));
  }
  var orPos = findTopOp(expr, '||');
  if (orPos !== -1) {
    var L1 = evalExpr(expr.substring(0, orPos));
    var R1 = evalExpr(expr.substring(orPos + 2));
    return toBool(L1) || toBool(R1);
  }
  var andPos = findTopOp(expr, '&&');
  if (andPos !== -1) {
    var L2 = evalExpr(expr.substring(0, andPos));
    var R2 = evalExpr(expr.substring(andPos + 2));
    return toBool(L2) && toBool(R2);
  }
  var cmps = ['==','!=','>=','<=','>','<'];
  for (var i = 0; i < cmps.length; i++) {
    var op = cmps[i];
    var idx = findTopOp(expr, op);
    if (idx === -1) continue;
    var L = evalExpr(expr.substring(0, idx));
    var R = evalExpr(expr.substring(idx + op.length));
    return compareValues(L, R, op);
  }
  if (expr.indexOf('{') >= 0) {
    expr = resolveInlinePlaceholders(expr);
    var l2 = expr.toLowerCase();
    if (l2 === 'null') return null;
    if (l2 === 'true') return true;
    if (l2 === 'false') return false;
  }
  if (/[+\-*/%]/.test(expr.replace(/^[+\-]/, ''))) {
    var r2 = evalArith(expr);
    if (r2 != null) return r2;
  }
  var deep = manualDeepLookup(expr);
  if (deep != null) return deep;
  var num = Number(expr);
  if (!isNaN(num)) return num;
  if ((expr.charAt(0) === "'" && expr.charAt(expr.length - 1) === "'") ||
      (expr.charAt(0) === '"' && expr.charAt(expr.length - 1) === '"')) {
    return expr.substring(1, expr.length - 1);
  }
  if (expr.indexOf('[') >= 0 || expr.indexOf(']') >= 0) return null;
  return expr;
}
''';
