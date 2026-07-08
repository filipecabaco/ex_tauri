// ------- tabs -------
document.querySelectorAll('.tab').forEach(tab => {
  tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    tab.classList.add('active');
    document.querySelector(`.tab-panel[data-panel="${tab.dataset.tab}"]`).classList.add('active');
  });
});

// ------- copy button -------
document.querySelectorAll('.copy-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    navigator.clipboard.writeText(btn.dataset.copy).then(() => {
      const old = btn.innerHTML;
      btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="#4ade80" stroke-width="2.5" width="16" height="16"><path d="M20 6 9 17l-5-5"/></svg>';
      setTimeout(() => { btn.innerHTML = old; }, 1400);
    });
  });
});

// ------- tiny syntax highlighter -------
function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

function highlightElixir(src) {
  const rules = [
    { re: /#[^\n]*/y, cls: 'tok-com' },
    { re: /"(?:[^"\\]|\\.)*"/y, cls: 'tok-str' },
    { re: /:[a-zA-Z_][a-zA-Z0-9_?!]*|\b[a-zA-Z_][a-zA-Z0-9_?!]*:(?=\s)/y, cls: 'tok-atom' },
    { re: /\b(defmodule|defp?|do|end|fn|use|import|alias|if|else|case|cond|with|for|when|and|or|not|in|true|false|nil|receive|after|raise|try|rescue)\b/y, cls: 'tok-kw' },
    { re: /\b[A-Z][a-zA-Z0-9_]*(?:\.[A-Z][a-zA-Z0-9_]*)*/y, cls: 'tok-mod' },
    { re: /\b\d[\d_]*\b/y, cls: 'tok-num' },
    { re: /\b(handle_event|handle_info|mount|assign|put_flash|connected\?|subscribe|notify|set_tray|set_title|send|open|wrap)(?=\()/y, cls: 'tok-fn' },
    { re: /@[a-zA-Z_][a-zA-Z0-9_]*/y, cls: 'tok-var' },
  ];
  let out = '', i = 0;
  while (i < src.length) {
    let matched = false;
    for (const { re, cls } of rules) {
      re.lastIndex = i;
      const m = re.exec(src);
      if (m && m.index === i) {
        out += `<span class="${cls}">${esc(m[0])}</span>`;
        i += m[0].length;
        matched = true;
        break;
      }
    }
    if (!matched) { out += esc(src[i]); i++; }
  }
  return out;
}

function highlightBash(src) {
  return src.split('\n').map(line => {
    if (/^\s*#/.test(line)) return `<span class="tok-com">${esc(line)}</span>`;
    const m = line.match(/^(\s*)(\S+)(.*)$/);
    if (!m) return esc(line);
    return `${m[1]}<span class="tok-cmd">${esc(m[2])}</span>${esc(m[3])}`;
  }).join('\n');
}

document.querySelectorAll('code.lang-elixir').forEach(el => { el.innerHTML = highlightElixir(el.textContent); });
document.querySelectorAll('code.lang-bash').forEach(el => { el.innerHTML = highlightBash(el.textContent); });
