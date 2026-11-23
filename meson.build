project(
  'majoris-stickies',
  'vala',
  'c',
  version: '0.9.12',
  meson_version: '>=1.1.0',
  default_options: ['warning_level=2'],
)

gnome = import('gnome')

glib_dep = dependency('glib-2.0', version: '>=2.74')
gio_dep = dependency('gio-2.0', version: '>=2.74')
gee_dep = dependency('gee-0.8', version: '>=0.20')
gtk_dep = dependency('gtk4', version: '>=4.16')
adw_dep = dependency('libadwaita-1', version: '>=1.5')
sqlite_dep = dependency('sqlite3', version: '>=3.35')

app_deps = [glib_dep, gio_dep, gee_dep, gtk_dep, adw_dep, sqlite_dep]
stickies_vala_args = ['--pkg=sqlite3']
imagekit_dep = dependency('majoris-image-gtk4-1', required: get_option('imagekit'))
if imagekit_dep.found()
  app_deps += [imagekit_dep]
  stickies_vala_args += ['--pkg=majoris-image-gtk4-1', '--define=HAVE_IMAGEKIT']
endif
spellcheck_dep = dependency('libspelling-1', required: get_option('spellcheck'))
sourceview_dep = dependency('gtksourceview-5', required: get_option('spellcheck'))
if spellcheck_dep.found() and sourceview_dep.found()
  app_deps += [spellcheck_dep, sourceview_dep]
  stickies_vala_args += ['--pkg=libspelling-1', '--pkg=gtksourceview-5', '--define=HAVE_SPELLING']
endif
core_deps = [glib_dep, gio_dep, gee_dep, sqlite_dep]

subdir('src')
subdir('data')
subdir('tests')

install_data(
  'tools/stickies_backup.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-backup',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_exchange.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-exchange',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_rtf.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-rtf',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_rtf_import.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-rtf-import',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_rtfd.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-rtfd',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_reminders.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-reminders',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_auto_sync.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-auto-sync',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_pdf_preview.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-pdf-preview',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_image_crop.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-image-crop',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_pdf_annotate.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-pdf-annotate',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_image_markup.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-image-markup',
  install_mode: 'rwxr-xr-x',
)

install_data(
  'tools/stickies_pdf_text.py',
  install_dir: get_option('bindir'),
  rename: 'majoris-stickies-pdf-text',
  install_mode: 'rwxr-xr-x',
)

summary({
  'Stage': '9.12 paragraph geometry and RTFD compatibility — native qualification pending',
  'ImageKit': imagekit_dep.found(),
  'Spellcheck': spellcheck_dep.found() and sourceview_dep.found(),
  'Shell extension installed': get_option('shell_extension'),
  'Storage': 'SQLite, local-first',
  'Desktop UI': 'GTK4 / libadwaita',
}, section: 'Majoris Stickies')
