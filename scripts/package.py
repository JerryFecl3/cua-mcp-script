"""Build a checksum-verified Windows candidate; fail closed on unknown licenses.

Requires Python 3.12+ and cargo. Downloads only from upstream GitHub/crates/npm.
Does not publish. Distribution gates live in the release workflow.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import urllib.request
import urllib.parse
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {'MIT', 'Apache-2.0', 'BSD-2-Clause', 'BSD-3-Clause', 'ISC', 'Zlib',
           'Unicode-3.0', 'Unicode-DFS-2016', 'CC0-1.0', 'Unlicense', 'MPL-2.0',
           'BSL-1.0', '0BSD', 'MIT-0', 'CDLA-Permissive-2.0'}
TREE_CACHE = {}


class NoCrossHostCredentials(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        result = super().redirect_request(req, fp, code, msg, headers, newurl)
        if result and urllib.parse.urlparse(req.full_url).netloc != urllib.parse.urlparse(newurl).netloc:
            result.remove_header('Authorization')
        return result


def fetch(url):
    headers = {'User-Agent': 'cua-mcp-script-build'}
    # Never forward the GitHub token to release redirects or third-party hosts.
    if url.startswith('https://api.github.com/') and os.getenv('GH_TOKEN'):
        headers['Authorization'] = 'Bearer ' + os.environ['GH_TOKEN']
    with urllib.request.build_opener(NoCrossHostCredentials).open(urllib.request.Request(url, headers=headers), timeout=120) as r:
        return r.read()


def recover_notices(package, base, target):
    """Some crates omit monorepo-root licenses; recover only at their recorded commit."""
    vcs_file = base / '.cargo_vcs_info.json'
    repo = (package.get('repository') or '').removesuffix('/').removesuffix('.git')
    match = re.fullmatch(r'https://github.com/([\w.-]+/[\w.-]+)', repo)
    if not match or not vcs_file.exists():
        return []
    vcs = json.loads(vcs_file.read_text())
    commit = vcs.get('git', {}).get('sha1', '')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        return []
    repository = match[1]
    key = (repository, commit)
    if key not in TREE_CACHE:
        TREE_CACHE[key] = json.loads(fetch(f'https://api.github.com/repos/{repository}/git/trees/{commit}?recursive=1'))
    tree = TREE_CACHE[key]
    if tree.get('truncated'):
        raise RuntimeError(f'Truncated source tree for {repository}; review required')
    from pathlib import PurePosixPath
    directory = PurePosixPath(vcs.get('path_in_vcs') or '.')
    ancestors = {str(directory), *(str(p) for p in directory.parents)}
    origins = []
    for entry in tree['tree']:
        path = PurePosixPath(entry['path'])
        if entry['type'] == 'blob' and str(path.parent) in ancestors and re.match(r'(?i)^(licen[cs]e|copying|notice|copyright)', path.name):
            url = f'https://raw.githubusercontent.com/{repository}/{commit}/{entry["path"]}'
            (target / entry['path'].replace('/', '__')).write_bytes(fetch(url))
            origins.append(url)
    if origins:
        (target / 'UPSTREAM-SOURCES.txt').write_text('\n'.join(origins)+'\n', encoding='utf-8')
    return origins


def license_allowed(expression):
    # Conservative: reject even an OR expression if any branch is unreviewed.
    if not expression or 'WITH' in expression:
        return False
    parts = re.findall(r'[A-Za-z0-9][A-Za-z0-9.+-]*', expression)
    return all(x in ALLOWED or x in ('AND', 'OR') for x in parts)


def write_bundle(bundle, output):
    # Crates often ship epoch-dated notices. Normalize timestamps instead of
    # propagating dates older than ZIP's 1980 minimum; sort paths for stable output.
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(bundle.rglob('*')):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(bundle).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, path.read_bytes())


def latest_stable():
    releases = []
    for page in range(1, 11):
        batch = json.loads(fetch(f'https://api.github.com/repos/trycua/cua/releases?per_page=100&page={page}'))
        releases += batch
        found = [r for r in releases if not r['draft'] and re.fullmatch(r'cua-driver-rs-v\d+\.\d+\.\d+', r['tag_name'])]
        if found:
            # Upstream deliberately marks stable driver releases as GitHub prereleases.
            return max(found, key=lambda r: tuple(map(int, r['tag_name'].removeprefix('cua-driver-rs-v').split('.'))))
        if not batch:
            break
    raise RuntimeError('No stable CUA Driver release found')


def build(tag):
    release = (json.loads(fetch(f'https://api.github.com/repos/trycua/cua/releases/tags/{tag}'))
               if tag else latest_stable())
    tag = release['tag_name']
    if not re.fullmatch(r'cua-driver-rs-v\d+\.\d+\.\d+', tag):
        raise RuntimeError('Only stable, exact CUA Driver tags are accepted')
    version = tag.removeprefix('cua-driver-rs-v')
    asset_name = f'cua-driver-rs-{version}-windows-x86_64-binary.zip'
    assets = {a['name']: a for a in release['assets']}
    archive = fetch(assets[asset_name]['browser_download_url'])
    checksums = fetch(assets['checksums.txt']['browser_download_url']).decode()
    actual = hashlib.sha256(archive).hexdigest()
    if not re.search(rf'(?mi)^{actual}\s+\*?{re.escape(asset_name)}\s*$', checksums):
        raise RuntimeError('Upstream archive checksum mismatch')
    work = ROOT / 'build' / tag
    if work.exists():
        raise RuntimeError(f'Build directory already exists: {work}; use a clean checkout')
    work.mkdir(parents=True)
    archive_path = work / asset_name
    archive_path.write_bytes(archive)
    bundle = work / 'cua-mcp-script'
    (bundle / 'cua').mkdir(parents=True)
    # No archive paths are trusted; permit exactly the expected flat asset files.
    expected = {'cua-driver.exe', 'cua-driver-uia.exe', 'cua-cursor-theme.exe',
                'cua_driver_sdk.dll', 'cua_driver_node_runtime.node', 'cua_driver_abi.h'}
    with zipfile.ZipFile(archive_path) as z:
        if set(z.namelist()) != expected or len(z.namelist()) != len(expected):
            raise RuntimeError('Upstream package layout changed: review required')
        for name in expected:
            (bundle / 'cua' / name).write_bytes(z.read(name))
    for name in ('CuaLink.ps1', 'README.md', 'README.zh-CN.md', 'LICENSE', 'VERSION', 'SECURITY.md'):
        shutil.copy2(ROOT / name, bundle / name)

    # Exact source tag for dependency notices. tar's data filter rejects path traversal.
    source_archive = work / 'source.tar.gz'
    source_archive.write_bytes(fetch(f'https://api.github.com/repos/trycua/cua/tarball/{tag}'))
    source_dir = work / 'source'
    with tarfile.open(source_archive) as t:
        t.extractall(source_dir, filter='data')
    source = next(source_dir.iterdir())
    driver = source / 'libs/cua-driver'
    licenses = bundle / 'licenses'
    licenses.mkdir()
    shutil.copy2(source / 'LICENSE.md', licenses / 'CUA-MIT.txt')
    shutil.copy2(driver / 'scripts/node-runtime-NOTICE.md', licenses / 'node-runtime-NOTICE.md')
    (licenses / 'MPL-2.0.txt').write_bytes(fetch('https://raw.githubusercontent.com/spdx/license-list-data/main/text/MPL-2.0.txt'))

    # Download the same locked Rust dependency sources, without executing build scripts.
    manifest = driver / 'rust/Cargo.toml'
    metadata = json.loads(subprocess.check_output([
        'cargo', 'metadata', '--locked', '--format-version', '1',
        '--filter-platform', 'x86_64-pc-windows-msvc', '--manifest-path', str(manifest)
    ], text=True, encoding='utf-8'))
    notices = [f'# Third-party notices\n\nCUA {version}: https://github.com/trycua/cua/tree/{tag}\n',
               'CUA is independently licensed; the wrapper LICENSE does not replace component licenses.\n']
    problems = []
    for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
        if not package['source']:
            continue  # Upstream workspace files are covered by its root MIT notice.
        expression = package.get('license')
        if not license_allowed(expression):
            problems.append(f"{package['name']} {package['version']}: {expression}")
        base = Path(package['manifest_path']).parent
        files = [p for p in base.iterdir() if p.is_file() and re.match(r'(?i)^(licen[cs]e|copying|notice|copyright)', p.name)]
        if package.get('license_file'):
            files.append(base / package['license_file'])
        target = licenses / (package['name'] + '-' + package['version'])
        target.mkdir(exist_ok=True)
        for f in set(files):
            if f.is_file():
                shutil.copy2(f, target / f.name)
        if not files and not recover_notices(package, base, target):
            problems.append(f"{package['name']}: no license/notice file; manual review required")
        notices.append(f"## {package['name']} {package['version']}\nLicense: {expression}\nSource: https://crates.io/api/v1/crates/{package['name']}/{package['version']}/download\n")
    # Node runtime has a separate MPL boundary. Preserve notice + exact source/build pointers.
    notices.append(f'''## cua_driver_node_runtime.node
License: MPL-2.0. Corresponding source and deterministic build transformations:
https://github.com/trycua/cua/tree/{tag}/libs/cua-driver
See licenses/node-runtime-NOTICE.md and scripts/build-node-runtime.mjs at that tag.
The pinned uniffi-bindgen-react-native dependency is available from the npm registry.
''')
    (bundle / 'THIRD-PARTY-NOTICES.md').write_text('\n'.join(notices), encoding='utf-8')
    if problems:
        (work / 'license-review-required.txt').write_text('\n'.join(problems))
        raise RuntimeError('License gate failed:\n' + '\n'.join(problems))
    manifest_data = dict(script_version=(ROOT / 'VERSION').read_text().strip(), cua_version=version,
                         cua_tag=tag, upstream_url=assets[asset_name]['browser_download_url'],
                         upstream_sha256=actual, status='candidate-not-desktop-certified',
                         source_commit=os.getenv('GITHUB_SHA', 'local'))
    (bundle / 'version.json').write_text(json.dumps(manifest_data, indent=2)+'\n')
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    output = dist / f'cua-mcp-script-{manifest_data["script_version"]}-cua-{version}-windows-x64.zip'
    write_bundle(bundle, output)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (dist / 'SHA256SUMS').write_text(f'{digest}  {output.name}\n')
    print(json.dumps(manifest_data, indent=2))
    print(output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', help='Exact stable upstream tag; default: discover newest stable driver')
    build(parser.parse_args().tag)

