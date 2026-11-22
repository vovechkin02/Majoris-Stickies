core_sources = files(
  'core/note-attachment.vala',
  'core/note-formatting.vala',
  'core/note-palette.vala',
  'core/note-repository.vala',
  'core/note.vala',
)

gtk_sources = files(
  'gtk/manager-window.vala',
  'gtk/note-window.vala',
  'gtk/rich-text-codec.vala',
)

service_sources = files(
  'services/shell-window-bridge.vala',
)

app_sources = files(
  'app/application.vala',
  'app/main.vala',
)

resource_sources = gnome.compile_resources(
  'stickies-resources',
  '../data/com.majoris.stickies.gresource.xml',
  source_dir: '../data',
  c_name: 'majoris_stickies_resources',
)

stickies_executable = executable(
  'majoris-stickies',
  [core_sources, service_sources, gtk_sources, app_sources, resource_sources],
  dependencies: app_deps,
  vala_args: stickies_vala_args,
  install: true,
)
