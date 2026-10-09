"""Build a licensed, offline Chinese route extract; never invent missing tracks."""
import gzip
import json
import math
from pathlib import Path
import subprocess
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlencode

BASE = Path(__file__).resolve().parent.parent
CACHE = BASE / 'work/domestic-routes'
API = 'https://hiking.waymarkedtrails.org/api/v1'
CLASSICS = ['五台山', '武功山', '南太行', '虎跳峡', '贡嘎', '雨崩', '长穿毕', '洛克', '四姑娘山', '乌孙', '夏特', '喀纳斯', '腾格里', '库布齐', '徽杭', '黄山', '三清山', '梵净山', '麦理浩', '麥理浩', '鳳凰徑', '港島徑', '衛奕信', '华山', '泰山', '峨眉', '庐山', '雁荡', '神农架', '太白', '大五台', '八达岭', '箭扣', '海坨', '四明山', '宁海', '九顶山', '佛顶山', '船底顶', '大南山', '七娘山', '东西涌', '梧桐山', '天目山', '莫干山', '百山祖', '括苍山', '香山', '白云山', '老君山']
REGIONS = dict(zip(['Hainan','Taiwan','Guangxi','Guangdong','Hong Kong','Macao','Fujian','Zhejiang','Jiangxi','Hunan','Guizhou','Yunnan','Sichuan','Chongqing','Hubei','Anhui','Jiangsu','Shanghai','Henan','Shaanxi','Gansu','Qinghai','Tibet','Xinjiang','Ningxia','Inner Mongolia','Shanxi','Hebei','Beijing','Tianjin','Shandong','Liaoning','Jilin','Heilongjiang'], ['海南','台湾','广西','广东','香港','澳门','福建','浙江','江西','湖南','贵州','云南','四川','重庆','湖北','安徽','江苏','上海','河南','陕西','甘肃','青海','西藏','新疆','宁夏','内蒙古','山西','河北','北京','天津','山东','辽宁','吉林','黑龙江']))
REGIONS['Guangzhou'] = '广东'  # geoBoundaries labels Guangdong this way in the current extract.

def fetch(url, filename):
    file = CACHE / filename
    if file.exists():
        return json.loads(file.read_text())
    result = subprocess.run(['curl', '-fsSL', '--max-time', '30', '-A', 'OutdoorGearNative/0.19 personal-offline-catalogue', url], capture_output=True, check=True)
    data = json.loads(result.stdout)
    file.write_bytes(result.stdout)
    time.sleep(0.3)
    return data

def project(lon, lat):
    return [lon * 20037508.34 / 180, math.log(math.tan(math.pi / 4 + lat * math.pi / 360)) * 6378137]

def point(pair):
    return {'lat': round((2 * math.atan(math.exp(pair[1] / 6378137)) - math.pi / 2) * 180 / math.pi, 7), 'lon': round(pair[0] / 20037508.34 * 180, 7)}

def rings(geometry):
    return geometry['coordinates'] if geometry['type'] == 'MultiPolygon' else [geometry['coordinates']]

def in_ring(lon, lat, ring):
    inside = False
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        if (y1 > lat) != (y2 > lat) and lon < (x2 - x1) * (lat - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside

def region_for(center, features):
    for f in features:
        for polygon in rings(f['geometry']):
            if in_ring(center['lon'], center['lat'], polygon[0]) and not any(in_ring(center['lon'], center['lat'], r) for r in polygon[1:]):
                name = f['properties']['shapeName']
                # Match the longest known prefix, so "Guangxi" is not confused with Guangdong.
                return next((REGIONS[k] for k in sorted(REGIONS, key=len, reverse=True) if name.startswith(k)), name)
    return None

def segments(node):
    result = []
    geom = node.get('geometry')
    if geom and geom['type'] == 'LineString' and len(geom['coordinates']) > 1:
        result.append([point(p) for p in geom['coordinates']])
    for child in node.get('main', []) + node.get('ways', []) + node.get('appendices', []):
        result.extend(segments(child))
    return result

def track_length_m(track):
    total = 0.0
    for segment in track:
        for a, b in zip(segment, segment[1:]):
            lat1, lat2 = math.radians(a['lat']), math.radians(b['lat'])
            dlat, dlon = lat2 - lat1, math.radians(b['lon'] - a['lon'])
            h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
            total += 6371008.8 * 2 * math.asin(math.sqrt(min(1.0, h)))
    return total

def build_entry(candidate, features):
    try:
        data = fetch(API + '/details/relation/' + str(candidate['id']), str(candidate['id']) + '.json')
        bbox = data['bbox']
        center = point([(bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2])
        region = region_for(center, features)
        if not region:
            return None, None
        tags = data.get('tags', {})
        name = tags.get('name:zh') or data.get('name') or candidate['name']
        if '鳌太' in name or '鰲太' in name or tags.get('access') in ['no', 'private']:
            return None, None
        track = segments(data['route'])
        count = sum(map(len, track))
        if not 2 <= count <= 20000:
            return None, None
        length = data.get('official_length') or data['route'].get('length')
        distance_source = '平台标注' if data.get('official_length') else '来源轨迹长度' if length else '按几何估算'
        if not length:
            length = track_length_m(track)
        route = {'id': candidate['id'], 'name': name, 'area': region, 'center': center,
                 'distance': f'{length / 1000:.1f} km（{distance_source}）' if length else '', 'segments': track}
        return {'route': route, 'sourceTags': tags,
                'classicKeywordMatch': any(k in name for k in CLASSICS),
                'distanceSource': distance_source if length else '未提供',
                'aliases': [tags[k] for k in ['name:en', 'alt_name', 'name'] if tags.get(k) and tags[k] != name]}, None
    except Exception as error:
        return None, f"{candidate['id']}: {error}"

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    features = json.loads(Path('/tmp/china-provinces.geojson').read_text())['features']
    candidates = {}
    errors = []
    for f in features:
        coords = [p for poly in rings(f['geometry']) for ring in poly for p in ring]
        bounds = project(min(p[0] for p in coords), min(p[1] for p in coords)) + project(max(p[0] for p in coords), max(p[1] for p in coords))
        name = f['properties']['shapeName']
        try:
            data = fetch(API + '/list/by_area?' + urlencode({'bbox': ','.join(map(str, bounds)), 'limit': 100}), name + '.json')
            results = list(data['results'])
            # The API caps each area at 100. Split capped provincial boxes into four cells
            # to discover additional relations without inventing or scraping private data.
            if len(results) >= 100:
                x0, y0, x1, y1 = bounds
                for xi in range(2):
                    for yi in range(2):
                        tile = [x0 + (x1-x0)*xi/2, y0 + (y1-y0)*yi/2,
                                x0 + (x1-x0)*(xi+1)/2, y0 + (y1-y0)*(yi+1)/2]
                        tile_data = fetch(API + '/list/by_area?' + urlencode({'bbox': ','.join(map(str, tile)), 'limit': 100}), name + f'-tile-{xi}-{yi}.json')
                        results.extend(tile_data['results'])
            for route in results:
                if route.get('name'):
                    candidates[route['id']] = route
            print(name, len(data['results']), 'unique', len(candidates), flush=True)
        except Exception as error:
            errors.append(str(error))
    entries = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(build_entry, candidate, features) for candidate in candidates.values()]
        for i, future in enumerate(as_completed(futures), start=1):
            entry, error = future.result()
            if entry:
                entries.append(entry)
            if error:
                errors.append(error)
            if i % 20 == 0:
                print('details', i, '/', len(candidates), 'accepted', len(entries), flush=True)
    entries.sort(key=lambda r: (not r['classicKeywordMatch'], r['route']['area'], r['route']['name']))
    output = {'schemaVersion': 1, 'snapshotDate': '2026-10-08', 'source': 'OpenStreetMap contributors / Waymarked Trails', 'license': 'ODbL-1.0', 'entries': entries}
    raw = json.dumps(output, ensure_ascii=False, separators=(',', ':')).encode()
    package = CACHE / 'package'
    package.mkdir(parents=True, exist_ok=True)
    (package / 'DomesticRoutes.json').write_bytes(raw)
    (package / 'DomesticRoutes.json.gz').write_bytes(gzip.compress(raw, mtime=0))
    region_counts = {}
    point_counts = []
    for entry in entries:
        region_counts[entry['route']['area']] = region_counts.get(entry['route']['area'], 0) + 1
        point_counts.append(sum(map(len, entry['route']['segments'])))
    (package / 'build-report.json').write_text(json.dumps({
        'snapshotDate': output['snapshotDate'], 'source': output['source'], 'license': output['license'],
        'candidateRelations': len(candidates), 'routesWithGeometry': len(entries),
        'classicNameKeywordMatches': sum(r['classicKeywordMatch'] for r in entries),
        'regions': region_counts, 'trackPoints': sum(point_counts),
        'trackPointRange': [min(point_counts), max(point_counts)] if point_counts else [0, 0],
        'elevationValues': 0, 'rawBytes': len(raw), 'gzipBytes': len(gzip.compress(raw)),
        'errors': errors
    }, ensure_ascii=False, indent=2))
    with zipfile.ZipFile(package / 'DomesticRoutes-data.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for filename in ['DomesticRoutes.json', 'README.md', 'build-report.json']:
            archive.write(package / filename, arcname=filename)
    print('COMPLETE', len(entries), 'routes', len(raw), 'bytes', flush=True)

if __name__ == '__main__':
    main()
