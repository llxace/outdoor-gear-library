"""Validate the standalone offline route package and its gzip copy."""
import gzip
import json
import math
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent.parent / 'work/domestic-routes/package'

def main():
    raw = (PACKAGE / 'DomesticRoutes.json').read_bytes()
    packed = gzip.decompress((PACKAGE / 'DomesticRoutes.json.gz').read_bytes())
    assert raw == packed, 'gzip copy differs from JSON'
    data = json.loads(raw)
    assert data['schemaVersion'] == 1
    report = json.loads((PACKAGE / 'build-report.json').read_text())
    entries = data['entries']
    ids = [entry['route']['id'] for entry in entries]
    assert len(ids) == len(set(ids)), 'duplicate route IDs'
    points = 0
    profiles = 0
    for entry in entries:
        route = entry['route']
        assert route['name'].strip() and route['area']
        assert isinstance(entry['classicKeywordMatch'], bool)
        assert isinstance(entry['sourceTags'], dict)
        assert entry['distanceSource'] in ('平台标注', '来源轨迹长度', '按几何估算')
        assert -90 <= route['center']['lat'] <= 90 and -180 <= route['center']['lon'] <= 180
        assert route['segments'] and all(len(segment) >= 2 for segment in route['segments'])
        route_points = sum(map(len, route['segments']))
        assert route_points <= 20_000
        for segment in route['segments']:
            for point in segment:
                assert math.isfinite(point['lat']) and math.isfinite(point['lon'])
                assert -90 <= point['lat'] <= 90 and -180 <= point['lon'] <= 180
                points += 1
        if 'elevationProfile' in route:
            profile = route['elevationProfile']
            stats = route['elevationStats']
            assert len(profile) == 100
            assert all(math.isfinite(p['elevationMeters']) for p in profile)
            assert stats['minimumMeters'] <= stats['maximumMeters']
            assert math.isclose(stats['averageMeters'], round(sum(p['elevationMeters'] for p in profile) / len(profile), 1))
            assert stats['estimatedAscentMeters'] >= 0 and stats['estimatedDescentMeters'] >= 0
            assert stats['sourceResolutionMeters'] == 90
            profiles += 1
    assert report['routesWithGeometry'] == len(entries)
    assert report['candidateRelations'] >= len(entries)
    assert report['rawBytes'] == len(raw)
    assert report['gzipBytes'] == len((PACKAGE / 'DomesticRoutes.json.gz').read_bytes())
    assert report['trackPoints'] == points
    if 'routesWithElevationProfile' in report:
        assert report['routesWithElevationProfile'] == profiles
    print(f"PASS: {len(entries)} routes, {points} track points, {profiles} elevation profiles, {len(raw):,} bytes JSON, {len((PACKAGE / 'DomesticRoutes.json.gz').read_bytes()):,} bytes gzip")

if __name__ == '__main__':
    main()
