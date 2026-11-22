// The gallery page: reads index.json (the same list livewall uses) and shows it.
// Text from the list is only ever set with textContent, and links are only
// used if they point where they should, so a bad entry can't add code here.
'use strict';

const REPO = 'https://github.com/manndevani/livewall-gallery';
const KIND = { shader: 'Shader', video: 'Video', gif: 'GIF', image: 'Picture' };
const ID_RULE = /^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/;

const $ = (id) => document.getElementById(id);
const grid = $('grid');
const status = $('status');
const search = $('search');
const sort = $('sort');
const detail = $('detail');
let all = [];
let kind = '';

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function ownFile(path) {
  // Files must be ours: w/<id>/<name>, nothing else (no other sites, no "javascript:").
  return typeof path === 'string' && /^w\/[a-z0-9-]+\/[a-z]+\.(hlsl|mp4|gif|png|jpg)$/.test(path) ? path : null;
}

function likeUrl(w) {
  return typeof w.discussion === 'string' && w.discussion.startsWith(REPO + '/discussions/') ? w.discussion : null;
}

function size(bytes) {
  if (!(bytes > 0)) return '';
  if (bytes < 1024 * 1024) return Math.max(1, Math.round(bytes / 1024)) + ' KB';
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}

function likes(w) { return Number.isInteger(w.likes) && w.likes > 0 ? w.likes : 0; }

function card(w) {
  const b = el('button', 'card');
  b.type = 'button';
  b.setAttribute('aria-label', `${w.name} by ${w.author}`);
  const img = el('img');
  if (ownFile(w.preview)) img.src = ownFile(w.preview);
  img.alt = '';
  img.loading = 'lazy';
  img.width = 480;
  img.height = 270;
  const info = el('div', 'info');
  info.append(el('span', 'name', w.name), el('span', 'kind', KIND[w.kind] || ''),
              el('span', 'by', 'by ' + w.author), el('span', 'likes', likes(w) ? '♥ ' + likes(w) : ''));
  b.append(img, info);
  b.addEventListener('click', () => { location.hash = 'w/' + w.id; });
  return b;
}

function show() {
  const q = search.value.trim().toLowerCase();
  let list = all.filter((w) => (!kind || w.kind === kind) &&
    (!q || [w.name, w.author, w.description, ...(w.tags || [])].join(' ').toLowerCase().includes(q)));
  list.sort(sort.value === 'name'
    ? (a, b) => a.name.localeCompare(b.name)
    : (a, b) => likes(b) - likes(a) || a.name.localeCompare(b.name));
  grid.replaceChildren(...list.map(card));
  status.textContent = all.length && !list.length ? 'Nothing matches. Try another word or type.' : '';
}

function open(id) {
  const w = all.find((x) => x.id === id);
  if (!w) { if (detail.open) detail.close(); return; }
  if (ownFile(w.preview)) $('d-img').src = ownFile(w.preview);
  else $('d-img').removeAttribute('src');
  $('d-name').textContent = w.name;
  $('d-name2').textContent = w.name;
  $('d-by').textContent = 'by ' + w.author;
  $('d-desc').textContent = w.description || '';
  $('d-tags').replaceChildren(...(w.tags || []).map((t) => el('span', '', t)));
  $('d-meta').textContent = [KIND[w.kind], size(w.size), w.license + ' license',
                             likes(w) ? likes(w) + (likes(w) === 1 ? ' like' : ' likes') : '']
    .filter(Boolean).join(' · ');
  const file = ownFile(w.file);
  const dl = $('d-download');
  dl.hidden = !file;
  if (file) {
    dl.href = file;
    dl.download = w.name.replace(/[^\w .-]/g, '').trim() + file.slice(file.lastIndexOf('.'));
  }
  const like = $('d-like');
  like.hidden = !likeUrl(w);
  if (likeUrl(w)) like.href = likeUrl(w);
  const src = $('d-source');
  src.hidden = w.kind !== 'shader';
  src.href = `${REPO}/blob/main/wallpapers/${w.id}/wallpaper.hlsl`;
  document.title = w.name + ' · livewall gallery';
  if (!detail.open) detail.showModal();
}

function route() {
  const m = /^#w\/(.+)$/.exec(location.hash);
  if (m && ID_RULE.test(m[1])) open(m[1]);
  else { if (detail.open) detail.close(); document.title = 'livewall gallery'; }
}

detail.addEventListener('close', () => {
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
  document.title = 'livewall gallery';
});
detail.addEventListener('click', (e) => { if (e.target === detail) detail.close(); }); // click outside
window.addEventListener('hashchange', route);
search.addEventListener('input', show);
sort.addEventListener('change', show);
for (const b of document.querySelectorAll('.kinds button')) {
  b.addEventListener('click', () => {
    kind = b.dataset.kind;
    for (const o of document.querySelectorAll('.kinds button')) o.classList.toggle('on', o === b);
    show();
  });
}

fetch('index.json', { cache: 'no-cache' })
  .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); })
  .then((data) => {
    all = (Array.isArray(data.wallpapers) ? data.wallpapers : [])
      .filter((w) => w && ID_RULE.test(w.id) && typeof w.name === 'string' && typeof w.author === 'string' && KIND[w.kind])
      .map((w) => ({ ...w, tags: Array.isArray(w.tags) ? w.tags.filter((t) => typeof t === 'string') : [] }));
    status.textContent = all.length ? '' : 'No wallpapers yet. Be the first to share one!';
    show();
    route();
  })
  .catch(() => { status.textContent = "Couldn't load the gallery list. Please try again in a moment."; });
