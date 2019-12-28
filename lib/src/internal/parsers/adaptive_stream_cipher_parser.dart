class AdaptiveStreamCipherParser {
  Map<String, dynamic> _root;

  AdaptiveStreamCipherParser(this._root);

  String parseUrl() => _root['url'];

  String parseSignature() => _root['s'];

  String parseSp() => _root['sp'];

  static AdaptiveStreamCipherParser initialize(String raw) {
    var query = Uri.splitQueryString(raw);
    return AdaptiveStreamCipherParser(query);
  }
}
