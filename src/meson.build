core_sources = files(
  'core/inline-image-format.vala',
  'core/note-attachment.vala',
  'core/note-formatting.vala',
  'core/note-palette.vala',
  'core/note-repository.vala',
  'core/note-title.vala',
  'core/note-transfer.vala',
  'core/source-link.vala',
  'core/text-style-format.vala',
  'core/note.vala',
)

gtk_sources = files(
  'gtk/ink-canvas.vala',
  'gtk/inline-image-controller.vala',
  'gtk/image-markup-editor.vala',
  'gtk/manager-window.vala',
  'gtk/note-window.vala',
  'gtk/note-paper-style.vala',
  'gtk/rich-text-codec.vala',
  'gtk/text-edit-commands.vala',
)

service_sources = files(
  'services/image-markup-transfer.vala',
  'services/note-defaults.vala',
  'services/pdf-preview-service.vala',
  'services/pdf-text-service.vala',
  'services/rtf-exporter.vala',
  'services/rtf-importer.vala',
  'services/rtfd-transfer.vala',
  'services/screenshot-portal.vala',
  'services/shell-window-bridge.vala',
  'services/startup-preferences.vala',
)

native_sources = files(
  'native/store-session-lock.c',
  'native/store-session-lock.vapi',
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
  [core_sources, service_sources, gtk_sources, app_sources, native_sources, resource_sources],
  include_directories: include_directories('native'),
  dependencies: app_deps,
  vala_args: stickies_vala_args,
  install: true,
)
