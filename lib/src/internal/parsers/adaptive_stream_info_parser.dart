class AdaptiveStreamInfoParser {
  Map<String, dynamic> _root;

  AdaptiveStreamInfoParser(this._root);

  int parseBitrate() => _root['bitrate'];

  int parseContentLength() => _getInt(_root[
      'contentLength']); // encoded as string in json for whatever reason (maybe json int overflow)

  int parseFramerate() => _root['fps'];

  // if there is &sp=sig signiture parameter must name 'sig' instead of 'signiture'
  int parseHeight() => 0;

  bool parseIsAudioOnly() => _root['mimeType']?.startsWith('audio/');

  int parseItag() => _root['itag'];

  String parseSignature() => _root['s'];

  String parseSp() =>
      _root['sp']; //_root["size"].SubstringUntil('x').ParseInt();

  String parseUrl() =>
      _root['url']; //_root["size"].SubstringAfter('x').ParseInt();

  int parseWidth() => 0;

  int _getInt(String string) {
    if (string == null) {
      return null;
    }

    return int.tryParse(string);
  }
}
