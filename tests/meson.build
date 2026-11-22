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
