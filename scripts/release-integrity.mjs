import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const fail = message => { console.error('RELEASE INTEGRITY FAIL:', message); process.exitCode = 1; };
const migrationDir = path.join(root, 'supabase', 'migrations');
const migrations = fs.readdirSync(migrationDir).filter(name => name.endsWith('.sql')).sort();
const byVersion = new Map();

for (const name of migrations) {
  const match = name.match(/^(\d+)_/);
  if (!match) {
    fail('Migration filename has no numeric version prefix: ' + name);
    continue;
  }
  const files = byVersion.get(match[1]) || [];
  files.push(name);
  byVersion.set(match[1], files);
}

// These two pairs are legacy SQL-Editor scripts already present in the repository.
// Keep the exception explicit so no new duplicate migration versions can be added silently.
const legacyDuplicates = new Map([
  ['022', ['022_public_league_directory.sql', '022_public_leagues_directory.sql']],
  ['026', ['026_automatic_seven_day_business_trial.sql', '026_seven_day_professional_trial.sql']]
]);
for (const [version, names] of byVersion) {
  if (names.length < 2) continue;
  const expected = legacyDuplicates.get(version);
  if (!expected || [...names].sort().join('|') !== [...expected].sort().join('|')) {
    fail('Unexpected duplicate migration version ' + version + ': ' + names.join(', '));
  } else {
    console.warn('LEGACY MIGRATION COLLISION (review before using Supabase CLI): ' + version + ' — ' + names.join(', '));
  }
}
for (const [version, expected] of legacyDuplicates) {
  const actual = byVersion.get(version) || [];
  if (actual.length !== expected.length || [...actual].sort().join('|') !== [...expected].sort().join('|')) {
    fail('Legacy migration collision changed unexpectedly for version ' + version);
  }
}

try {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.webmanifest'), 'utf8'));
  if (!manifest.start_url || !manifest.scope || manifest.display !== 'standalone') {
    fail('PWA manifest is missing a valid start_url, scope or standalone display mode');
  }
  for (const icon of manifest.icons || []) {
    const iconPath = path.resolve(root, icon.src.replace(/^\.\//, ''));
    if (!iconPath.startsWith(root + path.sep) || !fs.existsSync(iconPath)) {
      fail('PWA icon is missing or outside the repository: ' + icon.src);
    }
  }
} catch (error) {
  fail('PWA manifest is not valid JSON: ' + error.message);
}

const frontendFiles = fs.readdirSync(root)
  .filter(name => /\.(js|html)$/i.test(name))
  .map(name => path.join(root, name));
for (const file of frontendFiles) {
  const source = fs.readFileSync(file, 'utf8');
  if (/SUPABASE_SERVICE_ROLE_KEY\s*[:=]\s*['"`]/i.test(source)
      || /service_role\s*[:=]\s*['"`]eyJ/i.test(source)) {
    fail('Possible Supabase service-role secret embedded in browser source: ' + path.basename(file));
  }
}

const activity = fs.readFileSync(path.join(root, 'android/app/src/main/java/com/whitelion/sme/MainActivity.java'), 'utf8');
if (!activity.includes('WebViewAssetLoader') || !activity.includes('APP_ASSET_URL')
    || /webView\.loadUrl\(APP_URL\)/.test(activity)) {
  fail('Android app must load its bundled local application shell through WebViewAssetLoader');
}
const actionCentre = fs.readFileSync(path.join(root, 'action-centre.js'), 'utf8');
if (!actionCentre.includes('actorLabel')) {
  fail('Executive Action Centre audit history must display actor labels');
}

if (!process.exitCode) console.log('Release integrity checks passed. Legacy duplicate migration labels are explicitly allowlisted for manual-history review.');
