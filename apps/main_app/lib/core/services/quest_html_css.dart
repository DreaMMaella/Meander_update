// CSS-стили для HTML-плеера квеста.

const String questHtmlCss = r'''
* { box-sizing: border-box; }
html, body {
  margin: 0; padding: 0;
  background: #0B1118;
  color: #DEE5EE;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, system-ui, sans-serif;
  font-size: 16px; line-height: 1.55;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
  overscroll-behavior: contain;
}
body { min-height: 100vh; min-height: 100dvh; }
button { font: inherit; cursor: pointer; }
a { color: #6EC1D7; text-decoration: none; }
a:hover { text-decoration: underline; }

#bg-layer {
  position: fixed; inset: 0; z-index: 0;
  background: #0B1118 center/cover no-repeat;
  transition: background-image 0.3s ease, filter 0.3s ease;
}
#bg-layer::after {
  content: ''; position: absolute; inset: 0;
  background: rgba(11, 17, 24, 0.62);
  pointer-events: none;
}

#app {
  position: relative; z-index: 1;
  display: flex; flex-direction: column;
  min-height: 100vh; min-height: 100dvh;
  max-width: 900px; margin: 0 auto;
  padding: 24px 24px max(24px, env(safe-area-inset-bottom));
  gap: 16px;
}

.card {
  background: rgba(20, 26, 34, 0.78);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 18px;
  box-shadow: 0 8px 30px rgba(0,0,0,0.35);
}

/* Header */
#header { display: flex; align-items: center; gap: 12px; padding: 14px 18px; }
.hdr-btn {
  background: transparent; border: none; color: #C8D0DA;
  font-size: 22px; width: 38px; height: 38px;
  border-radius: 10px;
  display: inline-flex; align-items: center; justify-content: center;
  flex-shrink: 0;
}
.hdr-btn:hover, .hdr-btn:active { background: rgba(255,255,255,0.06); }
.hdr-btn[disabled] { opacity: 0.35; pointer-events: none; }
#header-text { flex: 1; min-width: 0; }
#header-title {
  font-size: 26px; font-weight: 800; color: #F1F5FA;
  letter-spacing: -0.4px; line-height: 1.1;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
#header-sub { font-size: 12px; color: #8E98A4; margin-top: 2px; }

/* Info bar */
#info-bar.info { padding: 12px 18px; font-size: 13px; color: #B0B9C4; line-height: 1.5; }

/* Stage */
#stage { flex: 1; }
#node-content { display: flex; flex-direction: column; gap: 14px; }

.node-card {
  padding: 22px;
  background: rgba(20, 26, 34, 0.78);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
  border: 1px solid rgba(255,255,255,0.06);
  border-radius: 18px;
  display: flex; flex-direction: column; gap: 16px;
}

.node-title {
  font-size: 26px; font-weight: 800; color: #F1F5FA;
  letter-spacing: -0.4px; line-height: 1.15;
}

.player-img-wrap { margin: 0; }
.player-img-wrap img {
  width: 100%; max-height: 60vh; object-fit: cover;
  border-radius: 12px; display: block;
}

.player-text {
  font-size: 17px; line-height: 1.6; color: #DEE5EE;
  word-wrap: break-word; overflow-wrap: break-word;
}
.player-text p { margin: 0 0 10px; }
.player-text p:last-child { margin-bottom: 0; }
.player-text strong { color: #FFFFFF; }
.player-text em { color: #C7CFDA; }
.player-text code {
  background: rgba(255,255,255,0.06);
  padding: 1px 6px; border-radius: 4px;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
  font-size: 0.92em; color: #C792EA;
}
.player-text pre {
  background: rgba(255,255,255,0.04); padding: 12px 14px;
  border-radius: 8px; overflow-x: auto;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
  font-size: 13px; color: #B0BEC5;
}
.player-text h1 { font-size: 26px; font-weight: 800; margin: 18px 0 8px; color: #FFFFFF; }
.player-text h2 { font-size: 22px; font-weight: 700; margin: 16px 0 6px; color: #ECF0F4; }
.player-text h3 { font-size: 18px; font-weight: 700; margin: 14px 0 4px; color: #DCE3EB; }
.player-text ul, .player-text ol { padding-left: 22px; margin: 6px 0; }
.player-text li { margin: 3px 0; }
.player-text blockquote {
  border-left: 3px solid rgba(255,255,255,0.18);
  padding-left: 12px; margin: 10px 0;
  color: #ABB6C2; font-style: italic;
}

.player-buttons { display: flex; flex-direction: column; gap: 12px; margin-top: 4px; }
.player-btn {
  display: block; width: 100%;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.08);
  color: #E6EBF2; border-radius: 14px;
  padding: 16px 18px;
  font-weight: 700; font-size: 15px;
  letter-spacing: 0.04em; text-align: center;
  text-transform: uppercase;
  transition: background 0.15s, transform 0.05s, border-color 0.15s;
}
.player-btn:hover { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.14); }
.player-btn:active { transform: translateY(1px); background: rgba(255,255,255,0.10); }
.player-btn[disabled] { opacity: 0.45; pointer-events: none; }
.player-btn.restart {
  background: rgba(255, 167, 38, 0.08);
  border-color: rgba(255, 167, 38, 0.35);
  color: #FFB74D;
}

.input-block { display: flex; flex-direction: column; gap: 8px; }
.input-block input {
  background: rgba(0,0,0,0.25); color: #E0E6EB;
  border: 1px solid rgba(255,255,255,0.10);
  border-radius: 12px; padding: 12px 14px;
  font-size: 16px; outline: none;
}
.input-block input:focus { border-color: rgba(110, 193, 215, 0.6); }
.input-block button {
  align-self: flex-start;
  background: rgba(255,255,255,0.06); color: #E6EBF2;
  border: 1px solid rgba(255,255,255,0.10);
  border-radius: 10px; padding: 10px 18px;
  font-weight: 600;
}

.chat { display: flex; gap: 8px; }
.chat.out { justify-content: flex-end; }
.chat .bubble {
  max-width: 78%; padding: 10px 12px;
  border-radius: 14px; font-size: 15px;
  line-height: 1.45; word-wrap: break-word;
}
.chat.in .bubble {
  background: rgba(255,255,255,0.06);
  color: #DDE5EC;
  border-bottom-left-radius: 4px;
}
.chat.out .bubble {
  background: #2E8AAA; color: #061015;
  border-bottom-right-radius: 4px;
}
.chat .sender { font-size: 11px; color: #8B98A6; margin-bottom: 2px; }

.player-audio { margin: 4px 0; }
.player-audio audio { width: 100%; }
.audio-label { color: #8B98A6; font-size: 12px; margin-bottom: 4px; }

.ending-banner {
  margin-top: 6px; padding: 14px 16px;
  background: rgba(255,167,38,0.1);
  border: 1px solid rgba(255,167,38,0.3);
  border-radius: 12px; text-align: center;
}
.ending-banner .name { font-weight: 700; color: #FFB74D; }

/* Footer */
#footer.brand {
  display: flex; flex-wrap: wrap;
  align-items: center; justify-content: space-between;
  gap: 12px; padding: 12px 18px;
}
.brand-text { color: #B0B9C4; font-size: 13px; flex: 1 1 280px; }
.brand-links { display: flex; gap: 8px; flex-wrap: wrap; }
.pill {
  display: inline-block; padding: 7px 14px;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 999px;
  color: #DEE5EE; font-size: 12px; font-weight: 600;
  letter-spacing: 0.02em;
  transition: background 0.15s, border-color 0.15s;
}
.pill:hover {
  background: rgba(255,255,255,0.08);
  border-color: rgba(255,255,255,0.14);
  text-decoration: none;
}

/* Drawer */
#drawer {
  position: fixed; top: 0; left: -320px;
  width: 280px; max-width: 84vw; height: 100%;
  background: #131A22; z-index: 30;
  transition: left 0.22s ease;
  border-right: 1px solid rgba(255,255,255,0.06);
  display: flex; flex-direction: column;
}
#drawer.open { left: 0; box-shadow: 4px 0 30px rgba(0,0,0,0.5); }
.drawer-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 16px 18px;
  padding-top: max(16px, env(safe-area-inset-top));
  border-bottom: 1px solid rgba(255,255,255,0.06);
}
.drawer-head strong { color: #F1F5FA; font-size: 15px; }
.drawer-head button {
  background: transparent; border: none; color: #8B98A6;
  font-size: 26px; width: 36px; height: 36px; border-radius: 8px;
}
.drawer-head button:hover { background: rgba(255,255,255,0.04); }
#drawer-list { overflow-y: auto; flex: 1; padding: 8px; }
.drawer-chapter {
  font-size: 11px; font-weight: 800; color: #6EC1D7;
  padding: 10px 8px 6px;
  text-transform: uppercase; letter-spacing: 0.07em;
}
.drawer-node {
  display: block; background: transparent; border: none;
  color: #C3CCD6; text-align: left; width: 100%;
  padding: 9px 10px; border-radius: 8px; font-size: 14px;
}
.drawer-node:hover { background: rgba(255,255,255,0.04); }
.drawer-node.active {
  background: rgba(110, 193, 215, 0.10);
  color: #6EC1D7; font-weight: 600;
}
#drawer-backdrop {
  position: fixed; inset: 0;
  background: rgba(0,0,0,0.55); z-index: 20;
  opacity: 0; pointer-events: none;
  transition: opacity 0.22s ease;
}
#drawer-backdrop.visible { opacity: 1; pointer-events: auto; }

@media (max-width: 520px) {
  #app { padding: 14px 14px max(14px, env(safe-area-inset-bottom)); gap: 12px; }
  #header-title { font-size: 22px; }
  .node-card { padding: 18px 16px; }
  .player-text { font-size: 16px; }
  .player-btn { font-size: 14px; padding: 14px 16px; }
  .brand-text { font-size: 12px; }
  .pill { padding: 6px 12px; font-size: 11px; }
}
''';
