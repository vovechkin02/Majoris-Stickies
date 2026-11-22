python = import('python').find_installation('python3')

unit_deps = core_deps

note_unit_executable = executable(
  'test-note',
  [core_sources, files('unit/test-note.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Note model edits and palette', note_unit_executable, suite: 'unit')

repository_unit_executable = executable(
  'test-note-repository',
  [core_sources, files('unit/test-note-repository.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('SQLite note persistence and search', repository_unit_executable, suite: 'unit')

stage2_unit_executable = executable(
  'test-stage2',
  [core_sources, files('unit/test-stage2.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 2 migration and formatting', stage2_unit_executable, suite: 'unit')

stage3_unit_executable = executable(
  'test-stage3',
  [core_sources, files('unit/test-stage3.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 3 sources and transfer', stage3_unit_executable, suite: 'unit')

test(
  'UI resources and template bindings',
  python,
  args: [meson.current_source_dir() / 'integration/test_resource_layout.py',
         meson.project_source_root() / 'data'],
  suite: 'integration',
)

stage4_unit_executable = executable(
  'test-stage4',
  [core_sources, files('unit/test-stage4.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 4 integrity and collection limits', stage4_unit_executable, suite: 'unit')

test(
  'Offline backup and restore',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/recovery', '-p', 'test_*.py'],
  suite: 'integration',
)

node = find_program('node', required: false)
if node.found()
  test(
    'Shell multi-monitor layout calculations',
    node,
    args: ['--experimental-default-type=module',
           meson.project_source_root() / 'tests/integration/test_layout.mjs'],
    suite: 'integration',
  )
endif

test(
  'Engineering source documentation coverage',
  python,
  args: [meson.project_source_root() / 'tools/check_source_docs.py'],
  suite: 'integration',
)

stage5_unit_executable = executable(
  'test-stage5',
  [core_sources, files('unit/test-stage5.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 5 reminders and v4 migration', stage5_unit_executable, suite: 'unit')

test(
  'Optional note share and folder synchronization',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage5_exchange.py'],
  suite: 'integration',
)

stage6_unit_executable = executable(
  'test-stage6',
  [core_sources, files('unit/test-stage6.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 6 lifecycle and schema migration', stage6_unit_executable, suite: 'unit')

test(
  'Stage 6 share and archive compatibility',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage6_exchange.py'],
  suite: 'integration',
)

test(
  'Stage 7 bounded RTF export',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage7_rtf.py'],
  suite: 'integration',
)

test(
  'Stage 7 packaging and menu contracts',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage7_release.py'],
  suite: 'integration',
)
