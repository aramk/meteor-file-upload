Package.describe({
  name: 'aramk:file-upload',
  summary: 'Simple file uploads.',
  version: '2.0.0'
});

Npm.depends({
  'mime': '1.3.4'
})

Package.onUse(function(api) {
  api.versionsFrom('METEOR@1.6.1');
  api.use([
    'coffeescript@2.2.1_1',
    'underscore',
    'templating@1.3.2',
    'less@4.0.0',
    'aramk:q@1.0.1_1',
    // 'cfs:standard-packages@3.0.0',
    // 'cfs:filesystem@3.0.0',
    // 'cfs:tempstore@3.0.0',
    // 'cfs:s3@3.0.0',
    'urbanetic:bismuth-utility@3.0.0',
    'urbanetic:utility@3.0.0'
  ], ['client', 'server']);
  api.addFiles([
    'src/uploadField.html',
    'src/uploadField.coffee',
    'src/uploadField.less'
  ], 'client');
  api.addFiles([
    'src/common/FileUtils.coffee'
  ], ['client', 'server']);
  api.addFiles([
    'src/server/FileUtils.coffee',
    'src/server/FileLogger.coffee'
  ], 'server');
  // api.imply('cfs:standard-packages@3.0.0');
  api.export([
    'FileUtils'
  ], ['client', 'server']);
  api.export([
    'FileLogger'
  ], 'server');
});
