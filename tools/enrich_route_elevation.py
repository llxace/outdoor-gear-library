"""Add a sampled SRTM90 elevation profile and estimated ascent/descent for each route."""
import gzip
import json
import math
from pathlib import Path
import subprocess
import time
import zipfile

BASE = Path(__file__).resolve().parent.parent
PACKAGE = BASE / 'work/domestic-routes/package'
CACHE = BASE / 'work/domestic-routes/elevation-cache'
API = 'https://api.opentopodata.org/v1/srtm90m'
SAMPLES = 100
NOISE_THRESHOLD_METERS = 8
MINIMUM_VALID_RATIO = 0.75

def haversine(a, b):
    lat1, lat2 = math.radians(a['lat']), math.radians(b['lat'])
    dlat, dlon = lat2-lat1, math.radians(b['lon']-a['lon'])
    h = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
    return 6371008.8 * 2 * math.asin(math.sqrt(h))

def sample_path(segments):
    parts, total = [], 0.0
    for segment in segments:
        cumulative = [0.0]
        for a, b in zip(segment, segment[1:]):
            cumulative.append(cumulative[-1] + haversine(a, b))
        if cumulative[-1] > 0:
            parts.append((segment, cumulative, total, cumulative[-1]))
            total += cumulative[-1]
    if total <= 0:
        return [], 0.0
    result = []
    for i in range(SAMPLES):
        target = total * i / (SAMPLES - 1)
        segment, cumulative, offset, length = next((p for p in parts if target <= p[2] + p[3]), parts[-1])
        within = max(0.0, min(length, target - offset))
        ix = next((j for j, d in enumerate(cumulative[1:], 1) if d >= within), len(cumulative)-1)
        a, b = segment[ix-1], segment[ix]
        span = cumulative[ix] - cumulative[ix-1]
        fraction = 0 if span <= 0 else (within - cumulative[ix-1]) / span
        result.append({'distanceMeters': round(target, 1),
                       'lat': round(a['lat'] + (b['lat']-a['lat'])*fraction, 7),
                       'lon': round(a['lon'] + (b['lon']-a['lon'])*fraction, 7)})
    return result, total

def fetch(samples):
    payload = {'locations': '|'.join(f"{p['lat']:.7f},{p['lon']:.7f}" for p in samples), 'interpolation': 'bilinear'}
    result = subprocess.run(['curl', '-fsSL', '--max-time', '30', '-A', 'OutdoorGearNative-route-package/1.0',
                             '-H', 'Content-Type: application/json', '--data-binary', '@-', API],
                            input=json.dumps(payload).encode(), capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace').strip() or f'curl exit {result.returncode}')
    response = json.loads(result.stdout)
    if len(response.get('results', [])) != len(samples):
        raise ValueError('elevation response count does not match sampled points')
    return response

def ascent_descent(values):
    if len(values) >= 3:
        values = values[:]
        for i in range(1, len(values)-1):
            values[i] = sorted(values[i-1:i+2])[1]
    up = down = 0.0
    for a, b in zip(values, values[1:]):
        delta = b-a
        if delta > NOISE_THRESHOLD_METERS: up += delta-NOISE_THRESHOLD_METERS
        elif delta < -NOISE_THRESHOLD_METERS: down += -delta-NOISE_THRESHOLD_METERS
    return round(up), round(down)

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    path = PACKAGE / 'DomesticRoutes.json'
    data = json.loads(path.read_text())
    entries, errors = data['entries'], []
    last_request = 0.0
    complete = 0
    for index, entry in enumerate(entries, 1):
        route = entry['route']
        samples, route_length = sample_path(route['segments'])
        if len(samples) < 2:
            errors.append(f"{route['id']}: insufficient geometry")
            continue
        cache = CACHE / f"{route['id']}.json"
        response = None
        if cache.exists():
            try:
                response = json.loads(cache.read_text())
                if response.get('status') != 'OK' or len(response.get('results', [])) != SAMPLES:
                    response = None
            except (OSError, json.JSONDecodeError):
                response = None
        if response is None:
            wait = 1.05 - (time.monotonic() - last_request)
            if wait > 0: time.sleep(wait)
            last_request = time.monotonic()
            try:
                response = fetch(samples)
                cache.write_text(json.dumps(response, separators=(',', ':')))
            except Exception as error:
                errors.append(f"{route['id']}: {error}")
                continue
        valid = [(sample, result.get('elevation')) for sample, result in zip(samples, response['results'])
                 if isinstance(result.get('elevation'), (int, float)) and math.isfinite(result['elevation'])]
        if len(valid) < max(2, int(SAMPLES * MINIMUM_VALID_RATIO)):
            errors.append(f"{route['id']}: insufficient DEM coverage ({len(valid)}/{SAMPLES})")
            continue
        profile = [dict(sample, elevationMeters=round(float(elevation), 1)) for sample, elevation in valid]
        altitudes = [sample['elevationMeters'] for sample in profile]
        ascent, descent = ascent_descent(altitudes)
        route['elevationProfile'] = profile
        route['elevationStats'] = {
            'minimumMeters': round(min(altitudes), 1), 'maximumMeters': round(max(altitudes), 1),
            'averageMeters': round(sum(altitudes) / len(altitudes), 1),
            'estimatedAscentMeters': ascent, 'estimatedDescentMeters': descent,
            'profileDistanceMeters': round(route_length), 'profileSampleCount': len(profile),
            'noiseThresholdMeters': NOISE_THRESHOLD_METERS,
            'source': 'SRTM90m via Open Topo Data', 'sourceResolutionMeters': 90,
            'method': '100 equal-distance samples; 3-point median smoothing; ignore adjacent changes ≤8 m'
        }
        complete += 1
        if index % 20 == 0:
            print(f'elevation routes {index}/{len(entries)} complete {complete}', flush=True)

    data['elevationSource'] = 'SRTM90m via Open Topo Data public API'
    data['elevationNote'] = 'Sampled DEM estimates; not surveyed elevation and not suitable for navigation or safety decisions.'
    raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode()
    path.write_bytes(raw)
    gz_path = PACKAGE / 'DomesticRoutes.json.gz'
    gz_path.write_bytes(gzip.compress(raw, mtime=0))
    report_path = PACKAGE / 'build-report.json'
    report = json.loads(report_path.read_text())
    sample_total = sum(len(e['route'].get('elevationProfile', [])) for e in entries)
    report.update({'routesWithElevationProfile': complete,
                   'routesWithoutElevationProfile': len(entries)-complete,
                   'elevationSource': data['elevationSource'], 'elevationResolutionMeters': 90,
                   'elevationSamplesPerRoute': SAMPLES, 'elevationSamplesTotal': sample_total,
                   'elevationValues': sample_total, 'elevationErrors': errors,
                   'rawBytes': len(raw), 'gzipBytes': len(gz_path.read_bytes())})
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    with zipfile.ZipFile(PACKAGE / 'DomesticRoutes-data.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for filename in ['DomesticRoutes.json', 'README.md', 'build-report.json']:
            archive.write(PACKAGE / filename, arcname=filename)
    print(f"COMPLETE elevation profiles: {complete}/{len(entries)}; {len(errors)} issues", flush=True)

if __name__ == '__main__':
    main()
