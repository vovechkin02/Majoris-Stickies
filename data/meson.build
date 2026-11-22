install_data(
  'com.majoris.stickies.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_data(
  'com.majoris.stickies.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo',
)

install_data(
  'icons/com.majoris.stickies.svg',
  install_dir: get_option('datadir') / 'icons/hicolor/scalable/apps',
)

if get_option('shell_extension')
  install_data(
    '../shell/majoris-stickies@majoris.org/metadata.json',
    '../shell/majoris-stickies@majoris.org/extension.js',
    '../shell/majoris-stickies@majoris.org/layout.js',
    install_dir: get_option('datadir') / 'gnome-shell/extensions/majoris-stickies@majoris.org',
  )
endif

# Installed but disabled: the user explicitly opts into offline background reminders.
install_data(
  'systemd/majoris-stickies-reminders.service',
  'systemd/majoris-stickies-reminders.timer',
  install_dir: get_option('prefix') / 'lib/systemd/user',
)
