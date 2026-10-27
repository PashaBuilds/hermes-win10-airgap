#!/usr/bin/env python3
"""Turkish "what's new" notes for an airgap release (stdlib only, Windows/Linux).

Source of the summary, in order:
  1. release-notes/<tag>.md in this repo (hand-curated text), if present;
  2. an OpenAI-compatible chat endpoint, only if the NOTES_LLM_API_KEY secret is set
     (NOTES_LLM_BASE_URL / NOTES_LLM_MODEL repo variables; see release-notes/README.md);
  3. fallback: a short Turkish notice + the upstream English notes verbatim.
Any failure in 1-2 falls through to 3; this script never fails the release because of notes.

Outputs:
  --out-summary  SURUM-NOTLARI-<tag>.md (summary + download/install footer; mail-ready)
  --out-body     full release body = summary block (between markers) + package notes
"""
import argparse, json, os, re, sys, urllib.request, urllib.error

UP = 'NousResearch/hermes-agent'
START, END = '<!-- surum-notlari:start -->', '<!-- surum-notlari:end -->'
TR_MONTHS = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık']
STABLE = re.compile(r'^v(\d+)\.(\d+)\.(\d+)$')


def log(msg):
    print(f'[release_notes] {msg}', file=sys.stderr, flush=True)


def gh(path):
    req = urllib.request.Request('https://api.github.com/' + path.lstrip('/'),
                                 headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'hermes-airgap-notes'})
    tok = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if tok:
        req.add_header('Authorization', f'Bearer {tok}')
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def ver(tag):
    m = STABLE.match(tag or '')
    return tuple(map(int, m.groups())) if m else None


def tr_date(iso):
    from datetime import datetime, timedelta, timezone
    t = datetime.strptime(iso[:19], '%Y-%m-%dT%H:%M:%S').replace(tzinfo=timezone.utc).astimezone(timezone(timedelta(hours=3)))
    return f'{t.day} {TR_MONTHS[t.month - 1]} {t.year}'


def upstream_releases():
    out = []
    for page in range(1, 6):
        rows = gh(f'repos/{UP}/releases?per_page=100&page={page}')
        out += [r for r in rows if not r['draft'] and not r['prerelease'] and ver(r['tag_name'])]
        if len(rows) < 100:
            break
    return sorted(out, key=lambda r: ver(r['tag_name']))


def previous_tag(tag, ups, repo):
    """Base = newest airgap release of this repo older than tag; else previous upstream stable."""
    v = ver(tag)
    try:
        own = [r['tag_name'][len('hermes-'):] for r in gh(f'repos/{repo}/releases?per_page=100')
               if r['tag_name'].startswith('hermes-')]
        own = sorted((t for t in own if ver(t) and ver(t) < v), key=ver)
        if own:
            return own[-1], 'önceki airgap paketi'
    except Exception as e:  # noqa: BLE001
        log(f'own releases lookup failed: {e}')
    older = [r['tag_name'] for r in ups if ver(r['tag_name']) < v]
    return (older[-1] if older else None), 'önceki stabil upstream sürüm'


def commit_subjects(prev, tag, limit=400):
    subs, page = [], 1
    while page <= 5:
        d = gh(f'repos/{UP}/compare/{prev}...{tag}?per_page=100&page={page}')
        for c in d.get('commits', []):
            if len(c.get('parents', [])) == 1:
                subs.append(c['commit']['message'].split('\n', 1)[0])
        if len(d.get('commits', [])) < 100:
            break
        page += 1
    return subs[:limit]


SYSTEM = """Sen Hermes Agent sürüm notlarını Türkçeye aktaran titiz bir teknik yazarsın. Metni bir mühendis, iş arkadaşlarına e-postayla gönderecek.
Kurallar:
- Yalnızca sana verilen upstream sürüm notlarında ve commit başlıklarında AÇIKÇA yazanı anlat. Özellik, sayı, tarih, isim UYDURMA; emin olmadığın şeyi yazma.
- Dil: sade, sıcak, gündelik ama profesyonel Türkçe. Resmî/bürokratik tutanak dili kullanma. Her cümle tam bir fiille bitsin.
- Bilinen İngilizce teknik terimler (CLI, gateway, plugin, MCP, Desktop, commit, PR) İngilizce kalabilir. Komut ve dosya adlarını `kod` biçiminde yaz.
- Biçim (Markdown, başlık seviyesi ###):
  1. Tek paragraf "Kısaca": sürümün türü (yama/ana sürüm) ve kapsamı, notlarda geçen sayılarla.
  2. "### Öne çıkanlar": 4-8 madde. Her madde **kalın kısa başlık** + bunun kullanıcı için ne anlama geldiğini anlatan 1-2 cümle.
  3. "### Küçük düzeltmeler ve iyileştirmeler": konuya göre gruplanmış kısa maddeler (en fazla 10).
- Bağımlılık güvenlik güncellemelerini tek maddede topla. Test, CI, docs, refactor commit'lerini atla.
- İndirme, kurulum ve link bölümü EKLEME; o kısım ayrıca ekleniyor. Giriş başlığı da ekleme.
- Sadece Markdown metnini döndür."""


def llm_summary(tag, prev, notes_blob, subjects):
    key = os.environ.get('NOTES_LLM_API_KEY', '').strip()
    if not key:
        return None, 'NOTES_LLM_API_KEY tanımlı değil'
    base = (os.environ.get('NOTES_LLM_BASE_URL') or 'https://api.openai.com/v1').rstrip('/')
    model = os.environ.get('NOTES_LLM_MODEL') or 'gpt-4.1'
    user = (f'Hermes Agent {prev} → {tag} arasındaki değişiklikler.\n\n=== UPSTREAM SÜRÜM NOTLARI ===\n{notes_blob[:30000]}\n\n'
            f'=== COMMIT BAŞLIKLARI (merge hariç, {len(subjects)} adet) ===\n' + '\n'.join(subjects)[:30000])
    body = json.dumps({'model': model, 'temperature': 0.2,
                       'messages': [{'role': 'system', 'content': SYSTEM}, {'role': 'user', 'content': user}]}).encode()
    req = urllib.request.Request(f'{base}/chat/completions', data=body, method='POST',
                                 headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {key}'})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            text = json.load(r)['choices'][0]['message']['content'].strip()
    except Exception as e:  # noqa: BLE001
        return None, f'model çağrısı başarısız: {type(e).__name__}'
    text = re.sub(r'^```(?:markdown|md)?\s*\n|\n```\s*$', '', text).strip()
    if len(text) < 200 or 'Öne çıkanlar' not in text:
        return None, 'model çıktısı beklenen biçimde değil'
    return text + f'\n\n_Bu özet upstream notları ve commit listesinden yapay zekâ ile ({model}) hazırlandı._', 'ok'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tag', required=True)
    ap.add_argument('--repo', default=os.environ.get('GITHUB_REPOSITORY', 'PashaBuilds/hermes-win10-airgap'))
    ap.add_argument('--package-notes', help='package/zip/install part of the body (markers block is stripped)')
    ap.add_argument('--out-summary', required=True)
    ap.add_argument('--out-body', required=True)
    ap.add_argument('--no-curated', action='store_true', help='ignore release-notes/<tag>.md (testing)')
    a = ap.parse_args()
    tag = a.tag.strip()
    rtag = f'hermes-{tag}'
    zip_name = f'HermesAirgapBundle_{tag}_Win10_Desktop'
    rel_url = f'https://github.com/{a.repo}/releases/tag/{rtag}'
    up_url = f'https://github.com/{UP}/releases/tag/{tag}'

    prev, prev_kind, date, up_body, window = None, '', '', '', []
    try:
        ups = upstream_releases()
        cur = next((r for r in ups if r['tag_name'] == tag), None)
        if cur:
            date, up_body = tr_date(cur.get('published_at') or ''), (cur.get('body') or '').strip()
        prev, prev_kind = previous_tag(tag, ups, a.repo)
        if prev:  # every upstream stable release in (prev, tag], newest first
            window = [r for r in reversed(ups) if ver(prev) < ver(r['tag_name']) <= ver(tag)]
    except Exception as e:  # noqa: BLE001
        log(f'upstream lookup failed: {e}')

    span = f'{prev} → {tag}' if prev else tag
    head = f'## Hermes Agent {span}: bu sürümde neler var?\n\n'
    meta = [f'Upstream yayın tarihi: {date}' if date else None,
            f'karşılaştırma: {prev_kind} {prev}' if prev else None]
    meta = ' · '.join(m for m in meta if m)
    if meta:
        head += f'_{meta}_\n\n'

    summary, source = None, ''
    curated = os.path.join(os.path.dirname(__file__), '..', '..', 'release-notes', f'{tag}.md')
    if not a.no_curated and os.path.isfile(curated):
        summary, source = open(curated, encoding='utf-8').read().strip(), 'curated'
    if summary is None and prev:
        try:
            blob = '\n\n'.join(f"# {r['tag_name']}\n{(r.get('body') or '').strip()}" for r in window) or up_body
            summary, why = llm_summary(tag, prev, blob, commit_subjects(prev, tag))
            source = 'llm' if summary else why
        except Exception as e:  # noqa: BLE001
            source = f'özet girdisi alınamadı: {type(e).__name__}'
    if summary is None:
        log(f'fallback: {source}')
        summary = ('> **Not:** Bu sürüm için Türkçe özet otomatik olarak üretilemedi'
                   + (f' ({source})' if source else '') + '. Aşağıda upstream\'in kendi (İngilizce) sürüm notları yer alıyor; '
                   'Türkçe özet daha sonra eklenebilir.\n\n')
        notes = '\n\n'.join(f"#### {r['tag_name']}\n\n" + re.sub(r'^# Hermes Agent v[^\n]*\n', '', (r.get('body') or '').strip())
                              for r in window) or up_body \
            or f'Upstream notlarına ulaşılamadı: {up_url}'
        notes = re.sub(r'^(#{1,3}) ', '#### ', notes, flags=re.M).replace('<!-- HERMES_BUILDS_TABLE -->', '').strip()
        summary += '<details><summary>Upstream sürüm notları (İngilizce)</summary>\n\n' + notes + '\n\n</details>'
        source = 'fallback'

    links = f'- Upstream sürüm notları: {up_url}\n'
    if prev:
        links += f'- Bütün değişiklikler (commit listesi): https://github.com/{UP}/compare/{prev}...{tag}\n'
    foot = ('\n\n### İndirme ve kurulum\n\n'
            f'- **Paket:** `{zip_name}.zip` (Windows 10 x64, internetsiz kurulum). İndirme sayfası: {rel_url}\n'
            '- **Bütünlük:** Zip\'in yanındaki `.sha256` dosyasıyla aktarımdan sonra SHA256 değerini kontrol edebilirsiniz.\n'
            f'- **Kurulum:** Zip\'i intranetteki makinede `C:\\H4Transfer` altına açın, `{zip_name}` klasöründe önce '
            '`InstallOrUpdateHermesAirgapped.bat Pilot`, ardından `InstallOrUpdateHermesAirgapped.bat Auto CleanVenv` komutunu çalıştırın. '
            'Kurulum önceki sürümü yedekler; sorun olursa `RollbackHermesAirgapped.bat` son kurulumu geri alır.\n'
            + links)
    full = head + summary + foot
    with open(a.out_summary, 'w', encoding='utf-8', newline='\n') as f:
        f.write(full + '\n')

    pkg = ''
    if a.package_notes and os.path.isfile(a.package_notes):
        pkg = open(a.package_notes, encoding='utf-8').read()
        pkg = re.sub(re.escape(START) + r'.*?' + re.escape(END), '', pkg, flags=re.S)
        pkg = re.sub(r'^\s*(---\s*)?(## Paket bilgileri\s*)?', '', pkg).strip()
    body = f'{START}\n{full}\n{END}\n\n---\n\n## Paket bilgileri\n\n{pkg}\n'
    with open(a.out_body, 'w', encoding='utf-8', newline='\n') as f:
        f.write(body)
    log(f'tag={tag} prev={prev} source={source} summary={len(full)} chars body={len(body)} chars')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as f:
            f.write(f'source={source}\nprev={prev or ""}\n')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001  last resort: never block the release
        log(f'unexpected error: {e!r}')
        sys.exit(0)
