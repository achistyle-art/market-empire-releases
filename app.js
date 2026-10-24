// MARKET EMPIRE – Website: Sprache, neueste Versionen, Vorschläge, Bildergalerie.
// Versionen und Vorschläge kommen live aus dem öffentlichen Repository über die GitHub-API;
// changelog.json (beim Veröffentlichen aus der README erzeugt) liefert die Beschreibungen.
(() => {
  'use strict';

  const REPO = 'achistyle-art/market-empire-releases';
  const API = `https://api.github.com/repos/${REPO}`;
  const RELEASES_PAGE = `https://github.com/${REPO}/releases`;
  const SHOWN = 6;
  const $ = (id) => document.getElementById(id);

  // ---------------------------------------------------------------- Sprache
  const KEY = 'me.lang';
  const store = {
    get() { try { return localStorage.getItem(KEY); } catch { return null; } },
    set(v) { try { localStorage.setItem(KEY, v); } catch { /* Speicher nicht verfügbar */ } },
  };
  let lang = store.get() || (/^de\b/i.test(navigator.language || 'de') ? 'de' : 'en');
  if (lang !== 'de' && lang !== 'en') lang = 'de';
  const t = (de, en) => (lang === 'en' ? en : de);

  const listeners = [];
  function applyLang(next) {
    lang = next;
    document.documentElement.lang = next;
    document.documentElement.dataset.lang = next;
    document.querySelectorAll('[data-set-lang]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.setLang === next)));
    listeners.forEach((fn) => fn());
  }
  document.querySelectorAll('[data-set-lang]').forEach((b) => b.addEventListener('click', () => { store.set(b.dataset.setLang); applyLang(b.dataset.setLang); }));
  applyLang(lang);

  const fmtDate = (iso) => new Date(iso).toLocaleDateString(t('de-DE', 'en-GB'), { day: 'numeric', month: 'long', year: 'numeric' });
  const fmtSize = (bytes) => `${(bytes / 1048576).toLocaleString(t('de-DE', 'en-GB'), { maximumFractionDigits: 0 })} MB`;
  const el = (tag, props = {}, ...kids) => {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === 'class') n.className = v; else if (k === 'text') n.textContent = v; else n.setAttribute(k, v);
    }
    kids.flat().forEach((k) => k != null && n.append(k));
    return n;
  };

  async function getJson(url) {
    const r = await fetch(url, { headers: { Accept: 'application/vnd.github+json' } });
    if (!r.ok) throw new Error(`${r.status}`);
    return r.json();
  }

  // ---------------------------------------------------------------- Versionen
  const cleanVersion = (tag) => String(tag || '').replace(/^v/i, '');
  const asset = (rel, suffix) => (rel.assets || []).find((a) => a.name.endsWith(suffix));

  let releases = null;   // GitHub-Releases (null: noch nicht geladen, []: keine oder nicht erreichbar)
  let changelog = [];    // [{version, text, items}]
  let showAll = false;

  function renderReceipt() {
    const latest = releases && releases[0];
    if (!latest) return;
    const setup = asset(latest, '-Setup.exe'), zip = asset(latest, '-Windows-x64.zip');
    $('bon-version').textContent = cleanVersion(latest.tag_name);
    $('bon-date').textContent = fmtDate(latest.published_at);
    $('bon-size').textContent = setup ? fmtSize(setup.size) : '–';
    if (setup) { $('bon-setup').href = setup.browser_download_url; $('dl-main').href = setup.browser_download_url; }
    if (zip) $('bon-zip').href = zip.browser_download_url;
  }

  function renderReleases() {
    const list = $('releases');
    const byVersion = new Map(changelog.map((c) => [c.version, c]));
    // Releases mit Beschreibung aus der README; ohne erreichbare API nur die Änderungsliste
    const entries = releases && releases.length
      ? releases.map((r) => ({ version: cleanVersion(r.tag_name), date: r.published_at, rel: r, log: byVersion.get(cleanVersion(r.tag_name)) }))
      : changelog.map((c) => ({ version: c.version, log: c }));
    list.replaceChildren();
    if (!entries.length) {
      list.append(el('li', { class: 'release-empty' }, releases === null ? t('Versionen werden geladen …', 'Loading releases …') : t('Noch keine Versionen veröffentlicht.', 'No releases published yet.')));
      $('more-releases').hidden = true;
      return;
    }
    entries.slice(0, showAll ? entries.length : SHOWN).forEach((e, i) => {
      const head = el('div', { class: 'release-head' },
        el('h3', { text: `Version ${e.version}` }),
        e.date ? el('span', { class: 'release-date', text: fmtDate(e.date) }) : null,
        i === 0 ? el('span', { class: 'badge', text: t('NEU', 'NEW') }) : null);
      const body = [];
      if (e.log) {
        if (e.log.text) body.push(el('p', { text: e.log.text }));
        if (e.log.items && e.log.items.length) body.push(el('ul', {}, e.log.items.map((it) => el('li', { text: it }))));
      } else if (e.rel && e.rel.body) {
        body.push(el('p', { text: e.rel.body.replace(/[#*_`>]/g, '').trim().slice(0, 600) }));
      }
      if (e.rel) {
        const setup = asset(e.rel, '-Setup.exe'), zip = asset(e.rel, '-Windows-x64.zip');
        body.push(el('p', { class: 'release-dl' },
          setup ? el('a', { href: setup.browser_download_url, rel: 'noopener', text: `Setup.exe (${fmtSize(setup.size)})` }) : null,
          zip ? el('a', { href: zip.browser_download_url, rel: 'noopener', text: `${t('Portable ZIP', 'Portable ZIP')} (${fmtSize(zip.size)})` }) : null,
          el('a', { href: e.rel.html_url, rel: 'noopener', text: t('Details auf GitHub', 'Details on GitHub') })));
      }
      list.append(el('li', { class: i === 0 ? 'release latest' : 'release' }, head, body));
    });
    const more = $('more-releases');
    more.hidden = showAll || entries.length <= SHOWN;
  }

  $('more-releases').addEventListener('click', () => { showAll = true; renderReleases(); });

  fetch('changelog.json').then((r) => (r.ok ? r.json() : [])).catch(() => []).then((c) => {
    changelog = Array.isArray(c) ? c : [];
    if (releases !== null || !changelog.length) renderReleases();
  });
  getJson(`${API}/releases?per_page=50`).then((rs) => rs.filter((r) => !r.draft && !r.prerelease)).catch(() => []).then((rs) => {
    releases = rs;
    renderReceipt();
    renderReleases();
  });
  // nach 4 s ohne API-Antwort wenigstens die Änderungsliste zeigen
  setTimeout(() => { if (releases === null && changelog.length) renderReleases(); }, 4000);

  // ---------------------------------------------------------------- Vorschläge
  let ideas = null;

  function renderIdeas() {
    const list = $('idea-list');
    list.replaceChildren();
    if (!Array.isArray(ideas) || !ideas.length) {
      list.append(el('li', { class: 'idea-empty' }, ideas === null ? t('Vorschläge werden geladen …', 'Loading ideas …')
        : ideas === 'error' ? t('Die Liste ist gerade nicht erreichbar – auf GitHub finden Sie alle Vorschläge.', 'The list is unavailable right now – all ideas are on GitHub.')
          : t('Noch keine Vorschläge – machen Sie den Anfang!', 'No ideas yet – be the first!')));
      return;
    }
    ideas.slice(0, 8).forEach((i) => {
      const votes = (i.reactions && i.reactions['+1']) || 0;
      list.append(el('li', {},
        el('span', { class: 'votes', title: t('Stimmen', 'Votes'), text: `👍 ${votes}` }),
        el('span', {},
          el('a', { href: i.html_url, rel: 'noopener', text: i.title.replace(/^\[Vorschlag\]\s*/i, '') }),
          el('span', { class: 'idea-meta', text: `#${i.number} · ${i.comments} ${t(i.comments === 1 ? 'Kommentar' : 'Kommentare', i.comments === 1 ? 'comment' : 'comments')}` }))));
    });
  }

  getJson(`${API}/issues?state=open&per_page=100`)
    .then((is) => is.filter((i) => !i.pull_request && /^\[Vorschlag\]/i.test(i.title)))
    .then((is) => {
      ideas = is.sort((a, b) => ((b.reactions && b.reactions['+1']) || 0) - ((a.reactions && a.reactions['+1']) || 0) || b.comments - a.comments);
      renderIdeas();
    })
    .catch(() => { ideas = 'error'; renderIdeas(); });

  const form = $('idea-form');
  function issueText() {
    const kind = form.querySelector('input[name=kind]:checked').value;
    const title = $('idea-title').value.trim();
    const desc = $('idea-body').value.trim();
    const version = $('idea-version').value.trim();
    const body = [desc, '', '---', `${kind === 'Fehler' ? 'Fehlerbericht' : 'Vorschlag'} über die Website`, version ? `Spielversion: ${version}` : null,
      kind === 'Fehler' ? `Browser/System: ${navigator.userAgent}` : null].filter((x) => x !== null).join('\n');
    return { kind, title, desc, body };
  }
  function check({ title, desc }) {
    const err = $('idea-error');
    const msg = !title ? t('Bitte geben Sie einen Titel ein.', 'Please enter a title.')
      : desc.length < 10 ? t('Bitte beschreiben Sie Ihr Anliegen in ein, zwei Sätzen.', 'Please describe your request in a sentence or two.') : '';
    err.textContent = msg;
    err.hidden = !msg;
    if (msg) (title ? $('idea-body') : $('idea-title')).focus();
    return !msg;
  }
  form.addEventListener('submit', (ev) => {
    ev.preventDefault();
    const x = issueText();
    if (!check(x)) return;
    const url = `https://github.com/${REPO}/issues/new?` + new URLSearchParams({ title: `[${x.kind}] ${x.title}`, body: x.body, labels: x.kind === 'Fehler' ? 'bug' : 'enhancement' });
    window.open(url, '_blank', 'noopener');
  });
  $('idea-copy').addEventListener('click', async () => {
    const x = issueText();
    if (!check(x)) return;
    const text = `[${x.kind}] ${x.title}\n\n${x.body}`;
    const btn = $('idea-copy');
    try { await navigator.clipboard.writeText(text); }
    catch {
      const ta = el('textarea', {}, text); document.body.append(ta); ta.select();
      try { document.execCommand('copy'); } finally { ta.remove(); }
    }
    const old = btn.innerHTML;
    btn.textContent = t('Kopiert ✓', 'Copied ✓');
    setTimeout(() => { btn.innerHTML = old; }, 1800);
  });

  // ---------------------------------------------------------------- Bildergalerie
  const box = $('lightbox');
  document.querySelectorAll('.shot').forEach((b) => b.addEventListener('click', () => {
    const img = b.querySelector('img');
    $('lightbox-img').src = b.dataset.full;
    $('lightbox-img').alt = img.alt;
    if (box.showModal) box.showModal(); else window.open(b.dataset.full, '_blank');
  }));
  $('lightbox-close').addEventListener('click', () => box.close());
  box.addEventListener('click', (e) => { if (e.target === box) box.close(); });

  // Sprachwechsel: dynamische Inhalte neu aufbauen
  listeners.push(() => { renderReceipt(); renderReleases(); renderIdeas(); });
})();
