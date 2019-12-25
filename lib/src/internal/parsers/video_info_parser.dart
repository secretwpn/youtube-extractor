import 'dart:convert';

import 'adaptive_stream_info_parser.dart';
import 'muxed_stream_info_parser.dart';

class VideoInfoParser {
  Map<String, String> _root;
  Map<String, dynamic> _playerResponse;
  bool isLive;

  VideoInfoParser(this._root, this._playerResponse);

  List<AdaptiveStreamInfoParser> getAdaptiveStreamInfo() {
    var builtList = List<AdaptiveStreamInfoParser>();
    try {
      var streamInfosEncoded =
          _playerResponse['streamingData']['adaptiveFormats'];
      streamInfosEncoded?.forEach((stream) {
        builtList.add(AdaptiveStreamInfoParser(stream));
      });
    } catch (err) {
      print('Failed to get adaptive stream info');
      print(err);
    }
    return builtList;
  }

  List<MuxedStreamInfoParser> getMuxedStreamInfo() {
    // List that we will full
    var builtList = List<MuxedStreamInfoParser>();
    try {
      var streamInfosEncoded = _root['url_encoded_fmt_stream_map'];

      if (streamInfosEncoded == null) {
        return List<MuxedStreamInfoParser>();
      }

      // Extract the streams and return a list
      var streams = streamInfosEncoded.split(',');
      streams.forEach((stream) {
        builtList.add(MuxedStreamInfoParser(Uri.splitQueryString(stream)));
      });
    } catch (err) {
      print('Failed to get muxed stream info');
      print(err);
    }
    return builtList;
  }

  List<MuxedStreamInfoParser> getMuxedStreamInfo2() {
    var builtList = List<MuxedStreamInfoParser>();
    try {
      var streamInfosEncoded = _playerResponse['streamingData']['formats'];
      streamInfosEncoded?.forEach((stream) {
        builtList.add(MuxedStreamInfoParser(stream));
      });
    } catch (err) {
      print('Failed to get adaptive stream info');
      print(err);
    }
    return builtList;
  }

  int parseErrorCode() =>
      _root['errorcode'] == null ? 0 : int.tryParse(_root['errorcode']);

  String parseErrorReason() => _root["reason"];

  String parsePreviewVideoId() => _root['ypc_vid'];

  String parseStatus() {
    String status = 'error';
    try {
      var playabilityStatus =
          _playerResponse['playabilityStatus'] as Map<String, dynamic>;
      if (playabilityStatus == null || !playabilityStatus.containsKey('status'))
        return status = 'error';
      status = playabilityStatus['status'];
    } catch (err) {
      print('Failed to parse status');
    }
    return status;
  }

  static VideoInfoParser initialize(String raw) {
    var root = Uri.splitQueryString(raw);
    var playerResponse =
        jsonDecode(root['player_response']) as Map<String, dynamic>;
    return VideoInfoParser(root, playerResponse);
  }
}
