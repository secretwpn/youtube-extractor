class MuxedStreamInfoParser {
  Map<String, String> _root;

  MuxedStreamInfoParser(this._root);

  int parseItag() => _getInt(_root['itag']);

  String parseSignature() => _root['s'];

  String parseUrl() => _root['url'];

  int _getInt(String string) {
    if (string == null) {
      return null;
    }

    return int.tryParse(string);
  }
}
