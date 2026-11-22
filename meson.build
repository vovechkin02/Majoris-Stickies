project(
  'majoris-stickies',
  'vala',
  'c',
  version: '0.1.0',
  meson_version: '>=1.0.0',
  default_options: ['warning_level=2'],
)

gnome = import('gnome')

glib_dep = dependency('glib-2.0', version: '>=2.74')
gio_dep = dependency('gio-2.0', version: '>=2.74')
gee_dep = dependency('gee-0.8', version: '>=0.20')
gtk_dep = dependency('gtk4', version: '>=4.12')
adw_dep = dependency('libadwaita-1', version: '>=1.5')
sqlite_dep = dependency('sqlite3', version: '>=3.35')

app_deps = [glib_dep, gio_dep, gee_dep, gtk_dep, adw_dep, sqlite_dep]
core_deps = [glib_dep, gio_dep, gee_dep, sqlite_dep]

subdir('src')
subdir('data')
subdir('tests')

summary({
  'Stage': '1 — Core notes',
  'Storage': 'SQLite, local-first',
  'Desktop UI': 'GTK4 / libadwaita',
}, section: 'Majoris Stickies')
