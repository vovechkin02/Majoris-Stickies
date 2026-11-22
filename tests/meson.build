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

test(
  'Stage 8 bounded RTF import',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage8_rtf_import.py'],
  suite: 'integration',
)

test(
  'Stage 8 desktop and editing contracts',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage8_contracts.py'],
  suite: 'integration',
)

test(
  'Stage 8 bounded PDF first-page preview',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage8_pdf_preview.py'],
  suite: 'integration',
)


test(
  'Stage 8 completion and directory interchange',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration',
         '-p', 'test_stage8_completion.py'],
  suite: 'integration',
)

stage8_final_unit_executable = executable(
  'test-stage8-final',
  [core_sources, files('unit/test-stage8-final.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 8 final formatting and image tokens', stage8_final_unit_executable,
  suite: 'unit')

test(
  'Stage 8 final metadata and import regression',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration',
         '-p', 'test_stage8_final.py'],
  suite: 'integration',
)

# Keep Stage 9 checks focused on installed metadata and safe preview cleanup.
test(
  'Stage 9 release metadata and preview recovery',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration',
         '-p', 'test_stage9_release.py'],
  suite: 'integration',
)

# Stage 9.1 focused round-trip, deletion and reminder worker checks.
foreach case_name : [
  'test_stage9_interchange.py',
  'test_stage9_deletions.py',
  'test_stage9_rtfd_native.py',
  'test_stage9_rtf_dynamic.py',
  'test_stage9_reminders.py',
]
  test(
    'Stage 9.1 ' + case_name,
    python,
    args: ['-m', 'unittest', 'discover', '-s',
           meson.project_source_root() / 'tests/integration', '-p', case_name],
    suite: 'integration',
  )
endforeach

stage9_completion_unit_executable = executable(
  'test-stage9-2',
  [core_sources, files('unit/test-stage9-2.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 9.2 rich clipboard and search ordering', stage9_completion_unit_executable, suite: 'unit')

test(
  'Stage 9.2 XDG data-directory compatibility',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage9_2_xdg.py'],
  suite: 'integration',
)

test(
  'Stage 9.2 opt-in background folder synchronization',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage9_2_auto_sync.py'],
  suite: 'integration',
)

# Verify the same advisory lock is obeyed by the native GUI shim and Python exchange.
test(
  'Stage 9.3 notes-store session lock',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_store_session_lock.py'],
  suite: 'integration',
)

# Stage 9.4 text/PDF reading and portable nested-list compatibility.
stage9_4_unit_executable = executable(
  'test-stage9-4',
  [core_sources, files('unit/test-stage9-4.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 9.4 nested-list tokens', stage9_4_unit_executable, suite: 'unit')

foreach case_name : [
  'test_stage9_4_pdf_text.py',
  'test_stage9_4_list_interchange.py',
]
  test(
    'Stage 9.4 ' + case_name,
    python,
    args: ['-m', 'unittest', 'discover', '-s',
           meson.project_source_root() / 'tests/integration', '-p', case_name],
    suite: 'integration',
  )
endforeach

stage9_5_unit_executable = executable(
  'test-stage9-5',
  [core_sources, files('unit/test-stage9-5.vala')],
  dependencies: unit_deps,
  vala_args: ['--pkg=sqlite3'],
)
test('Stage 9.5 persistent automatic title mode', stage9_5_unit_executable, suite: 'unit')

test(
  'Stage 9.5 title-mode interchange',
  python,
  args: ['-m', 'unittest', 'discover', '-s',
         meson.project_source_root() / 'tests/integration', '-p', 'test_stage9_5_titles.py'],
  suite: 'integration',
)
