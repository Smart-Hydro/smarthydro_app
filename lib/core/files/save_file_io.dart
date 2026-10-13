import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveBytes(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  await SharePlus.instance.share(
    ShareParams(
      title: filename,
      files: [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
      fileNameOverrides: [filename],
    ),
  );
}

Future<bool> openExternal(String url) async {
  await SharePlus.instance.share(ShareParams(uri: Uri.parse(url)));
  return true;
}
