#!/usr/bin/env python3
"""Generate and pack three cached Logan Approach controller previews."""

import argparse
import base64
import concurrent.futures
import hashlib
import json
import math
import os
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

API_URL = "https://api.elevenlabs.io/v1/text-to-voice/design"
CREATE_URL = "https://api.elevenlabs.io/v1/text-to-voice"
TTS_URL = "https://api.elevenlabs.io/v1/text-to-speech"
TTS_MODEL = "eleven_turbo_v2_5"
TTS_SETTINGS = {
    "stability": 0.55,
    "similarity_boost": 0.8,
    "speed": 1.08,
}
SAMPLE_RATE = 11025
MAX_REU_SIZE = 16 * 1024 * 1024
VOICE_DESCRIPTION = (
    "An experienced Boston-area air traffic controller in their forties. "
    "Calm, concise, authoritative, and fast but intelligible, with authentic "
    "aviation cadence. Neutral American English with only a very light eastern "
    "Massachusetts coloration. Professional and dry, never an announcer or a caricature."
)
PREVIEW_TEXT = (
    "Cape Air five eighty-two, Boston Approach. Turn left heading two seven zero, "
    "descend and maintain three thousand. Cleared I L S runway two two left."
)
DUNKS_DESCRIPTION = (
    "An ordinary, tired male cargo pilot, age 40-50, with an extremely thick working-class "
    "South Boston accent. Annoyed, amused, and completely deadpan. Natural conversational "
    "pitch through a close cockpit microphone: unpolished, understated, and slightly nasal. "
    "Absolutely not a radio DJ, announcer, commercial voice, booming baritone, or performer. "
    "Make the accent much "
    "stronger than normal speech: very broad Boston vowels, hard non-rhotic R-dropping, "
    "short clipped consonants, and the unmistakable fast Southie rhythm. Boston sounds "
    "like BAW-stin; harder loses its R; youey, wicked, brutal, and Dunks should sound "
    "aggressively local. Clipped aviation-radio cadence, fast but intelligible. This is "
    "an intentionally exaggerated comedy performance, not neutral American English."
)
DUNKS_TEXT = (
    "Boston Approach, Logan seven forty-four heavy. Unable. Traffic's wicked brutal. "
    "Bangin' a youey and headin' to Dunks. Logan seven forty-four heavy."
)
PILOT_DESIGNS = {
    "de_female": {
        "name": "Logan German Pilot",
        "description": (
            "A professional German woman airline pilot in her thirties. Calm, concise, "
            "confident cockpit radio delivery in English with a clear but restrained German "
            "accent. Fast aviation cadence, never theatrical or stereotyped."
        ),
        "text": (
            "Boston Approach, Lufthansa four twenty-three heavy, level one zero thousand. "
            "Right heading two two five, descend and maintain three thousand, "
            "Lufthansa four twenty-three heavy."
        ),
    },
    "br_male": {
        "name": "Logan Brazilian Pilot",
        "description": (
            "A professional Brazilian man airline pilot in his thirties. Warm but disciplined "
            "cockpit radio delivery in English with a natural restrained Brazilian accent. "
            "Fast aviation cadence, never theatrical or stereotyped."
        ),
        "text": (
            "Boston Departure, Air Portugal two eighteen heavy, climbing to seven thousand. "
            "Left heading three one five, climb and maintain one zero thousand, "
            "Air Portugal two eighteen heavy."
        ),
    },
}
RADIO_FILTER = (
    "[0:a]silenceremove=start_periods=1:start_duration=0.02:start_threshold=-50dB,"
    "areverse,silenceremove=start_periods=1:start_duration=0.02:start_threshold=-50dB,"
    "areverse,atempo=1.18,highpass=f=320,lowpass=f=3000,"
    "acompressor=threshold=0.12:ratio=5:attack=3:release=70,"
    "acrusher=bits=10:mix=0.18[s];"
    "anoisesrc=color=white:amplitude=0.016:r=11025:seed=744[n];"
    "[s][n]amix=inputs=2:duration=first:weights='1 0.25',"
    "alimiter=limit=0.85,apad=pad_dur=0.06[out]"
)
AUDITIONS = [
    ("controller", "controller-3-radio.wav"),
    ("german pilot 1", "de_female-1-radio.wav"),
    ("german pilot 2", "de_female-2-radio.wav"),
    ("german pilot 3", "de_female-3-radio.wav"),
    ("brazilian pilot 1", "br_male-1-radio.wav"),
    ("brazilian pilot 2", "br_male-2-radio.wav"),
    ("brazilian pilot 3", "br_male-3-radio.wav"),
]
FINAL_AUDITIONS = [
    ("controller command", "controller.template.turn_left.270"),
    ("american woman", "pilot.us_female.callsign.JBU117"),
    ("southern man", "pilot.us_male.callsign.SWA492"),
    ("british woman", "pilot.uk_female.callsign.ACA765"),
    ("british man", "pilot.uk_male.callsign.BAW212H"),
    ("german woman", "pilot.de_female.callsign.DLH423H"),
    ("indian man", "pilot.in_male.callsign.FDX28H"),
    ("dunks easter egg", "pilot.easter_egg.wicked_brutal"),
]


def load_key(path: Path) -> str:
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not key and path.is_file():
        key = path.read_text().strip()
    if not key:
        raise SystemExit("ELEVENLABS_API_KEY is unset and the key file is empty or missing")
    return key


def request_previews(
    key: str,
    description: str = VOICE_DESCRIPTION,
    text: str = PREVIEW_TEXT,
    model_id: str = "eleven_multilingual_ttv_v2",
) -> dict:
    payload = json.dumps(
        {"voice_description": description, "text": text, "model_id": model_id}
    ).encode()
    request = urllib.request.Request(
        API_URL,
        data=payload,
        headers={"Content-Type": "application/json", "xi-api-key": key},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"ElevenLabs returned HTTP {error.code}: {detail}") from None


def save_voice(
    key: str,
    generated_voice_id: str,
    name: str = "Logan Approach Controller",
    description: str = VOICE_DESCRIPTION,
) -> dict:
    payload = json.dumps(
        {
            "voice_name": name,
            "voice_description": description,
            "generated_voice_id": generated_voice_id,
        }
    ).encode()
    request = urllib.request.Request(
        CREATE_URL,
        data=payload,
        headers={"Content-Type": "application/json", "xi-api-key": key},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"ElevenLabs returned HTTP {error.code}: {detail}") from None


def ffmpeg(source: Path, output: Path, raw: bool = False) -> None:
    command = [
        "ffmpeg", "-y", "-v", "error", "-i", str(source),
        "-filter_complex", RADIO_FILTER, "-map", "[out]",
        "-ar", str(SAMPLE_RATE), "-ac", "1",
    ]
    command += ["-f", "s8"] if raw else ["-c:a", "pcm_s16le"]
    subprocess.run(command + [str(output)], check=True)


def expand_assets(comms: dict) -> list[dict]:
    callsigns = comms["values"]["callsigns"]
    value_sets = {
        "heading": comms["values"]["headings"],
        "altitude": comms["values"]["altitudes"],
        "runway": comms["values"]["runways"],
    }
    assets = []

    def add_voice(
        prefix: str, role: str, voice: dict, phrases: dict, voice_callsigns: list[dict]
    ) -> None:
        if not voice.get("voice_id"):
            raise ValueError(f"missing voice_id for {prefix}")
        common = {
            "role": role,
            "voice_id": voice["voice_id"],
            "voice_name": voice["name"],
        }
        for callsign in voice_callsigns:
            assets.append({
                **common,
                "id": f"{prefix}.callsign.{callsign['id']}",
                "kind": "callsign",
                "text": callsign["spoken"],
            })
        for phrase_id, text in phrases["fixed"].items():
            assets.append({
                **common,
                "id": f"{prefix}.fixed.{phrase_id}",
                "kind": "fixed",
                "text": text,
            })
        for phrase_id, template in phrases["templates"].items():
            fields = [name for name in value_sets if "{" + name + "}" in template]
            if len(fields) != 1:
                raise ValueError(f"template {prefix}.{phrase_id} needs one value field")
            field = fields[0]
            for value in value_sets[field]:
                assets.append({
                    **common,
                    "id": f"{prefix}.template.{phrase_id}.{value['id']}",
                    "kind": "template",
                    "text": template.format(**{field: value["spoken"]}),
                })

    pilot_ids = {voice["id"] for voice in comms["voices"]["pilots"]}
    assigned_ids = {callsign.get("pilot_voice") for callsign in callsigns}
    if assigned_ids != pilot_ids:
        raise ValueError("callsign pilot_voice assignments must cover the pilot roster")

    add_voice(
        "controller", "controller", comms["voices"]["controller"],
        comms["controller"], callsigns
    )
    for voice in comms["voices"]["pilots"]:
        prefix = f"pilot.{voice['id']}"
        voice_callsigns = [
            callsign for callsign in callsigns if callsign["pilot_voice"] == voice["id"]
        ]
        add_voice(prefix, "pilot", voice, comms["pilot"], voice_callsigns)
    easter_voice = comms["voices"]["easter_egg"]
    for phrase_id, text in comms["pilot"].get("easter_eggs", {}).items():
        assets.append({
            "id": f"pilot.easter_egg.{phrase_id}",
            "kind": "easter_egg",
            "role": "pilot",
            "voice_id": easter_voice["voice_id"],
            "voice_name": easter_voice["name"],
            "text": text,
        })

    ids = [asset["id"] for asset in assets]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate generated asset id")
    return assets


def asset_path(root: Path, asset: dict, rendered: bool) -> Path:
    source_key = json.dumps(
        {
            "voice_id": asset["voice_id"],
            "text": asset["text"],
            "model_id": TTS_MODEL,
            "voice_settings": TTS_SETTINGS,
        },
        sort_keys=True,
    )
    if rendered:
        source_key += RADIO_FILTER + str(SAMPLE_RATE)
    digest = hashlib.sha256(source_key.encode()).hexdigest()[:12]
    filename = asset["id"].replace("/", "_") + f".{digest}"
    return root / ("pcm" if rendered else "sources") / (filename + (".pcm" if rendered else ".mp3"))


def synthesize(key: str, asset: dict, output: Path, force: bool) -> None:
    if output.is_file() and not force:
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(
        {
            "text": asset["text"],
            "model_id": TTS_MODEL,
            "voice_settings": TTS_SETTINGS,
        }
    ).encode()
    request = urllib.request.Request(
        f"{TTS_URL}/{asset['voice_id']}",
        data=payload,
        headers={"Content-Type": "application/json", "xi-api-key": key},
        method="POST",
    )
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                data = response.read()
                if not response.headers.get_content_type().startswith("audio/"):
                    raise RuntimeError(f"non-audio response for {asset['id']}")
            temporary = output.with_suffix(output.suffix + ".tmp")
            temporary.write_bytes(data)
            temporary.replace(output)
            return
        except urllib.error.HTTPError as error:
            if error.code != 429 and error.code < 500:
                detail = error.read().decode(errors="replace")
                raise RuntimeError(f"HTTP {error.code} for {asset['id']}: {detail}") from None
            if attempt == 4:
                raise
            time.sleep(min(float(error.headers.get("Retry-After", 2 ** attempt)), 60))


def render_asset(source: Path, output: Path, force: bool) -> None:
    if output.is_file() and not force:
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    ffmpeg(source, temporary, raw=True)
    temporary.replace(output)


def build_bank(raw_files: list[Path], bank_path: Path) -> list[dict]:
    offset = 0
    entries = []
    with bank_path.open("wb") as bank:
        for index, raw_path in enumerate(raw_files, 1):
            data = raw_path.read_bytes()
            bank.write(data)
            entries.append(
                {
                    "id": f"controller-{index}",
                    "offset": offset,
                    "length": len(data),
                    "seconds": round(len(data) / SAMPLE_RATE, 3),
                }
            )
            offset += len(data)
    return entries


def print_estimate(assets: list[dict]) -> None:
    characters = sum(len(asset["text"]) for asset in assets)
    by_role = {
        role: sum(asset["role"] == role for asset in assets)
        for role in ("controller", "pilot")
    }
    print(
        f"{len(assets)} clips ({by_role['controller']} controller, "
        f"{by_role['pilot']} pilot), {characters} billable characters"
    )


def run_parallel(label: str, items: list, worker, workers: int) -> None:
    completed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(worker, item) for item in items]
        for future in concurrent.futures.as_completed(futures):
            future.result()
            completed += 1
            if completed == len(items) or completed % 25 == 0:
                print(f"{label}: {completed}/{len(items)}", flush=True)


def pack_full_bank(assets: list[dict], root: Path, output_dir: Path) -> dict:
    bank_path = output_dir / "logan-comms.reu"
    entries = []
    offset = 0
    with bank_path.open("wb") as bank:
        for asset in assets:
            pcm = asset_path(root, asset, rendered=True).read_bytes()
            if offset + len(pcm) > MAX_REU_SIZE:
                raise RuntimeError(
                    f"REU bank exceeds {MAX_REU_SIZE} bytes at {asset['id']}"
                )
            bank.write(pcm)
            entries.append(
                {
                    **asset,
                    "offset": offset,
                    "length": len(pcm),
                    "seconds": round(len(pcm) / SAMPLE_RATE, 3),
                }
            )
            offset += len(pcm)
    manifest = {
        "sample_rate": SAMPLE_RATE,
        "format": "signed 8-bit mono",
        "bank_size": offset,
        "seconds": round(offset / SAMPLE_RATE, 3),
        "model_id": TTS_MODEL,
        "voice_settings": TTS_SETTINGS,
        "radio_filter": RADIO_FILTER,
        "assets": entries,
    }
    (output_dir / "logan-comms.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def generate_all(key: str, output_dir: Path, force: bool, workers: int) -> None:
    comms = json.loads(Path(__file__).with_name("comms.json").read_text())
    assets = expand_assets(comms)
    print_estimate(assets)
    root = output_dir / "full"

    run_parallel(
        "synthesized",
        assets,
        lambda asset: synthesize(key, asset, asset_path(root, asset, False), force),
        workers,
    )
    run_parallel(
        "rendered",
        assets,
        lambda asset: render_asset(
            asset_path(root, asset, False), asset_path(root, asset, True), force
        ),
        workers,
    )
    manifest = pack_full_bank(assets, root, output_dir)
    print(
        f"packed {len(assets)} clips, {manifest['bank_size']} bytes, "
        f"{manifest['seconds'] / 60:.1f} minutes"
    )


def pack_auditions(output_dir: Path) -> None:
    sample_count = SAMPLE_RATE * 10
    silence = output_dir / "diagnostic-silence.pcm"
    tone = output_dir / "diagnostic-tone.pcm"
    silence.write_bytes(bytes(sample_count))
    tone.write_bytes(
        bytes(round(48 * math.sin(2 * math.pi * 440 * i / SAMPLE_RATE)) & 0xFF
              for i in range(sample_count))
    )
    labels = ["digital silence", "440 hz tone"] + [label for label, _ in AUDITIONS]
    raw_files = [silence, tone]
    for _, filename in AUDITIONS:
        source = output_dir / filename
        if not source.is_file():
            raise SystemExit(f"missing audition WAV: {source}")
        raw = source.with_suffix(".pcm")
        subprocess.run(
            [
                "ffmpeg", "-y", "-v", "error", "-i", str(source),
                "-ar", str(SAMPLE_RATE), "-ac", "1", "-f", "s8", str(raw),
            ],
            check=True,
        )
        raw_files.append(raw)

    entries = build_bank(raw_files, output_dir / "logan-auditions.reu")
    for entry, label in zip(entries, labels):
        entry["label"] = label
    manifest = {"sample_rate": SAMPLE_RATE, "format": "signed 8-bit mono", "assets": entries}
    (output_dir / "logan-auditions.json").write_text(json.dumps(manifest, indent=2) + "\n")

    lines = [
        "/* Generated by generate_previews.py --pack-auditions. */",
        "typedef struct { uint32_t offset, length; const char *label; } logan_clip;",
        f"#define LOGAN_BANK_SIZE {sum(e['length'] for e in entries)}UL",
        f"#define LOGAN_CLIP_COUNT {len(entries)}",
        "static const logan_clip logan_clips[LOGAN_CLIP_COUNT] = {",
    ]
    lines += [
        f'    {{{entry["offset"]}UL, {entry["length"]}UL, "{entry["label"]}"}},'
        for entry in entries
    ]
    lines += ["};", ""]
    (output_dir / "logan-auditions.h").write_text("\n".join(lines))
    print(f"packed {len(entries)} auditions, {sum(e['length'] for e in entries)} bytes")


def pack_final_auditions(output_dir: Path) -> None:
    manifest = json.loads((output_dir / "logan-comms.json").read_text())
    assets = {asset["id"]: asset for asset in manifest["assets"]}
    bank = (output_dir / "logan-comms.reu").read_bytes()
    raw_files = []
    for label, asset_id in FINAL_AUDITIONS:
        asset = assets[asset_id]
        path = output_dir / (asset_id.replace("/", "_") + ".audition.pcm")
        start = asset["offset"]
        path.write_bytes(bank[start:start + asset["length"]])
        raw_files.append(path)

    entries = build_bank(raw_files, output_dir / "logan-auditions.reu")
    for entry, (label, _) in zip(entries, FINAL_AUDITIONS):
        entry["label"] = label
    lines = [
        "/* Generated by generate_previews.py --pack-final-auditions. */",
        "typedef struct { uint32_t offset, length; const char *label; } logan_clip;",
        f"#define LOGAN_BANK_SIZE {sum(e['length'] for e in entries)}UL",
        f"#define LOGAN_CLIP_COUNT {len(entries)}",
        "static const logan_clip logan_clips[LOGAN_CLIP_COUNT] = {",
    ]
    lines += [
        f'    {{{entry["offset"]}UL, {entry["length"]}UL, "{entry["label"]}"}},'
        for entry in entries
    ]
    lines += ["};", ""]
    (output_dir / "logan-auditions.h").write_text("\n".join(lines))
    print(f"packed {len(entries)} final auditions, {sum(e['length'] for e in entries)} bytes")


def self_check() -> None:
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is required")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        files = [root / "a.raw", root / "b.raw"]
        files[0].write_bytes(b"ab")
        files[1].write_bytes(b"cde")
        entries = build_bank(files, root / "bank.pcm")
        assert (root / "bank.pcm").read_bytes() == b"abcde"
        assert [(item["offset"], item["length"]) for item in entries] == [(0, 2), (2, 3)]
    comms = json.loads(Path(__file__).with_name("comms.json").read_text())
    assets = expand_assets(comms)
    assert len(assets) == 820
    assert all(asset["voice_id"] for asset in assets)
    print("check passed")


def design_pilots(key: str, output_dir: Path, force: bool) -> None:
    for pilot_id, design in PILOT_DESIGNS.items():
        cache = output_dir / f"{pilot_id}-design.json"
        if cache.exists() and not force:
            response = json.loads(cache.read_text())
            print(f"reusing cached {pilot_id} Voice Design response")
        else:
            response = request_previews(key, design["description"], design["text"])
            cache.write_text(json.dumps(response))
        previews = response.get("previews", [])
        if len(previews) != 3:
            raise SystemExit(f"expected 3 {pilot_id} previews, received {len(previews)}")
        for index, preview in enumerate(previews, 1):
            source = output_dir / f"{pilot_id}-{index}-source.mp3"
            radio = output_dir / f"{pilot_id}-{index}-radio.wav"
            source.write_bytes(base64.b64decode(preview["audio_base_64"]))
            ffmpeg(source, radio)
        print(f"generated 3 {pilot_id} previews")


def design_dunks(key: str, output_dir: Path, force: bool) -> None:
    cache = output_dir / "dunks-design.json"
    if cache.exists() and not force:
        response = json.loads(cache.read_text())
        print("reusing cached Dunks Voice Design response")
    else:
        response = request_previews(
            key, DUNKS_DESCRIPTION, DUNKS_TEXT, model_id="eleven_ttv_v3"
        )
        cache.write_text(json.dumps(response))
    previews = response.get("previews", [])
    if len(previews) != 3:
        raise SystemExit(f"expected 3 Dunks previews, received {len(previews)}")
    for index, preview in enumerate(previews, 1):
        source = output_dir / f"dunks-{index}-source.mp3"
        radio = output_dir / f"dunks-{index}-radio.wav"
        source.write_bytes(base64.b64decode(preview["audio_base_64"]))
        ffmpeg(source, radio)
    print("generated 3 Dunks previews")


def save_dunks(key: str, output_dir: Path, selections: list[int]) -> None:
    response = json.loads((output_dir / "dunks-design.json").read_text())
    profiles = {
        1: ("Logan Dunks Pilot", DUNKS_DESCRIPTION),
        2: (
            "Logan Southern Pilot",
            "A natural, understated male cargo pilot with a Southern U.S. accent.",
        ),
    }
    for selection in selections:
        path = output_dir / f"selected-dunks-{selection}.json"
        if path.exists():
            saved = json.loads(path.read_text())
        else:
            name, description = profiles[selection]
            saved = save_voice(
                key,
                response["previews"][selection - 1]["generated_voice_id"],
                name,
                description,
            )
            path.write_text(json.dumps(saved, indent=2) + "\n")
        print(f"{selection}: {saved['name']} {saved['voice_id']}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--key-file", type=Path, default=Path("/private/tmp/logan-elevenlabs.key")
    )
    parser.add_argument("--force", action="store_true", help="spend credits on new previews")
    parser.add_argument("--select", type=int, choices=(1, 2, 3), help="save one preview as a voice")
    parser.add_argument(
        "--design-pilots", action="store_true", help="generate the two custom pilot auditions"
    )
    parser.add_argument(
        "--design-dunks", action="store_true", help="generate three exaggerated Boston auditions"
    )
    parser.add_argument(
        "--save-dunks", nargs="+", type=int, choices=(1, 2),
        help="save Dunks take 1 and/or Southern take 2 as reusable voices",
    )
    parser.add_argument(
        "--pack-auditions", action="store_true", help="pack audition WAVs for the C64 player"
    )
    parser.add_argument(
        "--pack-final-auditions", action="store_true",
        help="pack representative clips from the complete comms bank",
    )
    parser.add_argument(
        "--generate-all", action="store_true", help="generate and pack the complete comms bank"
    )
    parser.add_argument(
        "--estimate", action="store_true", help="show full-bank clip and character counts"
    )
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--check", action="store_true", help="run the local packer check")
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    if args.check:
        self_check()
        return
    if args.estimate:
        comms = json.loads(Path(__file__).with_name("comms.json").read_text())
        print_estimate(expand_assets(comms))
        return

    output_dir = Path(__file__).with_name("generated")
    output_dir.mkdir(exist_ok=True)
    if args.generate_all:
        generate_all(load_key(args.key_file), output_dir, args.force, args.workers)
        return
    if args.design_dunks:
        design_dunks(load_key(args.key_file), output_dir, args.force)
        return
    if args.save_dunks:
        save_dunks(load_key(args.key_file), output_dir, args.save_dunks)
        return
    if args.pack_auditions:
        pack_auditions(output_dir)
        return
    if args.pack_final_auditions:
        pack_final_auditions(output_dir)
        return
    if args.design_pilots:
        design_pilots(load_key(args.key_file), output_dir, args.force)
        return
    cache_path = output_dir / "voice-design.json"
    if cache_path.exists() and not args.force:
        response = json.loads(cache_path.read_text())
        print("reusing cached Voice Design response")
    else:
        response = request_previews(load_key(args.key_file))
        cache_path.write_text(json.dumps(response))

    previews = response.get("previews", [])
    if len(previews) != 3:
        raise SystemExit(f"expected 3 previews, received {len(previews)}")

    raw_files = []
    voice_ids = []
    for index, preview in enumerate(previews, 1):
        source = output_dir / f"controller-{index}-source.mp3"
        radio = output_dir / f"controller-{index}-radio.wav"
        raw = output_dir / f"controller-{index}.pcm"
        source.write_bytes(base64.b64decode(preview["audio_base_64"]))
        ffmpeg(source, radio)
        ffmpeg(source, raw, raw=True)
        raw_files.append(raw)
        voice_ids.append(preview["generated_voice_id"])

    entries = build_bank(raw_files, output_dir / "controller-bank.pcm")
    for entry, voice_id in zip(entries, voice_ids):
        entry["generated_voice_id"] = voice_id
    manifest = {"sample_rate": SAMPLE_RATE, "format": "signed 8-bit mono", "assets": entries}
    (output_dir / "controller-bank.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"generated {len(entries)} previews, bank size {sum(e['length'] for e in entries)} bytes")

    if args.select:
        selected_path = output_dir / "selected-controller.json"
        if selected_path.exists():
            selected = json.loads(selected_path.read_text())
            print(f"reusing saved voice {selected['name']}")
        else:
            selected = save_voice(load_key(args.key_file), voice_ids[args.select - 1])
            selected_path.write_text(json.dumps(selected, indent=2) + "\n")
            print(f"saved voice {selected['name']}")


if __name__ == "__main__":
    main()
