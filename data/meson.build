install_data(
  'com.majoris.stickies.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_data(
  'com.majoris.stickies.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo',
)

if get_option('shell_extension')
  install_data(
    '../shell/majoris-stickies@majoris.org/metadata.json',
    '../shell/majoris-stickies@majoris.org/extension.js',
    '../shell/majoris-stickies@majoris.org/layout.js',
    install_dir: get_option('datadir') / 'gnome-shell/extensions/majoris-stickies@majoris.org',
  )
endif
