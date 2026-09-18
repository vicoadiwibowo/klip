import os
import json
import uuid
import re
import subprocess
import threading
import requests as http_requests
from flask import Flask, render_template, request, jsonify, send_from_directory, send_file, url_for

app = Flask(__name__)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# ============ KONFIGURASI ============
DOWNLOAD_DIR = os.path.join(BASE_DIR, 'downloads')
CLIP_DIR = os.path.join(BASE_DIR, 'clips')
SRT_DIR = os.path.join(BASE_DIR, 'uploads_srt')
MUSIC_DIR = os.path.join(BASE_DIR, 'uploads_music')
STATE_FILE = os.path.join(BASE_DIR, 'state.json')

for d in (DOWNLOAD_DIR, CLIP_DIR, SRT_DIR, MUSIC_DIR):
    os.makedirs(d, exist_ok=True)

GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', '')
GEMINI_MODEL = 'gemini-2.5-flash'
GEMINI_API_URL = f'https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent'

AUTO_EDIT = True
AUTO_JUMPCUT = True
JUMPCUT_NOISE_DB = -30
JUMPCUT_MIN_SILENCE = 0.6
JUMPCUT_PAD = 0.2

GEMINI_PROMPT = """Anda adalah editor video profesional dengan 15 tahun pengalaman mengedit konten viral untuk Shorts/Reels/TikTok.

Saya akan memberikan transkrip video dalam format SRT. Analisis seluruh isi transkrip ini dan identifikasi momen-momen terbaik untuk dijadikan klip viral.

⚠️ ATURAN PALING UTAMA (WAJIB DIPATUHI, PRIORITAS DI ATAS SEGALANYA):
Klip HARUS mengikuti pembahasan/topik yang sedang dibicarakan sampai benar-benar SELESAI. DILARANG KERAS memotong atau mengakhiri klip sebelum topik itu tuntas dibahas — apapun alasannya, termasuk supaya durasi terlihat pas, ringkas, atau seragam dengan klip lain. Kalau di satu titik pembahasan belum kelar, klip WAJIB dilanjutkan sampai topik itu betul-betul selesai, meskipun jadi jauh lebih panjang dari klip lain.

⚠️ ATURAN DURASI:
- DURASI BEBAS — tidak ada batas minimum maupun maksimum.
- JANGAN pernah memotong klip hanya karena "sudah terlalu panjang". Yang menentukan akhir klip adalah SELESAINYA topik, bukan durasi.
- Klip bisa 15 detik, bisa 3 menit, bisa 5 menit — tidak masalah, selama topiknya tuntas dan memang layak viral.
- Lebih baik klip panjang yang utuh dan tuntas, daripada klip pendek yang terpotong di tengah pembahasan.

KRITERIA MOMEN (urut prioritas):
1. Hook kuat dalam 3 detik pertama
2. Puncak emosi: lucu, mengejutkan, mengharukan, tegang, kontroversial
3. Punchline/reveal — momen "aha" yang bikin ingin re-watch
4. Quote catchy yang gampang dikutip ulang
5. Reaksi natural yang kuat

ATURAN TITIK AWAL & AKHIR KLIP:
- Titik AWAL klip = mulai dari hook/momen kuat (bukan dari basa-basi pembuka).
- Titik AKHIR klip = setelah topik/cerita/poin yang dibicarakan benar-benar tuntas (selesai dijelaskan/dijawab/di-punchline-kan).
- Kalau pembahasan di satu topik berlanjut ke topik baru yang masih nyambung, BOLEH digabung — yang penting akhir klip di titik di mana pembicaraan itu berhenti secara natural.

HINDARI: bagian datar, basa-basi, transisi tanpa aksi, klip yang butuh konteks panjang, memotong di tengah kalimat, dan — yang paling penting — memotong sebelum topik yang dibahas benar-benar selesai.

KETENTUAN TEKNIS:
- Urutkan klip dari yang paling viral ke yang paling rendah
- Klip tidak boleh tumpang tindih
- Sebelum menampilkan hasil, cek ulang tiap klip: apakah pembahasannya sudah benar-benar selesai di timestamp akhir? Kalau belum, majukan timestamp akhirnya sampai topik itu tuntas
- Cek ulang setiap timestamp agar sinkron dengan transkrip

FORMAT OUTPUT (WAJIB PERSIS, TANPA PENJELASAN TAMBAHAN):

Baris pertama tiap klip: mm:ss-mm:ss
Baris kedua: JUDUL: <judul singkat catchy max 60 karakter>
Baris ketiga: HOOK: <hook viral max 80 karakter>
Baris keempat: HASHTAG: <5 hashtag dipisah spasi>
Kosongkan satu baris antar klip.

CONTOH:

00:10-02:35
JUDUL: Reaksi Kaget Lihat Harga iPhone 15
HOOK: Ternyata harganya bikin dompet menjerit
HASHTAG: #iphone15 #review #techtok #gadgetindonesia #viral

05:20-09:10
JUDUL: Perbandingan iPhone 15 vs Samsung S24
HOOK: Siapa yang menang di uji coba ini?
HASHTAG: #samsung #iphone #comparison #techtok #shorts"""

# ============ STATE ============
jobs = {}
videos = {}
clips = {}
active_job_id = None  # job yang sedang berjalan (untuk resume UI)

def save_state():
    try:
        with open(STATE_FILE, 'w', encoding='utf-8') as f:
            json.dump({'videos': videos, 'clips': clips}, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f'save_state error: {e}')

def load_state():
    global videos, clips
    if os.path.isfile(STATE_FILE):
        try:
            with open(STATE_FILE, 'r', encoding='utf-8') as f:
                s = json.load(f)
            videos = s.get('videos', {})
            clips = s.get('clips', {})
        except Exception as e:
            print(f'load_state error: {e}')

    # Sync video folder
    for fn in os.listdir(DOWNLOAD_DIR):
        p = os.path.join(DOWNLOAD_DIR, fn)
        if os.path.isfile(p) and fn not in videos:
            videos[fn] = {
                'path': p,
                'title': os.path.splitext(fn)[0],
                'srt_filename': None,
            }
    for fn in list(videos.keys()):
        if not os.path.isfile(videos[fn].get('path', '')):
            del videos[fn]

    # Sync clip folder
    for fn in os.listdir(CLIP_DIR):
        p = os.path.join(CLIP_DIR, fn)
        if os.path.isfile(p) and fn.endswith('.mp4') and fn not in clips:
            clips[fn] = {'path': p, 'meta': {}}
    for fn in list(clips.keys()):
        if not os.path.isfile(clips[fn].get('path', '')):
            del clips[fn]

    # Cleanup orphan .ass
    for fn in os.listdir(CLIP_DIR):
        if fn.endswith('.ass'):
            mp4 = fn[:-4]
            if not os.path.isfile(os.path.join(CLIP_DIR, mp4)):
                try:
                    os.remove(os.path.join(CLIP_DIR, fn))
                except:
                    pass

    save_state()

# ============ UTIL ============
def parse_ts(ts):
    parts = [float(p) for p in ts.strip().split(':')]
    if len(parts) == 3:
        return parts[0]*3600 + parts[1]*60 + parts[2]
    if len(parts) == 2:
        return parts[0]*60 + parts[1]
    return parts[0]

def probe_square(path, default=1080):
    try:
        r = subprocess.run([
            'ffprobe', '-v', 'error', '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height', '-of', 'csv=p=0', path
        ], capture_output=True, text=True, timeout=20)
        w, h = r.stdout.strip().split(',')
        return min(int(w), int(h))
    except:
        return default

def has_audio(path):
    try:
        r = subprocess.run([
            'ffprobe', '-v', 'error', '-select_streams', 'a:0',
            '-show_entries', 'stream=codec_type', '-of', 'csv=p=0', path
        ], capture_output=True, text=True, check=True)
        return 'audio' in r.stdout.lower()
    except:
        return False

def bitrate_for(sq):
    kbps = int(8000 * (sq / 1080) ** 2)
    kbps = max(2500, min(kbps, 12000))
    return f'{kbps}k'

# ============ SRT PARSER ============
SRT_RE = re.compile(r'(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})')

def parse_srt(path):
    try:
        text = open(path, encoding='utf-8', errors='ignore').read()
    except:
        return []
    entries = []
    for block in re.split(r'\n\s*\n', text.strip()):
        lines = block.strip().splitlines()
        if len(lines) < 2:
            continue
        m, idx = None, 0
        for i, line in enumerate(lines):
            m = SRT_RE.search(line)
            if m:
                idx = i
                break
        if not m:
            continue
        h1,m1,s1,ms1,h2,m2,s2,ms2 = map(int, m.groups())
        start = h1*3600 + m1*60 + s1 + ms1/1000
        end = h2*3600 + m2*60 + s2 + ms2/1000
        txt = '\n'.join(l for l in lines[idx+1:] if l.strip())
        if txt:
            entries.append((start, end, txt))
    return entries

def _fmt_ass(t):
    t = max(0.0, t)
    h = int(t // 3600); t -= h*3600
    m = int(t // 60); t -= m*60
    s = int(t)
    cs = int(round((t-s)*100))
    if cs >= 100: cs = 0; s += 1
    return f'{h:01d}:{m:02d}:{s:02d}.{cs:02d}'

def _esc_ass(t):
    return t.replace('\\','\\\\').replace('{','\\{').replace('}','\\}').replace('\n','\\N')

def build_ass(entries, cs, ce, out_path, sq):
    """Setting subtitle proporsional sesuai standar bot."""
    fontsize = max(22, round(sq * 0.042))
    marginv = round(sq * 0.085)
    margin_lr = round(sq * 0.06)
    outline = max(2, round(sq * 0.0025))
    shadow = 1

    NL = chr(10)
    p = []
    p.append('[Script Info]')
    p.append('ScriptType: v4.00+')
    p.append('PlayResX: ' + str(sq))
    p.append('PlayResY: ' + str(sq))
    p.append('WrapStyle: 0')
    p.append('ScaledBorderAndShadow: yes')
    p.append('')
    p.append('[V4+ Styles]')
    p.append('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding')
    p.append('Style: Default,Arial,' + str(fontsize) + ',&H00FFFFFF,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,1,' + str(outline) + ',' + str(shadow) + ',2,' + str(margin_lr) + ',' + str(margin_lr) + ',' + str(marginv) + ',1')
    p.append('')
    p.append('[Events]')
    p.append('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text')

    count = 0
    for s, e, t in entries:
        if e <= cs or s >= ce:
            continue
        rs = max(s, cs) - cs
        re = min(e, ce) - cs
        if re <= rs:
            continue
        count += 1
        p.append('Dialogue: 0,' + _fmt_ass(rs) + ',' + _fmt_ass(re) + ',Default,,0,0,0,,' + _esc_ass(t))

    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(NL.join(p) + NL)
    return count

def esc_ff(path):
    return path.replace('\\','\\\\').replace(':','\\:').replace("'","\\'")

# ============ FFMPEG PROGRESS ============
def run_ffmpeg(cmd, duration, cb, timeout_sec=900):
    """Jalankan ffmpeg dengan timeout & return (success, stderr)."""
    import time as _t
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            universal_newlines=True, bufsize=1)
    err_lines = []
    def read_err():
        for line in proc.stderr:
            err_lines.append(line)
    th = threading.Thread(target=read_err, daemon=True)
    th.start()
    start_time = _t.time()
    for line in proc.stdout:
        line = line.strip()
        if _t.time() - start_time > timeout_sec:
            try: proc.kill()
            except: pass
            return False, 'TIMEOUT after ' + str(timeout_sec) + 's'
        if line.startswith('out_time_ms='):
            try:
                ms = int(line.split('=')[1])
                pct = int((ms/1_000_000)/duration*100)
                cb(max(0, min(99, pct)))
            except:
                pass
        elif line == 'progress=end':
            cb(100)
    proc.wait()
    th.join(timeout=2)
    return proc.returncode == 0, ''.join(err_lines)[-3000:]

# ============ CUT JOB ============


def detect_silences(video_path, start, duration, noise_db=-30, min_dur=0.6):
    cmd = ['ffmpeg', '-hide_banner', '-nostats',
           '-ss', str(start), '-t', str(duration),
           '-i', video_path,
           '-af', 'silencedetect=noise=' + str(noise_db) + 'dB:d=' + str(min_dur),
           '-f', 'null', '-']
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    except Exception as e:
        print('[silence] err ' + str(e))
        return []
    starts = re.findall(r'silence_start: ([\d.]+)', r.stderr)
    ends = re.findall(r'silence_end: ([\d.]+)', r.stderr)
    out = []
    for i, s in enumerate(starts):
        if i < len(ends):
            out.append((float(s), float(ends[i])))
    return out

def build_jump_ranges(silences, pad=0.2):
    out = []
    for s, e in silences:
        rs = s + pad
        re_ = e - pad
        if re_ > rs + 0.1:
            out.append((rs, re_))
    return out

def build_select_expr(ranges):
    if not ranges:
        return None
    parts = ['between(t,' + str(s) + ',' + str(e) + ')' for s, e in ranges]
    return 'not(' + '+'.join(parts) + ')'

def removed_time_before(t, ranges):
    total = 0.0
    for s, e in ranges:
        if t <= s:
            break
        if t >= e:
            total += e - s
        else:
            total += t - s
    return total

def adjust_entries_for_jumpcut(entries, ranges):
    out = []
    for s, e, text in entries:
        ns = s - removed_time_before(s, ranges)
        ne = e - removed_time_before(e, ranges)
        if ne > ns + 0.05:
            out.append((ns, ne, text))
    return out

def do_cut(job_id, video_path, clips_data, vid, srt_path=None, music_path=None):
    jobs[job_id]['status'] = 'cutting'
    jobs[job_id]['message'] = 'Memotong klip...'
    jobs[job_id]['progress'] = 0
    jobs[job_id]['clip_status'] = []

    sq = probe_square(video_path)
    audio_ok = has_audio(video_path)

    sub_entries = None
    if srt_path and os.path.isfile(srt_path):
        sub_entries = parse_srt(srt_path)

    result = []
    total = len(clips_data)
    for i in range(total):
        jobs[job_id]['clip_status'].append({'index': i+1, 'status': 'pending', 'error': None})

    for i, clip in enumerate(clips_data):
        try:
            s = parse_ts(clip['start'])
            e = parse_ts(clip['end'])
            if e <= s:
                jobs[job_id]['clip_status'][i] = {'index': i+1, 'status': 'error', 'error': 'Timestamp invalid'}
                continue
            dur = e - s
            clip_fn = 'clip_' + vid + '_' + str(i+1) + '.mp4'
            clip_path = os.path.join(CLIP_DIR, clip_fn)

            def cb(pct, idx=i, tot=total):
                overall = ((idx + pct/100.0)/tot) * 100
                jobs[job_id]['progress'] = max(0, min(100, int(overall)))
                jobs[job_id]['message'] = 'Klip ' + str(idx+1) + '/' + str(tot) + ' (' + str(pct) + '%)'

            jump_ranges = []
            select_expr = None
            if AUTO_JUMPCUT:
                jobs[job_id]['message'] = 'Klip ' + str(i+1) + ': deteksi jeda...'
                sil = detect_silences(video_path, s, dur, JUMPCUT_NOISE_DB, JUMPCUT_MIN_SILENCE)
                jump_ranges = build_jump_ranges(sil, JUMPCUT_PAD)
                select_expr = build_select_expr(jump_ranges)
                print('[jumpcut] Klip ' + str(i+1) + ': ' + str(len(jump_ranges)) + ' jeda')

            ass_path = None
            if sub_entries:
                ce_list = []
                for ss, ee, tt in sub_entries:
                    if ee <= s or ss >= e: continue
                    rs = max(ss, s) - s
                    re_ = min(ee, e) - s
                    if re_ <= rs: continue
                    ce_list.append((rs, re_, tt))
                if ce_list:
                    if jump_ranges:
                        ce_list = adjust_entries_for_jumpcut(ce_list, jump_ranges)
                    if ce_list:
                        ass_path = os.path.join(CLIP_DIR, clip_fn + '.ass')
                        n = build_ass(ce_list, 0, dur, ass_path, sq)
                        if n == 0: ass_path = None

            vf_list = ["crop=w='min(iw,ih)':h='min(iw,ih)':x='(iw-min(iw,ih))/2':y='(ih-min(iw,ih))/2'"]
            if select_expr:
                vf_list.append("select='" + select_expr + "'")
                vf_list.append('setpts=N/FRAME_RATE/TB')
            if AUTO_EDIT:
                vf_list.append('eq=brightness=0.03:contrast=1.06:saturation=1.12')
                vf_list.append('fade=t=in:st=0:d=0.4')
                vf_list.append('fade=t=out:st=' + str(max(0.1, dur - 0.4)) + ':d=0.4')
            if ass_path:
                vf_list.append("subtitles='" + esc_ff(ass_path) + "'")
            vf = ','.join(vf_list)

            afilter = None
            if select_expr:
                afilter = "aselect='" + select_expr + "',asetpts=N/SR/TB"

            has_bgm = music_path and os.path.isfile(music_path)
            cmd = ['ffmpeg', '-y', '-ss', str(s), '-t', str(dur), '-i', video_path]
            if has_bgm:
                cmd += ['-stream_loop', '-1', '-i', music_path]

            enc_args = ['-c:v', 'libx264', '-preset', 'veryfast',
                        '-profile:v', 'main', '-level', '4.1',
                        '-b:v', bitrate_for(sq), '-pix_fmt', 'yuv420p']

            if has_bgm:
                vc = '[0:v]' + vf + '[vout]'
                if audio_ok and afilter:
                    ac = '[0:a]' + afilter + ',volume=1.0[ao];[1:a]volume=0.5[ab];[ao][ab]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[aout]'
                elif audio_ok:
                    ac = '[0:a]volume=1.0[ao];[1:a]volume=0.5[ab];[ao][ab]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[aout]'
                else:
                    ac = '[1:a]volume=0.5[aout]'
                cmd += ['-filter_complex', vc + ';' + ac, '-map', '[vout]', '-map', '[aout]']
            else:
                cmd += ['-vf', vf, '-map', '0:v:0', '-map', '0:a:0?']
                if afilter:
                    cmd += ['-af', afilter]

            cmd += enc_args
            cmd += ['-c:a', 'aac', '-b:a', '192k',
                    '-avoid_negative_ts', 'make_zero',
                    '-movflags', '+faststart',
                    '-progress', 'pipe:1', '-nostats',
                    clip_path]

            ok, log = run_ffmpeg(cmd, dur, cb, timeout_sec=900)
            if ok and os.path.isfile(clip_path) and os.path.getsize(clip_path) > 10000:
                result.append({'filename': clip_fn, 'meta': clip.get('meta', {})})
                clips[clip_fn] = {'path': clip_path, 'meta': clip.get('meta', {})}
                save_state()
                jobs[job_id]['clip_status'][i] = {'index': i+1, 'status': 'done', 'error': None}
                print('[OK] Klip ' + str(i+1) + '/' + str(total))
            else:
                err = (log[:300] if log else 'Output invalid')
                jobs[job_id]['clip_status'][i] = {'index': i+1, 'status': 'error', 'error': err}
                print('[ERR] Klip ' + str(i+1) + ': ' + err[:150])
                try:
                    if os.path.isfile(clip_path): os.remove(clip_path)
                except: pass

            if ass_path and os.path.isfile(ass_path):
                try: os.remove(ass_path)
                except: pass

        except Exception as ex:
            jobs[job_id]['clip_status'][i] = {'index': i+1, 'status': 'error', 'error': str(ex)[:300]}
            print('[EXC] Klip ' + str(i+1) + ': ' + str(ex))

    jobs[job_id]['status'] = 'done'
    jobs[job_id]['message'] = 'Selesai!'
    jobs[job_id]['progress'] = 100
    jobs[job_id]['clips'] = result



# ============ YOUTUBE SRT FETCHER ============
YT_SRT_CACHE = {}

def extract_video_id(url):
    patterns = [
        r'(?:youtube\.com/watch\?v=|youtu\.be/|youtube\.com/embed/|youtube\.com/v/)([A-Za-z0-9_-]{11})',
        r'youtube\.com/shorts/([A-Za-z0-9_-]{11})',
    ]
    for p in patterns:
        m = re.search(p, url)
        if m:
            return m.group(1)
    return None

def fetch_youtube_vtt(url, video_id):
    out_tpl = os.path.join(SRT_DIR, video_id)
    for lang in ['id-orig', 'id', 'en']:
        cmd = ['yt-dlp', '--write-auto-subs', '--sub-langs', lang,
               '--skip-download', '--no-part', '-o', out_tpl, url]
        try:
            subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            vtt_path = out_tpl + '.' + lang + '.vtt'
            if os.path.isfile(vtt_path) and os.path.getsize(vtt_path) > 100:
                print('[yt-srt] VTT downloaded: ' + vtt_path)
                return vtt_path, lang
        except Exception as e:
            print('[yt-srt] Error ' + lang + ': ' + str(e))
    return None, None

def clean_srt_file(srt_path):
    """Bersihkan YouTube auto-caption dengan DELTA: hanya tampilkan teks yang BARU diucapkan."""
    try:
        with open(srt_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        print('[clean-srt] Error baca: ' + str(e))
        return 0

    TS_RE = re.compile(r'(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})')

    def ts_sec(t):
        h, m, rest = t.split(':')
        s, ms = rest.split(',')
        return int(h)*3600 + int(m)*60 + int(s) + int(ms)/1000

    def fmt_ts(sec):
        sec = max(0, sec)
        h = int(sec // 3600); sec -= h*3600
        m = int(sec // 60); sec -= m*60
        s = int(sec)
        ms = int(round((sec - s) * 1000))
        if ms >= 1000:
            ms = 0; s += 1
        if s >= 60:
            s = 0; m += 1
        return str(h).zfill(2) + ':' + str(m).zfill(2) + ':' + str(s).zfill(2) + ',' + str(ms).zfill(3)

    # Parse entry
    raw = []
    for block in re.split(r'\n\s*\n', content.strip()):
        lines = block.strip().split('\n')
        if len(lines) < 2:
            continue
        ts_idx = -1
        for i, ln in enumerate(lines):
            if TS_RE.search(ln):
                ts_idx = i
                break
        if ts_idx < 0:
            continue
        m = TS_RE.search(lines[ts_idx])
        text = ' '.join(l.strip() for l in lines[ts_idx+1:] if l.strip())
        if not text:
            continue
        raw.append((ts_sec(m.group(1)), ts_sec(m.group(2)), text))

    if not raw:
        print('[clean-srt] Tidak ada entry valid')
        return 0

    # DELTA MODE: untuk setiap entry, cari teks yang BARU (bukan yang sudah diucapkan)
    final = []
    prev_text = ''
    for s, e, text in raw:
        text = text.strip()
        if not text:
            continue

        # Kalau teks sama persis dengan sebelumnya → skip (bukan baru)
        if text == prev_text:
            # Extend durasi entry terakhir
            if final:
                final[-1] = (final[-1][0], e, final[-1][2])
            continue

        # Hitung delta: teks yang belum ada di prev_text
        if prev_text and text.startswith(prev_text):
            # Kasus umum: teks baru = prev_text + delta
            delta = text[len(prev_text):].strip()
            if delta:
                final.append((s, e, delta))
            prev_text = text
            continue

        # Kalau prev_text adalah prefix dari text (case-sensitive gagal karena spasi dsb)
        # Coba cari kata yang overlap
        prev_words = prev_text.split()
        curr_words = text.split()

        # Cari overlap terpanjang di akhir prev dan awal curr
        overlap = 0
        for k in range(min(len(prev_words), len(curr_words)), 0, -1):
            if prev_words[-k:] == curr_words[:k]:
                overlap = k
                break

        if overlap > 0:
            delta_words = curr_words[overlap:]
            if delta_words:
                delta = ' '.join(delta_words)
                final.append((s, e, delta))
            prev_text = text
            continue

        # Kalau tidak ada overlap, anggap seluruh teks baru
        # Tapi cek dulu: apakah text adalah substring dari prev_text?
        if text in prev_text:
            # Skip, sudah pernah diucapkan
            prev_text = text
            continue

        # Fallback: ini kalimat baru
        final.append((s, e, text))
        prev_text = text

    if not final:
        print('[clean-srt] Delta kosong, fallback ke raw')
        final = raw

    # Tulis ulang SRT
    out = []
    for i, (s, e, t) in enumerate(final, 1):
        out.append(str(i))
        out.append(fmt_ts(s) + ' --> ' + fmt_ts(e))
        out.append(t)
        out.append('')

    try:
        with open(srt_path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(out))
    except Exception as e:
        print('[clean-srt] Error tulis: ' + str(e))
        return 0

    print('[clean-srt] ' + str(len(raw)) + ' raw -> ' + str(len(final)) + ' delta')
    return len(final)

def convert_vtt_to_srt(vtt_path, srt_path):
    cmd = ['ffmpeg', '-y', '-i', vtt_path, srt_path]
    try:
        subprocess.run(cmd, capture_output=True, text=True, timeout=60, check=True)
        if not os.path.isfile(srt_path):
            return False
        # Auto-cleanup duplikat
        clean_srt_file(srt_path)
        return True
    except Exception as e:
        print('[yt-srt] Convert error: ' + str(e))
        return False

def process_existing_job(job_id, video_filename, clips_data, ratio='asli', srt_path=None, music_path=None):
    """Proses klip dari video lokal yang sudah diunduh (untuk Potong Ulang)."""
    info = videos.get(video_filename)
    if not info or not os.path.exists(info['path']):
        jobs[job_id] = {'status': 'error', 'message': 'File tidak ditemukan.',
                        'progress': 0, 'clips': [], 'error': 'File tidak ditemukan.'}
        return

    # AUTO RE-DOWNLOAD SRT kalau hilang
    srt_fn = info.get('srt_filename')
    srt_ok = srt_fn and os.path.isfile(os.path.join(SRT_DIR, srt_fn))

    if not srt_ok and not srt_path:
        source_url = info.get('source_url')
        if source_url:
            vid = extract_video_id(source_url)
            if vid:
                candidate = os.path.join(SRT_DIR, vid + '.srt')
                if os.path.isfile(candidate):
                    srt_path = candidate
                    info['srt_filename'] = vid + '.srt'
                    save_state()
                    print('[process_existing] SRT found: ' + candidate)
                else:
                    print('[process_existing] SRT hilang, re-download...')
                    vtt_path, lang = fetch_youtube_vtt(source_url, vid)
                    if vtt_path:
                        candidate_srt = os.path.join(SRT_DIR, vid + '.srt')
                        if convert_vtt_to_srt(vtt_path, candidate_srt):
                            srt_path = candidate_srt
                            info['srt_filename'] = vid + '.srt'
                            save_state()
                            print('[process_existing] SRT re-downloaded')
        else:
            print('[process_existing] Tidak ada source_url')
    elif not srt_path and srt_fn:
        candidate = os.path.join(SRT_DIR, srt_fn)
        if os.path.isfile(candidate):
            srt_path = candidate

    if srt_path and not os.path.isfile(srt_path):
        srt_path = None

    jobs[job_id] = {'status': 'queued', 'message': 'Menunggu...',
                    'progress': 0, 'clips': [], 'error': None,
                    'clip_status': []}
    do_cut(job_id, info['path'], clips_data,
           os.path.splitext(video_filename)[0], srt_path, music_path)


def download_and_cut(job_id, url, clips_data, srt_path=None, music_path=None, all_clips=None):
    jobs[job_id] = {'status': 'downloading', 'message': 'Mengunduh video...',
                    'progress': 0, 'clips': [], 'error': None}

    vid = uuid.uuid4().hex[:8]
    video_path = os.path.join(DOWNLOAD_DIR, f'{vid}.mp4')

    try:
        proc = subprocess.Popen([
            'yt-dlp',
            '-f', 'bv*[height=1080]+ba/b[height=1080]/bv*[height<=1080]+ba/b[height<=1080]/b',
            '--merge-output-format', 'mp4', '--no-playlist', '-N', '16', '--newline',
            '-o', video_path, url
        ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

        for line in iter(proc.stdout.readline, ''):
            m = re.search(r'\[download\]\s+(\d+(?:\.\d+)?)%', line.strip())
            if m:
                p = float(m.group(1))
                jobs[job_id]['progress'] = int(p)
                jobs[job_id]['message'] = f'Mengunduh video... {int(p)}%'
        proc.wait()

        if proc.returncode != 0:
            jobs[job_id]['status'] = 'error'
            jobs[job_id]['error'] = 'Gagal unduh video.'
            return
    except Exception as ex:
        jobs[job_id]['status'] = 'error'
        jobs[job_id]['error'] = f'Error unduh: {ex}'
        return

    vfn = f'{vid}.mp4'
    videos[vfn] = {
        'path': video_path,
        'title': f'Video {vid}',
        'srt_filename': os.path.basename(srt_path) if srt_path else None,
        'last_clips': all_clips if all_clips else clips_data,
        'last_ratio': '1:1',
        'source_url': url,  # URL YouTube asli untuk re-download SRT
    }
    save_state()
    do_cut(job_id, video_path, clips_data, vid, srt_path, music_path)

# ============ ROUTES ============
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload_srt', methods=['POST'])
def upload_srt():
    if 'file' not in request.files:
        return jsonify({'error': 'Tidak ada file'}), 400
    f = request.files['file']
    if not f.filename or not f.filename.lower().endswith('.srt'):
        return jsonify({'error': 'Hanya .srt'}), 400
    fn = f'{uuid.uuid4().hex[:10]}.srt'
    f.save(os.path.join(SRT_DIR, fn))
    return jsonify({'filename': fn})

@app.route('/upload_music', methods=['POST'])
def upload_music():
    if 'file' not in request.files:
        return jsonify({'error': 'Tidak ada file'}), 400
    f = request.files['file']
    if not f.filename:
        return jsonify({'error': 'Nama kosong'}), 400
    ext = os.path.splitext(f.filename)[1].lower()
    if ext not in ('.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac'):
        return jsonify({'error': 'Format tidak didukung'}), 400
    fn = f'{uuid.uuid4().hex[:12]}{ext}'
    f.save(os.path.join(MUSIC_DIR, fn))
    return jsonify({'filename': fn})

@app.route('/analyze_youtube', methods=['POST'])
def analyze_youtube():
    """Auto-download VTT dari YouTube, analisis dengan Gemini."""
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400
    url = data.get('url', '').strip()
    if not url:
        return jsonify({'error': 'URL kosong'}), 400
    if not GEMINI_API_KEY:
        return jsonify({'error': 'GEMINI_API_KEY belum diset'}), 500

    vid = extract_video_id(url)
    if not vid:
        return jsonify({'error': 'URL YouTube tidak valid'}), 400

    cache = YT_SRT_CACHE.get(vid)
    if cache and os.path.isfile(cache['vtt']):
        vtt_path = cache['vtt']
        srt_path = cache['srt']
        print('[yt-srt] Cache hit: ' + vid)
    else:
        vtt_path, lang = fetch_youtube_vtt(url, vid)
        if not vtt_path:
            return jsonify({'error': 'Video ini tidak punya subtitle otomatis. Upload SRT manual atau pilih video lain.'}), 404
        srt_path = os.path.join(SRT_DIR, vid + '.srt')
        convert_vtt_to_srt(vtt_path, srt_path)
        YT_SRT_CACHE[vid] = {'vtt': vtt_path, 'srt': srt_path, 'created': __import__('time').time()}

    try:
        with open(vtt_path, 'r', encoding='utf-8', errors='ignore') as f:
            vtt_content = f.read()
    except Exception as e:
        return jsonify({'error': 'Gagal baca VTT: ' + str(e)}), 500

    if len(vtt_content) > 500000:
        vtt_content = vtt_content[:500000]

    payload = {
        'contents': [{'parts': [{'text': GEMINI_PROMPT}, {'text': vtt_content}]}],
        'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 8192},
    }
    try:
        r = http_requests.post(GEMINI_API_URL + '?key=' + GEMINI_API_KEY,
                               json=payload, timeout=180)
        if r.status_code != 200:
            return jsonify({'error': 'Gemini HTTP ' + str(r.status_code) + ': ' + r.text[:500]}), 500
        d = r.json()
        analysis = d['candidates'][0]['content']['parts'][0]['text']
    except Exception as e:
        return jsonify({'error': 'Gemini error: ' + str(e)}), 500

    return jsonify({
        'vtt_filename': os.path.basename(vtt_path),
        'srt_filename': os.path.basename(srt_path),
        'video_id': vid,
        'analysis': analysis,
    })

@app.route('/analyze_srt', methods=['POST'])
def analyze_srt():
    if not GEMINI_API_KEY:
        return jsonify({'error': 'GEMINI_API_KEY belum diset. Jalankan: export GEMINI_API_KEY=xxx'}), 500

    srt_fn = None
    srt_path = None

    if 'file' in request.files and request.files['file'].filename:
        f = request.files['file']
        if not f.filename.lower().endswith('.srt'):
            return jsonify({'error': 'Hanya .srt'}), 400
        srt_fn = f'{uuid.uuid4().hex[:10]}.srt'
        srt_path = os.path.join(SRT_DIR, srt_fn)
        f.save(srt_path)
    elif request.form.get('srt_filename'):
        srt_fn = request.form.get('srt_filename')
        srt_path = os.path.join(SRT_DIR, srt_fn)
        if not os.path.isfile(srt_path):
            return jsonify({'error': 'SRT tidak ditemukan'}), 404
    else:
        return jsonify({'error': 'Tidak ada SRT'}), 400

    try:
        with open(srt_path, 'r', encoding='utf-8', errors='ignore') as f:
            srt_content = f.read()
    except Exception as ex:
        return jsonify({'error': f'Baca SRT gagal: {ex}'}), 500

    if len(srt_content) > 500000:
        srt_content = srt_content[:500000]

    payload = {
        'contents': [{'parts': [{'text': GEMINI_PROMPT}, {'text': srt_content}]}],
        'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 8192},
    }

    try:
        r = http_requests.post(f'{GEMINI_API_URL}?key={GEMINI_API_KEY}',
                               json=payload, timeout=180)
        if r.status_code != 200:
            return jsonify({'error': f'Gemini HTTP {r.status_code}: {r.text[:500]}'}), 500
        d = r.json()
        analysis = d['candidates'][0]['content']['parts'][0]['text']
    except http_requests.exceptions.Timeout:
        return jsonify({'error': 'Gemini timeout. Coba lagi.'}), 500
    except Exception as ex:
        return jsonify({'error': f'Gemini error: {ex}'}), 500

    return jsonify({'srt_filename': srt_fn, 'analysis': analysis})

@app.route('/video_history/<filename>')
def video_history(filename):
    """Ambil riwayat klip dari video yang sudah diunduh."""
    info = videos.get(filename)
    if not info:
        return jsonify({'error': 'Video tidak ditemukan'}), 404
    return jsonify({
        'filename': filename,
        'title': info.get('title', filename),
        'has_srt': bool(info.get('srt_filename') and os.path.isfile(os.path.join(SRT_DIR, info.get('srt_filename', '')))),
        'srt_filename': info.get('srt_filename'),
        'last_clips': info.get('last_clips', []),
    })

@app.route('/process_existing', methods=['POST'])
def process_existing():
    """Proses klip dari video yang sudah diunduh (tanpa download ulang)."""
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400

    video_fn = data.get('video_filename')
    clips_data = data.get('clips')
    all_clips = data.get('all_clips')
    srt_fn = data.get('srt_filename')
    music_fn = data.get('music_filename')

    if not video_fn:
        return jsonify({'error': 'video_filename wajib'}), 400
    if not clips_data:
        return jsonify({'error': 'Klip kosong'}), 400

    info = videos.get(video_fn)
    if not info or not os.path.isfile(info['path']):
        return jsonify({'error': 'Video tidak ditemukan'}), 404

    # Update last_clips di metadata
    info['last_clips'] = all_clips if all_clips else clips_data
    save_state()

    srt_path = None
    if srt_fn:
        srt_path = os.path.join(SRT_DIR, srt_fn)
        if not os.path.isfile(srt_path):
            srt_path = None

    music_path = None
    if music_fn:
        music_path = os.path.join(MUSIC_DIR, music_fn)
        if not os.path.isfile(music_path):
            music_path = None

    job_id = uuid.uuid4().hex
    jobs[job_id] = {'status': 'queued', 'message': 'Menunggu...',
                    'progress': 0, 'clips': [], 'error': None,
                    'created': __import__('time').time(),
                    'clip_status': []}
    global active_job_id
    active_job_id = job_id

    # Selalu pakai process_existing_job supaya auto re-download SRT bisa jalan
    t = threading.Thread(target=process_existing_job,
                         args=(job_id, video_fn, clips_data, '1:1', srt_path, music_path))
    t.daemon = True
    t.start()
    return jsonify({'job_id': job_id})

@app.route('/process', methods=['POST'])
def process():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400

    url = data.get('url')
    clips_data = data.get('clips')
    all_clips = data.get('all_clips')  # semua hasil analisis (opsional)
    srt_fn = data.get('srt_filename')
    music_fn = data.get('music_filename')

    if not url:
        return jsonify({'error': 'URL wajib diisi'}), 400
    if not clips_data:
        return jsonify({'error': 'Klip kosong'}), 400

    srt_path = None
    if srt_fn:
        srt_path = os.path.join(SRT_DIR, srt_fn)
        if not os.path.isfile(srt_path):
            return jsonify({'error': 'SRT tidak ditemukan'}), 404

    music_path = None
    if music_fn:
        music_path = os.path.join(MUSIC_DIR, music_fn)
        if not os.path.isfile(music_path):
            return jsonify({'error': 'Musik tidak ditemukan'}), 404

    global active_job_id
    job_id = uuid.uuid4().hex
    jobs[job_id] = {'status': 'queued', 'message': 'Menunggu...',
                    'progress': 0, 'clips': [], 'error': None,
                    'url': url, 'created': __import__('time').time()}
    active_job_id = job_id
    t = threading.Thread(target=download_and_cut,
                         args=(job_id, url, clips_data, srt_path, music_path, all_clips))
    t.daemon = True
    t.start()
    return jsonify({'job_id': job_id})

@app.route('/active_job')
def get_active_job():
    """Cek apakah ada job yang sedang berjalan (untuk resume UI)."""
    global active_job_id
    if not active_job_id or active_job_id not in jobs:
        return jsonify({'active': False})
    job = jobs[active_job_id]
    return jsonify({
        'active': True,
        'job_id': active_job_id,
        'status': job.get('status'),
        'message': job.get('message'),
        'progress': job.get('progress', 0),
        'error': job.get('error'),
        'clips_count': len(job.get('clips', [])),
    })

@app.route('/active_job/clear', methods=['POST'])
def clear_active_job():
    """User sudah lihat hasil, reset active job."""
    global active_job_id
    active_job_id = None
    return jsonify({'success': True})

@app.route('/status/<job_id>')
def status(job_id):
    job = jobs.get(job_id)
    if not job:
        return jsonify({'error': 'Job tidak ditemukan'}), 404
    out = []
    for c in job.get('clips', []):
        fn = c['filename']
        out.append({
            'filename': fn,
            'meta': c.get('meta', {}),
            'download_url': url_for('download_clip', filename=fn, _external=True),
            'stream_url': url_for('stream_clip', filename=fn, _external=True),
        })
    return jsonify({
        'status': job.get('status'),
        'message': job.get('message'),
        'progress': job.get('progress'),
        'clips': out,
        'error': job.get('error'),
    })

@app.route('/files')
def list_files():
    vids = []
    for fn, info in videos.items():
        if os.path.exists(info['path']):
            srt_fn = info.get('srt_filename')
            has_srt = bool(srt_fn and os.path.isfile(os.path.join(SRT_DIR, srt_fn)))
            vids.append({
                'filename': fn,
                'title': info.get('title', fn),
                'stream_url': url_for('stream_video', filename=fn, _external=True),
                'download_url': url_for('download_video', filename=fn, _external=True),
                'has_srt': has_srt,
            })
    cl = []
    for fn, info in clips.items():
        if os.path.exists(info['path']):
            cl.append({
                'filename': fn,
                'meta': info.get('meta', {}),
                'stream_url': url_for('stream_clip', filename=fn, _external=True),
                'download_url': url_for('download_clip', filename=fn, _external=True),
            })
    return jsonify({'videos': vids, 'clips': cl})

@app.route('/delete/clips_batch', methods=['POST'])
def delete_clips_batch():
    """Hapus banyak klip sekaligus. Body: {"filenames": [...]} atau {"all": true}."""
    data = request.get_json() or {}
    deleted = 0
    errors = []

    if data.get('all'):
        # Hapus semua klip
        for fn in list(clips.keys()):
            info = clips[fn]
            try:
                if os.path.isfile(info['path']):
                    os.remove(info['path'])
                del clips[fn]
                deleted += 1
            except Exception as e:
                errors.append(f'{fn}: {e}')
    else:
        filenames = data.get('filenames', [])
        for fn in filenames:
            info = clips.pop(fn, None)
            if not info:
                continue
            try:
                if os.path.isfile(info['path']):
                    os.remove(info['path'])
                deleted += 1
            except Exception as e:
                errors.append(f'{fn}: {e}')

    save_state()
    return jsonify({'success': True, 'deleted': deleted, 'errors': errors})

@app.route('/delete/video/<filename>', methods=['DELETE'])
def delete_video(filename):
    info = videos.pop(filename, None)
    if info:
        try: os.remove(info['path'])
        except: pass
        srt_fn = info.get('srt_filename')
        if srt_fn:
            still = any(v.get('srt_filename') == srt_fn for v in videos.values())
            if not still:
                try: os.remove(os.path.join(SRT_DIR, srt_fn))
                except: pass
        save_state()
        return jsonify({'success': True})
    return jsonify({'error': 'Tidak ditemukan'}), 404

@app.route('/delete/clip/<filename>', methods=['DELETE'])
def delete_clip(filename):
    info = clips.pop(filename, None)
    if info:
        try: os.remove(info['path'])
        except: pass
        save_state()
        return jsonify({'success': True})
    return jsonify({'error': 'Tidak ditemukan'}), 404

@app.route('/download/<filename>')
def download_clip(filename):
    return send_from_directory(CLIP_DIR, filename, as_attachment=True)

@app.route('/stream/<filename>')
def stream_clip(filename):
    return send_file(os.path.join(CLIP_DIR, filename), mimetype='video/mp4', conditional=True)

@app.route('/download_video/<filename>')
def download_video(filename):
    return send_from_directory(DOWNLOAD_DIR, filename, as_attachment=True)

@app.route('/stream_video/<filename>')
def stream_video(filename):
    return send_file(os.path.join(DOWNLOAD_DIR, filename), mimetype='video/mp4', conditional=True)

if __name__ == '__main__':
    load_state()
    print('🎬 AI Video Klip V2 — http://0.0.0.0:5000')
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
