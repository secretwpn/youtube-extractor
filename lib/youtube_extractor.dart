import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'src/exceptions/parse_exception.dart';
import 'src/exceptions/video_requires_purchase_exception.dart';
import 'src/exceptions/video_unavailable_exception.dart';
import 'src/internal/itag_helper.dart';
import 'src/internal/parsers/player_source_parser.dart';
import 'src/internal/parsers/video_info_parser.dart';
import 'src/internal/player_source.dart';
import 'src/models/media_streams/audio_stream_info.dart';
import 'src/models/media_streams/media_stream_info_set.dart';
import 'src/models/media_streams/muxed_stream_info.dart';
import 'src/models/media_streams/video_resolution.dart';
import 'src/models/media_streams/video_stream_info.dart';

/// Dart port of YouTubeExplode
class YouTubeExtractor {
  // Stores the player source cache as this is used a lot
  var _playerSourceCache = Map<String, PlayerSource>();

  // Client used for http requests
  var _client = http.Client();

  // Credits from https://github.com/sarbagyastha/youtube_player_flutter
  // Get video ID from URL
  /// Gets a set of all available media stream infos for given video.
  Future<MediaStreamInfoSet> getMediaStreamsAsync(String videoId) async {
    // Make sure the ID is valid
    if (!_validateVideoId(videoId)) {
      throw ArgumentError('Invalid YouTube video ID [$videoId].');
    }

    // Create the http client
    _client = http.Client();

    // Get player context
    var playerSourceUrl = await _getVideoPlayerSourceUrlAsync(videoId);

    // Get parser
    var parser = await _getVideoInfoParserAsync(videoId, "embedded");

    // Check if video requires purchase
    var previewVideoId = parser.parsePreviewVideoId();
    if (previewVideoId != null) {
      throw new VideoRequiresPurchaseException(videoId, previewVideoId);
    }

    // Prepare stream info maps
    var muxedStreamInfoMap = new Map<int, MuxedStreamInfo>();
    var audioStreamInfoMap = new Map<int, AudioStreamInfo>();
    var videoStreamInfoMap = new Map<int, VideoStreamInfo>();

    // Parse muxed stream infos
    var muxedStreamInfo = parser.getMuxedStreamInfo();
    for (var i = 0; i < muxedStreamInfo.length; i++) {
      // Extract itag
      var itag = muxedStreamInfo[i].parseItag();

      // Skip unknown itags
      if (!ItagHelper.isKnown(itag)) {
        continue;
      }

      // Extract URL
      var url = muxedStreamInfo[i].parseUrl();

      // Decipher signature if needed
      var signature = muxedStreamInfo[i].parseSignature();
      if (signature != null) {
        var playerSource = await _getVideoPlayerSourceAsync(playerSourceUrl);
        signature = playerSource.decipher(signature);
        url = url + '&signature=' + signature;
      }

      // Probe stream and get content length
      var probe = await _client.head(url);
      int contentLength = int.tryParse(probe.headers['content-length']);

      // If probe failed or content length is 0, it means the stream is gone or faulty
      if (contentLength > 0) {
        var streamInfo = MuxedStreamInfo(itag, url, contentLength);
        muxedStreamInfoMap[itag] = streamInfo;
      }
    }

    // Parse adaptive stream infos
    var adaptiveStreamInfo = parser.getAdaptiveStreamInfo();
    for (var i = 0; i < adaptiveStreamInfo.length; i++) {
      // Extract itag
      var itag = adaptiveStreamInfo[i].parseItag();

      // Skip unknown itags
      if (!ItagHelper.isKnown(itag)) {
        continue;
      }

      // Extract content length
      var contentLength = adaptiveStreamInfo[i].parseContentLength();

      // If content length is 0, it means that the stream is gone or faulty
      if (contentLength > 0) {
        // Extract URL
        var url = adaptiveStreamInfo[i].parseUrl();

        // Decipher signature if needed
        var signature = adaptiveStreamInfo[i].parseSignature();
        if (signature != null) {
          var playerSource = await _getVideoPlayerSourceAsync(playerSourceUrl);
          signature = playerSource.decipher(signature);

          // parameter 'ratebypass' needs to be yes
          // if there is 'sp' parameter, must use 'sig' instead of 'signature'
          if (adaptiveStreamInfo[i].parseSp() != null) {
            url = url +
                '&ratebypass=yes&${adaptiveStreamInfo[i].parseSp()}=' +
                signature;
          } else {
            url = url + '&ratebypass=yes&signature=' + signature;
          }
        }

        // Extract bitrate
        var bitrate = adaptiveStreamInfo[i].parseBitrate();

        // If audio-only
        if (adaptiveStreamInfo[i].parseIsAudioOnly()) {
          var streamInfo = AudioStreamInfo(itag, url, contentLength, bitrate);
          audioStreamInfoMap[itag] = streamInfo;
        } else {
          // If video-only
          // Extract info
          var width = adaptiveStreamInfo[i].parseWidth();
          var height = adaptiveStreamInfo[i].parseHeight();
          var framerate = adaptiveStreamInfo[i].parseFramerate();

          var resolution = VideoResolution(width, height);
          var streamInfo = VideoStreamInfo(
              itag, url, contentLength, bitrate, resolution, framerate);
          videoStreamInfoMap[itag] = streamInfo;
        }
      }
    }

    // Finalize stream info collections
    var muxedStreamInfos = muxedStreamInfoMap.values.toList();
    var audioStreamInfos = audioStreamInfoMap.values.toList();
    var videoStreamInfos = videoStreamInfoMap.values.toList();

    // We are done with the client
    _client.close();

    return MediaStreamInfoSet(
      muxedStreamInfos,
      audioStreamInfos,
      videoStreamInfos,
    );
  }

  Future<VideoInfoParser> _getVideoInfoParserAsync(
    String videoId,
    String el,
  ) async {
    // This parameter does magic and a lot of videos don't work without it
    var eurl = Uri.encodeFull('https://youtube.googleapis.com/v/$videoId');

    // Build the url and perform a request
    // For some reasons, 'sts' parameter isn't required. but if value of 'sts' is null then, the request emit a Error.
    // previous variable
    // var url = "https://www.youtube.com/get_video_info?video_id=$videoId&el=$el&sts=$sts&eurl=$eurl&hl=en";
    var url =
        "https://www.youtube.com/get_video_info?video_id=$videoId&el=$el&eurl=$eurl&hl=en";
    var body = (await _client.get(url)).body;

    // Parse the response
    var parser = VideoInfoParser.initialize(body);

    // getInfo properties have been changed that 'video_id' property is no longer provided.
    // use 'status' property instead of 'video_id'
    // Check if status exists by verifying that status property is 'ok'
    if (parser.parseStatus()?.toLowerCase() != 'ok') {
      // Get native error code and error reason
      var errorCode = parser.parseErrorCode();
      var errorReason = parser.parseErrorReason();

      throw new VideoUnavailableException(videoId, errorCode, errorReason);
    }

    // Return the split string
    return parser;
  }

  // -- PRIVATE METHODS -- //

  Future<PlayerSource> _getVideoPlayerSourceAsync(String sourceUrl) async {
    // Try to resolve from cache first
    var playerSource = _playerSourceCache[sourceUrl];
    if (playerSource != null) {
      return playerSource;
    }

    // Get parser
    var raw = (await _client.get(sourceUrl)).body;
    var parser = PlayerSourceParser.initialize(raw);

    // Extract cipher operations
    var operations = parser.parseCipherOperations();

    return _playerSourceCache[sourceUrl] = PlayerSource(operations);
  }

  Future<String> _getVideoPlayerSourceUrlAsync(String videoId) async {
    // Build the required url and get the response
    var url =
        'https://www.youtube.com/embed/$videoId?disable_polymer=true&hl=en';
    var body = (await _client.get(url)).body;

    // Extract the config part
    var config =
        RegExp(r"yt\.setConfig\({'PLAYER_CONFIG':.+?\}\);", multiLine: true)
            .firstMatch(body)
            .group(0);

    // Trip off the start and end to get a valid JSON string
    config = config.substring(30, config.length - 3);

    // Decode the json
    var root = json.decode(config);

    // Get the player source url
    var playerSourceUrl = root["assets"]["js"].toString();
    if (playerSourceUrl != null && playerSourceUrl.isNotEmpty) {
      playerSourceUrl = "https://www.youtube.com" + playerSourceUrl;
    }

    // Check if successful
    if ((playerSourceUrl?.isEmpty ?? true))
      throw ParseException("Could not parse player context.");

    return playerSourceUrl;
  }

  /// Verifies that the given string is syntactically a valid YouTube video ID.
  bool _validateVideoId(String videoId) {
    // The user has not passed in a video ID at all
    if (videoId == null || videoId.isEmpty) {
      return false;
    }

    // Video IDs are always 11 characters
    if (videoId.length != 11) {
      return false;
    }

    // Try match the regex expression
    return !RegExp(r"[^0-9a-zA-Z_\-]").hasMatch(videoId);
  }

  static String convertUrlToId(String url, [bool trimWhitespaces = true]) {
    if (!url.contains("http") && (url.length == 11)) return url;
    if (url == null || url.length == 0) return null;
    if (trimWhitespaces) url = url.trim();

    for (var exp in [
      RegExp(
          r"^https:\/\/(?:www\.|m\.)?youtube\.com\/watch\?v=([_\-a-zA-Z0-9]{11}).*$"),
      RegExp(
          r"^https:\/\/(?:www\.|m\.)?youtube(?:-nocookie)?\.com\/embed\/([_\-a-zA-Z0-9]{11}).*$"),
      RegExp(r"^https:\/\/youtu\.be\/([_\-a-zA-Z0-9]{11}).*$")
    ]) {
      Match match = exp.firstMatch(url);
      if (match != null && match.groupCount >= 1) return match.group(1);
    }

    return null;
  }
}
